module siryul.json;
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
		deserialize!(JSON, BitFlags!DeSiryulize(flags))(parseJSON(data), T.stringof, output);
		return output;
	}
	package static string asString(Siryulize flags, T)(T data) {
		const json = serialize!(JSON, BitFlags!Siryulize(flags))(data);
		return toJSON(json, true);
	}
}

private void expect(T...)(JSONValue node, T types, string file = __FILE__, ulong line = __LINE__) {
	import std.algorithm : among;
	import std.exception : enforce;
	enforce(node.type.among(types), new UnexpectedTypeException([types], node.type, file, line));
}
template deserialize(Serializer : JSON, BitFlags!DeSiryulize flags) {
	import std.traits : isAggregateType;
	void deserialize(T)(JSONValue value, string path, out T result) if (is(T == enum)) {
		import std.conv : to;
		import std.traits : OriginalType;
		if (value.type == JSONType.string) {
			result = value.str.to!T;
		} else {
			OriginalType!T tmp;
			deserialize(value, path, tmp);
			result = tmp.to!T;
		}
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (isIntegral!T && !is(T == enum)) {
		import std.conv : to;
		expect(value, JSONType.integer, JSONType.string);
		if (value.type == JSONType.string) {
			result = value.str.to!T;
		} else {
			result = value.integer.to!T;
		}
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (isNullable!T) {
		if (value.type == JSONType.null_) {
			result.nullify();
		} else {
			typeof(result.get) tmp;
			deserialize(value, path, tmp);
			result = tmp;
		}
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (isFloatingPoint!T) {
		import std.conv : to;
		expect(value, JSONType.float_, JSONType.integer, JSONType.string);
		if (value.type == JSONType.string) {
			result =value.str.to!T;
		} else if (value.type == JSONType.integer) {
			result = value.integer.to!T;
		} else {
			result = value.floating.to!T;
		}
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (isSomeString!T) {
		import std.conv : to;
		expect(value, JSONType.string, JSONType.integer, JSONType.null_, JSONType.float_);
		if (value.type == JSONType.integer) {
			result = value.integer.to!T;
		} else if (value.type == JSONType.float_) {
			result = value.floating.to!T;
		} else if (value.type == JSONType.null_) {
			result = T.init;
		} else {
			result = value.str.to!T;
		}
	}
	void deserialize(T : P*, P)(JSONValue value, string path, out T result) {
		result = new P;
		deserialize(value, path, *result);
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (is(T == struct) && !isNullable!T && !hasDeserializationMethod!T) {
		static if (isTimeType!T) {
			string dateString;
			deserialize(value, path, dateString);
			result = T.fromISOExtString(dateString);
		} else {
			import std.exception : enforce;
			import std.meta : AliasSeq;
			import std.traits : arity, FieldNameTuple, ForeachType, getUDAs, hasIndirections, hasUDA, isAssociativeArray, isFloatingPoint, isIntegral, isPointer, isSomeChar, isSomeString, isStaticArray, OriginalType, Parameters, PointerTarget, TemplateArgsOf, ValueType;
			expect(value, JSONType.object);
			foreach (member; FieldNameTuple!T) {
				static if (__traits(getProtection, __traits(getMember, T, member)) == "public") {
					debug string newPath = path~"."~member;
					else string newPath = path;
					alias field = AliasSeq!(__traits(getMember, T, member));
					enum memberName = getMemberName!field;
					static if ((hasUDA!(field, Optional) || (!!(flags & DeSiryulize.optionalByDefault)) && !hasUDA!(field, Required)) || hasIndirections!(typeof(field))) {
						if ((memberName !in value.objectNoRef) || (value.objectNoRef[memberName].type == JSONType.null_)) {
							continue;
						}
					} else {
						enforce!JSONDException(memberName in value.objectNoRef, "Missing non-@Optional "~memberName~" in node");
					}
					alias fromFunc = getConvertFromFunc!(T, field);
					try {
						Parameters!(fromFunc)[0] param;
						static if (hasUDA!(field, IgnoreErrors)) {
							try {
								deserialize(value[memberName], newPath, param);
								__traits(getMember, result, member) = fromFunc(param);
							} catch (UnexpectedTypeException) {} //just skip it
						} else {
							deserialize(value[memberName], newPath, param);
							__traits(getMember, result, member) = fromFunc(param);
						}
					} catch (Exception e) {
						e.msg = "Error deserializing "~newPath~": "~e.msg;
						throw e;
					}
				}
			}
		}
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (isSomeChar!T) {
		import std.conv : to;
		import std.range.primitives : front;
		expect(value, JSONType.string, JSONType.null_);
		if (value.type == JSONType.null_) {
			result = T.init;
		} else {
			result = value.str.front.to!T;
		}
	}
	void deserialize(T)(JSONValue values, string path, out T result) if (isOutputRange!(T, ElementType!T) && !isSomeString!T && !isNullable!T) {
		import std.conv : text;
		expect(values, JSONType.array);
		result = new T(values.arrayNoRef.length);
		foreach (idx, ref element; result) {
			debug string newPath = path ~ "["~idx.text~"]";
			else string newPath = path;
			deserialize(values[idx], newPath, element);
		}
	}
	void deserialize(T)(JSONValue values, string path, out T result) if (isStaticArray!T) {
		import std.conv : text;
		import std.traits : ForeachType;
		static if (isSomeChar!(ElementType!T)) {
			import std.range : enumerate;
			import std.utf : byCodeUnit;
			expect(values, JSONType.string);
			string str;
			deserialize(values, path, str);
			foreach (i, ref chr; result) {
				chr = str[i];
			}
		} else {
			import std.exception : enforce;
			expect(values, JSONType.array);
			enforce!JSONDException(values.arrayNoRef.length == T.length, "Static array length mismatch");
			foreach (i, JSONValue newNode; values.arrayNoRef) {
				debug string newPath = path ~ "["~i.text~"]";
				else string newPath = path;
				deserialize(newNode, newPath, result[i]);
			}
		}
	}

	void deserialize(T)(JSONValue values, string path, out T result) if (isAssociativeArray!T) {
		import std.traits : ValueType;
		expect(values, JSONType.object);
		foreach (string key, JSONValue value; values.objectNoRef) {
			debug string newPath = path ~ "["~key~"]";
			else string newPath = path;
			ValueType!T v;
			deserialize(value, newPath, v);
			result[key] = v;
		}
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (is(T == bool)) {
		expect(value, JSONType.true_, JSONType.false_);
		if (value.type == JSONType.true_) {
			result = true;
		} else if (value.type == JSONType.false_) {
			result = false;
		} else {
			assert(false);
		}
	}
	void deserialize(JSONValue, string, out typeof(null)) {}
	void deserialize(T)(JSONValue value, string path, out T result) if (isAggregateType!T && hasDeserializationMethod!T) {
		Parameters!(deserializationMethod!T) tmp;
		deserialize(value, path, tmp);
		result = deserializationMethod!T(tmp);
	}
}

template serialize(Serializer : JSON, BitFlags!Siryulize flags) {
	import std.traits : hasUDA, isAggregateType;
	private JSONValue serialize(T)(auto ref const T value) if (is(T == struct) && !isNullable!T && !isTimeType!T && !hasSerializationMethod!T) {
		import std.traits : FieldNameTuple;
		string[string] arr;
		auto output = JSONValue(arr);
		foreach (member; FieldNameTuple!T) {
			static if (__traits(getProtection, __traits(getMember, T, member)) == "public") {
				if (__traits(getMember, value, member).isSkippableValue(flags)) {
					continue;
				}
				enum memberName = getMemberName!(__traits(getMember, T, member));
				output.object[memberName] = serialize(getConvertToFunc!(T, __traits(getMember, T, member))(__traits(getMember, value, member)));
			}
		}
		return output;
	}
	private JSONValue serialize(T)(auto ref const T value) if (isNullable!T) {
		if (value.isNull) {
			return serialize(null);
		} else {
			return serialize(value.get);
		}
	}
	private JSONValue serialize(const typeof(null) value) {
		return JSONValue();
	}
	private JSONValue serialize(T)(auto ref const T value) if (hasUDA!(value, AsString) || is(T == enum)) {
		import std.conv : text;
		return JSONValue(value.text);
	}
	private JSONValue serialize(T)(auto ref const T value) if (isPointer!T) {
		return serialize(*value);
	}
	private JSONValue serialize(T)(auto ref const T value) if (isTimeType!T) {
		return JSONValue(value.toISOExtString());
	}
	private JSONValue serialize(T)(auto ref const T value) if (isSomeChar!T) {
		return JSONValue([value]);
	}
	private JSONValue serialize(T)(auto ref const T value) if ((isSomeString!T || isStaticString!T) && !is(T : string)) {
		import std.utf : toUTF8;
		return JSONValue(value[].toUTF8);
	}
	private JSONValue serialize(T)(auto ref const T value) if (canStoreUnchanged!T && !is(T == enum)) {
		return JSONValue(value);
	}
	private JSONValue serialize(T)(auto ref T values) if (isSimpleList!T && !isNullable!T && !isStaticString!T && !isNullable!T) {
		string[] arr;
		auto output = JSONValue(arr);
		foreach (value; values) {
			output.array ~= serialize(value);
		}
		return output;
	}
	private JSONValue serialize(T)(auto ref T values) if (isAssociativeArray!T) {
		string[string] arr;
		auto output = JSONValue(arr);
		foreach (key, value; values) {
			output.object[key] = serialize(value);
		}
		return output;
	}
	private JSONValue serialize(T)(auto ref T value) if (isAggregateType!T && hasSerializationMethod!T) {
		return serialize(__traits(getMember, value, __traits(identifier, serializationMethod!T)));
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