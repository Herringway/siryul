module siryul.json;
import core.time : Duration;
private import siryul.common;
private import std.json : JSONValue, JSONType, parseJSON, toJSON;
private import std.range.primitives : ElementType, isInfinite, isInputRange, isOutputRange;
private import std.traits : isAssociativeArray, isFloatingPoint, isIntegral, isPointer, isSomeChar, isSomeString, isStaticArray;
private import std.typecons;
/++
 + JSON (JavaScript Object Notation) serialization format
 +
 + Note that only strings are supported for associative array keys in this format.
 +/
struct JSON {
	private import std.meta : AliasSeq;
	alias extensions = AliasSeq!".json";
	package static T parseInput(T, DeSiryulize flags, U)(U data, string filename) if (isInputRange!U && isSomeChar!(ElementType!U)) {
		T output;
		deserialize(JSONNode(parseJSON(data)), output, BitFlags!DeSiryulize(flags));
		return output;
	}
	package static string asString(Siryulize flags, T)(T data) {
		const json = serialize!(JSON, BitFlags!Siryulize(flags))(data);
		return toJSON(json, true);
	}
}

struct JSONNode {
	private JSONValue value;
	enum getMark = Nullable!Mark.init;
	bool hasTypeConvertible(T)() const {
		static if (is(T == typeof(null))) {
			return value.type == JSONType.null_;
		} else static if (is(T: const(char)[])) {
			return value.type == JSONType.string;
		} else static if (is(T : bool)) {
			return (value.type == JSONType.true_) || (value.type == JSONType.false_);
		} else static if (is(T == long)) {
			return value.type == JSONType.integer;
		} else static if (is(T == ulong)) {
			return value.type == JSONType.uinteger;
		} else static if (is(T : real)) {
			return value.type == JSONType.float_;
		} else {
			return false;
		}
	}
	bool hasClass(Classification c) const @safe pure {
		final switch (c) {
			case Classification.scalar:
				return (value.type != JSONType.array) && (value.type != JSONType.object);
			case Classification.sequence:
				return value.type == JSONType.array;
			case Classification.mapping:
				return value.type == JSONType.object;
		}
	}
	T getType(T)() {
		static if (is(T: const(char)[])) {
			return value.str;
		} else static if (is(T : bool)) {
			return value.boolean;
		} else static if (is(T : typeof(null))) {
			return value.type == JSONType.null_;
		} else static if (is(T == ulong)) {
			return value.uinteger;
		} else static if (is(T == long)) {
			return value.integer;
		} else static if (is(T : real)) {
			return value.floating;
		} else {
			assert(0, "Cannot represent type");
		}
	}
	JSONNode opIndex(size_t index) @safe {
		return JSONNode(value.arrayNoRef[index]);
	}
	JSONNode opIndex(string index) @safe {
		return JSONNode(value.objectNoRef[index]);
	}
	size_t length() const @safe {
		return value.arrayNoRef.length;
	}
	bool opBinaryRight(string op : "in")(string key) {
		return !!(key in value);
	}
	int opApply(scope int delegate(string k, JSONNode v) @safe dg) @safe {
		foreach (string k, JSONValue v; value.objectNoRef) {
			const result = dg(k, JSONNode(v));
			if (result != 0) {
				return result;
			}
		}
		return 0;
	}
}

private void expect(T...)(JSONValue node, T types, string file = __FILE__, ulong line = __LINE__) {
	import std.algorithm : among;
	import std.exception : enforce;
	enforce(node.type.among(types), new UnexpectedTypeException([types], node.type, file, line));
}

template serialize(Serializer : JSON, BitFlags!Siryulize flags) {
	import std.traits : isAggregateType, Unqual;
	private JSONValue serialize(T)(ref const T value) if (is(T == struct) && !isSumType!T && !isNullable!T && !isTimeType!T && !hasSerializationMethod!T && !hasSerializationTemplate!T) {
		import std.meta : AliasSeq;
		import std.traits : FieldNameTuple;
		string[string] arr;
		auto output = JSONValue(arr);
		foreach (member; FieldNameTuple!T) {
			alias field = AliasSeq!(__traits(getMember, T, member));
			static if (!mustSkip!field && (__traits(getProtection, field) == "public")) {
				if (__traits(getMember, value, member).isSkippableValue!flags) {
					continue;
				}
				enum memberName = getMemberName!field;
				static if (hasConvertToFunc!(T, field)) {
					output[memberName] = serialize(getConvertToFunc!(T, field)(__traits(getMember, value, member)));
				} else {
					output[memberName] = serialize(__traits(getMember, value, member));
				}
			}
		}
		return output;
	}
	private JSONValue serialize(T)(ref const T value) if (isNullable!T) {
		if (value.isNull) {
			return serialize(null);
		} else {
			return serialize(value.get);
		}
	}
	private JSONValue serialize(T)(ref const T value) if (isSumType!T) {
		import std.sumtype : match;
		return value.match!(v => serialize(v));
	}
	private JSONValue serialize(const typeof(null) value) {
		return JSONValue();
	}
	private JSONValue serialize(T)(ref const T value) if (shouldStringify!value || is(T == enum)) {
		import std.conv : text;
		return JSONValue(value.text);
	}
	private JSONValue serialize(T)(ref const T value) if (isPointer!T) {
		return serialize(*value);
	}
	private JSONValue serialize(T)(ref const T value) if (isTimeType!T) {
		return JSONValue(value.toISOExtString());
	}
	private JSONValue serialize(ref const Duration value) {
		import std.conv : text;
		return JSONValue(value.asISO8601String().text);
	}
	private JSONValue serialize(T)(ref const T value) if (isSomeChar!T) {
		return JSONValue([value]);
	}
	private JSONValue serialize(T)(ref const T value) if ((isSomeString!T || isStaticString!T) && !is(T : string)) {
		import std.utf : toUTF8;
		return JSONValue(value[].toUTF8);
	}
	private JSONValue serialize(T)(const T value) if (canStoreUnchanged!(Unqual!T) && !is(T == enum)) {
		return JSONValue(value);
	}
	private JSONValue serialize(T)(ref T values) if (isSimpleList!T && !isNullable!T && !isStaticString!T && !isNullable!T) {
		JSONValue[] output;
		foreach (value; values) {
			output ~= serialize(value);
		}
		return JSONValue(output);
	}
	private JSONValue serialize(T)(ref T values) if (isAssociativeArray!T) {
		JSONValue[string] output;
		foreach (key, value; values) {
			output[key] = serialize(value);
		}
		return JSONValue(output);
	}
	private JSONValue serialize(T)(ref T value) if (isAggregateType!T && hasSerializationMethod!T) {
		return serialize(__traits(getMember, value, __traits(identifier, serializationMethod!T)));
	}
	private JSONValue serialize(T)(ref T value) if (isAggregateType!T && hasSerializationTemplate!T) {
		const v = __traits(getMember, value, __traits(identifier, serializationTemplate!T));
		return serialize(v);
	}
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
	package this(JSONType[] expectedTypes, JSONType unexpectedType, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		import std.conv : text;
		import std.format : format;
		import std.exception : assumeWontThrow, ifThrown;
		super("Expecting JSON types "~assumeWontThrow(format!"%(%s, %)"(expectedTypes))~", got "~assumeWontThrow(unexpectedType.text.ifThrown("Unknown")), file, line);
	}
}

private T tryConvert(T, V)(V value) {
	import std.conv : ConvException, to;
	import std.format : format;
	try {
		return value.to!T;
	} catch (ConvException) {
		throw new JSONDException(format!("Cannot convert value '%s' to type "~T.stringof)(value));
	}
}
