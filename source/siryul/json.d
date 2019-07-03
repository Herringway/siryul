module siryul.json;
private import siryul.common;
private import std.json : JSONValue, JSONType, parseJSON, toJSON;
private import std.range.primitives : ElementType, isInfinite, isInputRange;
private import std.traits : isSomeChar;
private import std.typecons;
/++
 + JSON (JavaScript Object Notation) serialization format
 +
 + Note that only strings are supported for associative array keys in this format.
 +/
struct JSON {
	private import std.meta : AliasSeq;
	package alias types = AliasSeq!".json";
	package enum emptyObject = "{}";
	package static T parseInput(T, DeSiryulize flags, U)(U data) if (isInputRange!U && isSomeChar!(ElementType!U)) {
		return fromJSON!(T,BitFlags!DeSiryulize(flags))(parseJSON(data), T.stringof);
	}
	package static string asString(Siryulize flags, T)(T data) {
		const json = data.toJSON!(BitFlags!Siryulize(flags));
		return toJSON(json, true);
	}
}

private T fromJSON(T, BitFlags!DeSiryulize flags)(JSONValue node, string path = "") if (!isInfinite!T) {
	import std.conv : text, to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.exception : enforce;
	import std.meta : AliasSeq;
	import std.range.primitives : front;
	import std.range : enumerate, isOutputRange;
	import std.traits : arity, FieldNameTuple, ForeachType, getUDAs, hasIndirections, hasUDA, isAssociativeArray, isFloatingPoint, isIntegral, isPointer, isSomeChar, isSomeString, isStaticArray, OriginalType, Parameters, PointerTarget, TemplateArgsOf, ValueType;
	import std.utf : byCodeUnit;
	static if (is(T == struct) && hasDeserializationMethod!T) {
		return deserializationMethod!T(fromJSON!(Parameters!(deserializationMethod!T), flags)(node, path));
	} else static if (is(T == enum)) {
		import std.conv : to;
		if (node.type == JSONType.string)
			return node.str.to!T;
		else
			return fromJSON!(OriginalType!T, flags)(node, path).to!T;
	} else static if (isIntegral!T) {
		expect(node, JSONType.integer, JSONType.string);
		if (node.type == JSONType.string)
			return node.str.to!T;
		return node.integer.to!T;
	} else static if (isNullable!T) {
		T output;
		if (node.type == JSONType.null_)
			output.nullify();
		else
			output = fromJSON!(typeof(output.get), flags)(node, path);
		return output;
	} else static if (isFloatingPoint!T) {
		expect(node, JSONType.float_, JSONType.integer, JSONType.string);
		if (node.type == JSONType.string) {
			return node.str.to!T;
		}
		if (node.type == JSONType.integer) {
			return node.integer.to!T;
		}
		return node.floating.to!T;
	} else static if (isSomeString!T) {
		expect(node, JSONType.string, JSONType.integer, JSONType.null_);
		if (node.type == JSONType.integer)
			return node.integer.to!T;
		if (node.type == JSONType.null_)
			return T.init;
		return node.str.to!T;
	} else static if (isSomeChar!T) {
		expect(node, JSONType.string, JSONType.null_);
		if (node.type == JSONType.null_)
			return T.init;
		return node.str.front.to!T;
	} else static if (is(T == SysTime) || is(T == DateTime) || is(T == Date) || is(T == TimeOfDay)) {
		return T.fromISOExtString(fromJSON!(string, flags)(node, path));
	} else static if (is(T == struct) || (isPointer!T && is(PointerTarget!T == struct))) {
		expect(node, JSONType.object);
		T output;
		static if (isPointer!T) {
			output = new PointerTarget!T;
			alias Undecorated = PointerTarget!T;
		} else {
			alias Undecorated = T;
		}
		foreach (member; FieldNameTuple!Undecorated) {
			static if (__traits(getProtection, __traits(getMember, Undecorated, member)) == "public") {
				debug string newPath = path~"."~member;
				else string newPath = "";
				alias field = AliasSeq!(__traits(getMember, Undecorated, member));
				enum memberName = getMemberName!field;
				static if ((hasUDA!(field, Optional) || (!!(flags & DeSiryulize.optionalByDefault))) || hasIndirections!(typeof(field))) {
					if ((memberName !in node.object) || (node.object[memberName].type == JSONType.null_))
						continue;
				} else {
					enforce!JSONDException(memberName in node.object, "Missing non-@Optional "~memberName~" in node");
				}
				alias fromFunc = getConvertFromFunc!(T, field);
				try {
					static if (hasUDA!(field, IgnoreErrors)) {
						try {
							__traits(getMember, output, member) = fromFunc(fromJSON!(Parameters!(fromFunc)[0], flags)(node[memberName], newPath));
						} catch (UnexpectedTypeException) {} //just skip it
					} else {
						__traits(getMember, output, member) = fromFunc(fromJSON!(Parameters!(fromFunc)[0], flags)(node[memberName], newPath));
					}
				} catch (Exception e) {
					e.msg = "Error deserializing "~newPath~": "~e.msg;
					throw e;
				}
			}
		}
		return output;
	} else static if(isOutputRange!(T, ElementType!T)) {
		import std.algorithm : copy, map;
		expect(node, JSONType.array);
		T output = new T(node.array.length);
		copy(node.array.map!(x => fromJSON!(ElementType!T, flags)(x, path)), output);
		return output;
	} else static if (isStaticArray!T && isSomeChar!(ElementType!T)) {
		expect(node, JSONType.string);
		T output;
		foreach (i, chr; fromJSON!((ForeachType!T)[], flags)(node, path).byCodeUnit.enumerate(0))
			output[i] = chr;
		return output;
	} else static if(isStaticArray!T) {
		expect(node, JSONType.array);
		enforce!JSONDException(node.array.length == T.length, "Static array length mismatch");
		T output;
		foreach (i, JSONValue newNode; node.array)
			output[i] = fromJSON!(ForeachType!T, flags)(newNode, path);
		return output;
	} else static if(isAssociativeArray!T) {
		expect(node, JSONType.object);
		T output;
		foreach (string key, JSONValue value; node.object)
			output[key] = fromJSON!(ValueType!T, flags)(value, path);
		return output;
	} else static if (is(T == bool)) {
		expect(node, JSONType.true_, JSONType.false_);
		if (node.type == JSONType.true_)
			return true;
		else if (node.type == JSONType.false_)
			return false;
		assert(false);
	} else
		static assert(false, "Cannot read type "~T.stringof~" from JSON"); //unreachable, hopefully.
}
private void expect(T...)(JSONValue node, T types) {
	import std.algorithm : among;
	import std.exception : enforce;
	enforce(node.type.among(types), new UnexpectedTypeException(types[0], node.type));
}
private @property JSONValue toJSON(BitFlags!Siryulize flags, T)(T type) if (!isInfinite!T) {
	import std.conv : text, to;
	import std.meta : AliasSeq;
	import std.range : isInputRange;
	import std.traits : arity, FieldNameTuple, getSymbolsByUDA, getUDAs, hasUDA, isArray, isAssociativeArray, isPointer, isSomeChar, isSomeString, isStaticArray, PointerTarget, Unqual;
	JSONValue output;
	static if (isPointer!T) {
		alias Undecorated = Unqual!(PointerTarget!T);
	} else {
		alias Undecorated = Unqual!T;
	}
	static if (is(T == struct) && hasSerializationMethod!T) {
		output = toJSON!flags(mixin("type."~__traits(identifier, serializationMethod!T)));
	} else static if (hasUDA!(type, AsString) || is(Undecorated == enum)) {
		output = JSONValue(type.text);
	} else static if (isNullable!Undecorated) {
		if (type.isNull && !(flags & Siryulize.omitNulls)) {
			output = JSONValue();
		} else {
			output = type.get().toJSON!flags;
		}
	} else static if (isTimeType!Undecorated) {
		output = JSONValue(type.toISOExtString());
	} else static if (canStoreUnchanged!Undecorated) {
		output = JSONValue(type.to!Undecorated);
	} else static if (isSomeString!Undecorated || (isStaticArray!Undecorated && isSomeChar!(ElementType!Undecorated))) {
		import std.utf : toUTF8;
		output = JSONValue(type[].toUTF8);
	} else static if (isSomeChar!Undecorated) {
		output = [type].idup.toJSON!flags;
	} else static if (isAssociativeArray!Undecorated) {
		string[string] arr;
		output = JSONValue(arr);
		foreach (key, value; type) {
			output.object[key] = value.toJSON!flags;
		}
	} else static if (isSimpleList!Undecorated) {
		string[] arr;
		output = JSONValue(arr);
		foreach (value; type) {
			output.array ~= value.toJSON!flags;
		}
	} else static if (is(Undecorated == struct)) {
		string[string] arr;
		output = JSONValue(arr);
		foreach (member; FieldNameTuple!Undecorated) {
			static if (__traits(getProtection, __traits(getMember, Undecorated, member)) == "public") {
				static if (!!(flags & Siryulize.omitInits)) {
					static if (isNullable!(typeof(__traits(getMember, T, member)))) {
						if (__traits(getMember, type, member).isNull) {
							continue;
						}
					} else {
						if (__traits(getMember, type, member) == __traits(getMember, type, member).init) {
							continue;
						}
					}
				}
				enum memberName = getMemberName!(__traits(getMember, Undecorated, member));
				output.object[memberName] = getConvertToFunc!(T, __traits(getMember, Undecorated, member))(mixin("type."~member)).toJSON!flags;
			}
		}
	} else {
		static assert(false, "Cannot write type "~T.stringof~" to JSON"); //unreachable, hopefully
	}
	return output;
}
private template isTimeType(T) {
	import std.datetime : DateTime, Date, SysTime, TimeOfDay;
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
	this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
/++
+ Thrown when a JSON value has an unexpected type.
+/
class UnexpectedTypeException : JSONDException {
	package this(JSONType expectedType, JSONType unexpectedType, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		import std.conv : text;
		import std.exception : assumeWontThrow, ifThrown;
		super("Expecting JSON type "~assumeWontThrow(expectedType.text.ifThrown("Unknown"))~", got "~assumeWontThrow(unexpectedType.text.ifThrown("Unknown")), file, line);
	}
}