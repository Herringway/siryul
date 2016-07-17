module siryul.json;
private import siryul.common;
private import std.json : JSONValue, parseJSON, toJSON, JSON_TYPE;
private import std.range.primitives : isInputRange, ElementType, isInfinite;
private import std.typecons;
private import std.traits : isSomeChar;
/++
 + JSON (JavaScript Object Notation) serialization format
 +
 + Note that only strings are supported for associative array keys in this format.
 +/
struct JSON {
	private import std.meta : AliasSeq;
	package alias types = AliasSeq!".json";
	enum emptyObject = "{}";
	package static T parseInput(T, DeSiryulize flags, U)(U data) @trusted if (isInputRange!U && isSomeChar!(ElementType!U)) {
		return parseJSON(data).fromJSON!(T,BitFlags!DeSiryulize(flags));
	}
	package static string asString(Siryulize flags, T)(T data) @trusted {
		auto json = data.toJSON!(BitFlags!Siryulize(flags));
		return (&json).toJSON(true);
	}
}

private T fromJSON(T, BitFlags!DeSiryulize flags)(JSONValue node) @trusted if (!isInfinite!T) {
	import std.traits : isSomeString, isSomeChar, isAssociativeArray, isStaticArray, isFloatingPoint, isIntegral, FieldNameTuple, hasUDA, getUDAs, hasIndirections, ValueType, OriginalType, TemplateArgsOf, arity, Parameters, ForeachType;
	import std.exception : enforce;
	import std.datetime : SysTime, DateTime, Date, TimeOfDay;
	import std.range : isOutputRange, enumerate;
	import std.conv : to, text;
	import std.range.primitives : front;
	import std.utf : byCodeUnit;
	import std.conv : to;
	import std.meta : AliasSeq;
	static if (is(T == enum)) {
		import std.conv : to;
		if (node.type == JSON_TYPE.STRING)
			return node.str.to!T;
		else
			return node.fromJSON!(OriginalType!T, flags).to!T;
	} else static if (isIntegral!T) {
		if (node.type == JSON_TYPE.STRING)
			return node.str.to!T;
		expect(node, JSON_TYPE.INTEGER);
		return node.integer.to!T;
	} else static if (isNullable!T) {
		T output;
		if (node.type == JSON_TYPE.NULL)
			output.nullify();
		else
			output = node.fromJSON!(TemplateArgsOf!T[0], flags);
		return output;
	} else static if (isFloatingPoint!T) {
		if (node.type == JSON_TYPE.STRING)
			return node.str.to!T;
		expect(node, JSON_TYPE.FLOAT);
		return node.floating.to!T;
	} else static if (isSomeString!T) {
		if (node.type == JSON_TYPE.INTEGER)
			return node.integer.to!T;
		if (node.type == JSON_TYPE.NULL)
			return T.init;
		return node.str.to!T;
	} else static if (isSomeChar!T) {
		expect(node, JSON_TYPE.STRING, JSON_TYPE.NULL);
		if (node.type == JSON_TYPE.NULL)
			return T.init;
		return node.str.front.to!T;
	} else static if (is(T == SysTime) || is(T == DateTime) || is(T == Date) || is(T == TimeOfDay)) {
		return T.fromISOExtString(node.fromJSON!(string, flags));
	} else static if (is(T == struct)) {
		expect(node, JSON_TYPE.OBJECT);
		T output;
		foreach (member; FieldNameTuple!T) {
			alias field = AliasSeq!(__traits(getMember, output, member));
			enum memberName = getMemberName!field;
			static if ((hasUDA!(field, Optional) || (!!(flags & DeSiryulize.optionalByDefault))) || hasIndirections!(typeof(field))) {
				if ((memberName !in node.object) || (node.object[memberName].type == JSON_TYPE.NULL))
					continue;
			} else
				enforce(memberName in node.object, new JSONDException("Missing non-@Optional "~memberName~" in node"));
			alias fromFunc = getConvertFromFunc!(T, field);
			__traits(getMember, output, member) = fromFunc(node[memberName].fromJSON!(Parameters!(fromFunc)[0], flags));
		}
		return output;
	} else static if(isOutputRange!(T, ElementType!T)) {
		expect(node, JSON_TYPE.ARRAY);
		T output = new T(node.array.length);
		size_t i;
		foreach (JSONValue newNode; node.array)
			output[i++] = fromJSON!(ElementType!T, flags)(newNode);
		return output;
	} else static if (isStaticArray!T && isSomeChar!(ElementType!T)) {
		expect(node, JSON_TYPE.STRING);
		T output;
		foreach (i, chr; node.fromJSON!((ForeachType!T)[], flags).byCodeUnit.enumerate(0))
			output[i] = chr;
		return output;
	} else static if(isStaticArray!T) {
		expect(node, JSON_TYPE.ARRAY);
		enforce(node.array.length == T.length, new JSONDException("Static array length mismatch"));
		T output;
		foreach (i, JSONValue newNode; node.array)
			output[i] = fromJSON!(ForeachType!T, flags)(newNode);
		return output;
	} else static if(isAssociativeArray!T) {
		expect(node, JSON_TYPE.OBJECT);
		T output;
		foreach (string key, JSONValue value; node.object)
			output[key] = fromJSON!(ValueType!T, flags)(value);
		return output;
	} else static if (is(T == bool)) {
		if (node.type == JSON_TYPE.TRUE)
			return true;
		else if (node.type == JSON_TYPE.FALSE)
			return false;
		throw new JSONDException("Expecting true/false, got "~node.type.text);
	} else
		static assert(false, "Cannot read type "~T.stringof~" from JSON"); //unreachable, hopefully.
}
void expect(T...)(JSONValue node, T types) {
	import std.exception : enforce;
	import std.algorithm : among;
	enforce(node.type.among(types), new UnexpectedTypeException(types[0], node.type));
}
private @property JSONValue toJSON(BitFlags!Siryulize flags, T)(T type) @trusted if (!isInfinite!T) {
	import std.traits : isAssociativeArray, isArray, isSomeString, isSomeChar, FieldNameTuple, hasUDA, getUDAs, arity, Unqual, isStaticArray;
	import std.range : isInputRange;
	import std.conv : text, to;
	import std.meta : AliasSeq;
	JSONValue output;
	alias Undecorated = Unqual!T;
	static if (hasUDA!(type, AsString) || is(Undecorated == enum)) {
		output = JSONValue(type.text);
	} else static if (isNullable!Undecorated) {
		if (type.isNull && !(flags & Siryulize.omitNulls))
			output = JSONValue();
		else
			output = type.get().toJSON!flags;
	} else static if (isTimeType!Undecorated) {
		output = JSONValue(type.toISOExtString());
	} else static if (canStoreUnchanged!Undecorated) {
		output = JSONValue(type.to!Undecorated);
	} else static if (isSomeString!Undecorated || (isStaticArray!Undecorated && isSomeChar!(ElementType!Undecorated))) {
		import std.utf : toUTF8;
		output = JSONValue(type.toUTF8);
	} else static if (isSomeChar!Undecorated) {
		output = [type].idup.toJSON!flags;
	} else static if (isAssociativeArray!Undecorated) {
		string[string] arr;
		output = JSONValue(arr);
		foreach (key, value; type)
			output.object[key.text] = value.toJSON!flags;
	} else static if (isSimpleList!Undecorated) {
		string[] arr;
		output = JSONValue(arr);
		foreach (value; type)
			output.array ~= value.toJSON!flags;
	} else static if (is(Undecorated == struct)) {
		string[string] arr;
		output = JSONValue(arr);
		foreach (member; FieldNameTuple!T) {
			static if (!!(flags & Siryulize.omitInits)) {
				static if (isNullable!(typeof(__traits(getMember, T, member)))) {
					if (__traits(getMember, type, member).isNull)
						continue;
				} else
					if (__traits(getMember, type, member) == __traits(getMember, type, member).init)
						continue;
			}
			enum memberName = getMemberName!(__traits(getMember, T, member));
			output.object[memberName] = getConvertToFunc!(T, __traits(getMember, type, member))(__traits(getMember, type, member)).toJSON!flags;
		}
	} else
		static assert(false, "Cannot write type "~T.stringof~" to JSON"); //unreachable, hopefully
	return output;
}
private template isTimeType(T) {
	import std.datetime : DateTime, Date, TimeOfDay, SysTime;
	enum isTimeType = is(T == SysTime) || is(T == DateTime) || is(T == Date) || is(T == TimeOfDay);
}
private template canStoreUnchanged(T) {
	import std.traits : isFloatingPoint, isIntegral;
	enum canStoreUnchanged = isIntegral!T || is(T == string) || is(T == bool) || isFloatingPoint!T;
}
/++
 + Thrown on JSON deserialization errors
 +/
class JSONDException : DeserializeException {
	package this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
class UnexpectedTypeException : JSONDException {
	package this(JSON_TYPE expectedType, JSON_TYPE unexpectedType, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		import std.conv : text;
		string str;
		try {
			str = "Expecting JSON type "~expectedType.text~", got "~unexpectedType.text;
		} catch (Exception) {
			str = "Bad JSON type";
		}
		super(str, file, line);
	}
}
/++
 + Thrown on JSON serialization errors
 +/
class JSONSException : DeserializeException {
	package this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}