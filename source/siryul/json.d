module siryul.json;
private import siryul;
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
	package static T parseInput(T, DeSiryulize flags, U)(U data) @trusted if (isInputRange!U && isSomeChar!(ElementType!U)) {
		return parseJSON(data).fromJSON!(T,BitFlags!DeSiryulize(flags));
	}
	package static string asString(Siryulize flags, T)(T data) @trusted {
		auto json = data.toJSON!(BitFlags!Siryulize(flags));
		return (&json).toJSON(true);
	}
}

private T fromJSON(T, BitFlags!DeSiryulize flags)(JSONValue node) @trusted if (!isInfinite!T) {
	import std.traits : isSomeString, isSomeChar, isAssociativeArray, isStaticArray, isFloatingPoint, isIntegral, FieldNameTuple, hasUDA, hasIndirections, ValueType, OriginalType, TemplateArgsOf, arity, Parameters;
	import std.exception : enforce;
	import std.datetime : SysTime, DateTime, Date, TimeOfDay;
	import std.range : isOutputRange;
	import std.conv : to, text;
	import std.range.primitives : front;
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
		enforce(node.type == JSON_TYPE.INTEGER, new UnexpectedTypeException(JSON_TYPE.INTEGER, node.type));
		return node.integer.to!T;
	} else static if (isNullable!T) {
		T output;
		if (node.type == JSON_TYPE.NULL)
			output.nullify();
		else
			static if (isNullableValue!T) {
				output = node.fromJSON!(TemplateArgsOf!T[0], flags);
			} else {
				auto val = node.fromJSON!(TemplateArgsOf!T[0], flags);
				() @trusted {
					output.bind(moveToHeap(val));
				}();
			}
		return output;
	} else static if (isFloatingPoint!T) {
		if (node.type == JSON_TYPE.STRING)
			return node.str.to!T;
		enforce(node.type == JSON_TYPE.FLOAT, new UnexpectedTypeException(JSON_TYPE.FLOAT, node.type));
		return node.floating.to!T;
	} else static if (isSomeString!T) {
		if (node.type == JSON_TYPE.INTEGER)
			return node.integer.to!T;
		if (node.type == JSON_TYPE.NULL)
			return T.init;
		return node.str.to!T;
	} else static if (isSomeChar!T) {
		enforce(node.type == JSON_TYPE.STRING || node.type == JSON_TYPE.NULL, new UnexpectedTypeException(JSON_TYPE.STRING, node.type));
		if (node.type == JSON_TYPE.NULL)
			return T.init;
		return node.str.front.to!T;
	} else static if (is(T == SysTime) || is(T == DateTime) || is(T == Date) || is(T == TimeOfDay)) {
		return T.fromISOExtString(node.fromJSON!(string, flags));
	} else static if (is(T == struct)) {
		enforce(node.type == JSON_TYPE.OBJECT, new UnexpectedTypeException(JSON_TYPE.OBJECT, node.type));
		T output;
		foreach (member; FieldNameTuple!T) {
			string memberName = member;
			static if (hasUDA!(__traits(getMember, T, member), SiryulizeAs)) {
				memberName = getUDAValue!(__traits(getMember, T, member), SiryulizeAs).name;
			}
			static if ((hasUDA!(__traits(getMember, T, member), Optional) || (!!(flags & DeSiryulize.optionalByDefault))) || hasIndirections!(typeof(__traits(getMember, T, member)))) {
				if ((memberName !in node.object) || (node.object[memberName].type == JSON_TYPE.NULL))
					continue;
			} else
				enforce(memberName in node.object, new JSONDException("Missing non-@Optional "~memberName~" in node"));
			static if (hasUDA!(__traits(getMember, T, member), CustomParser)) {
				alias fromFunc = AliasSeq!(__traits(getMember, output, getUDAValue!(__traits(getMember, output, member), CustomParser).fromFunc))[0];
				assert(arity!fromFunc == 1, "Arity of conversion function must be exactly 1");
				__traits(getMember, output, member) = fromFunc(node[memberName].fromJSON!(Parameters!(fromFunc)[0], flags));
			} else
				__traits(getMember, output, member) = fromJSON!(typeof(__traits(getMember, T, member)), flags)(node[memberName]);
		}
		return output;
	} else static if(isOutputRange!(T, ElementType!T)) {
		enforce(node.type == JSON_TYPE.ARRAY, new UnexpectedTypeException(JSON_TYPE.ARRAY, node.type));
		T output = new T(node.array.length);
		size_t i;
		foreach (JSONValue newNode; node.array)
			output[i++] = fromJSON!(ElementType!T, flags)(newNode);
		return output;
	} else static if(isStaticArray!T) {
		enforce(node.type == JSON_TYPE.ARRAY, new UnexpectedTypeException(JSON_TYPE.ARRAY, node.type));
		enforce(node.array.length == T.length, new JSONDException("Static array length mismatch"));
		T output;
		size_t i;
		foreach (JSONValue newNode; node.array)
			output[i++] = fromJSON!(ElementType!T, flags)(newNode);
		return output;
	} else static if(isAssociativeArray!T) {
		enforce(node.type == JSON_TYPE.OBJECT, new UnexpectedTypeException(JSON_TYPE.OBJECT, node.type));
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

private @property JSONValue toJSON(BitFlags!Siryulize flags, T)(T type) @trusted if (!isInfinite!T) {
	import std.traits : isIntegral, isAssociativeArray, isArray, isFloatingPoint, isSomeString, isSomeChar, FieldNameTuple, hasUDA, arity;
	import std.datetime : DateTime, Date, TimeOfDay, SysTime;
	import std.range : isInputRange;
	import std.conv : text;
	import std.meta : AliasSeq;
	JSONValue output;
	static if (hasUDA!(type, AsString) || is(T == enum)) {
		output = JSONValue(type.text);
	} else static if (isNullable!T) {
		if (type.isNull && !(flags & Siryulize.omitNulls))
			output = JSONValue();
		else
			output = type.get().toJSON!flags;
	} else static if (is(T == SysTime) || is(T == DateTime) || is(T == Date) || is(T == TimeOfDay)) {
		output = JSONValue(type.toISOExtString());
	} else static if (isIntegral!T || is(T == string) || is(T == bool) || isFloatingPoint!T) {
		output = JSONValue(type);
	} else static if (isSomeString!T) {
		import std.utf : toUTF8;
		output = JSONValue(type.toUTF8);
	} else static if (isSomeChar!T) {
		output = [type].idup.toJSON!flags;
	} else static if (isAssociativeArray!T) {
		string[string] arr;
		output = JSONValue(arr);
		foreach (key, value; type)
			output.object[key.text] = value.toJSON!flags;
	} else static if(isInputRange!T || isArray!T) {
		string[] arr;
		output = JSONValue(arr);
		foreach (value; type)
			output.array ~= value.toJSON!flags;
	} else static if (is(T == struct)) {
		string[string] arr;
		output = JSONValue(arr);
		foreach (member; FieldNameTuple!T) {
			static if (!!(flags & Siryulize.omitInits)) {
				static if (isNullable!(__traits(getMember, T, member))) {
					if (__traits(getMember, type, member).isNull)
						continue;
				} else
					if (__traits(getMember, type, member) == __traits(getMember, type, member).init)
						continue;
			}
			string memberName = member;
			static if (hasUDA!(__traits(getMember, T, member), SiryulizeAs))
				memberName = getUDAValue!(__traits(getMember, T, member), SiryulizeAs).name;
			static if (hasUDA!(__traits(getMember, T, member), CustomParser)) {
				alias toFunc = AliasSeq!(__traits(getMember, type, getUDAValue!(__traits(getMember, type, member), CustomParser).toFunc))[0];
				assert(arity!toFunc == 1, "Arity of conversion function must be exactly 1");
				output.object[memberName] = toFunc(__traits(getMember, type, member)).toJSON!flags;
			} else
				output.object[memberName] = __traits(getMember, type, member).toJSON!flags;
		}
	} else
		static assert(false, "Cannot write type "~T.stringof~" to JSON"); //unreachable, hopefully
	return output;
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