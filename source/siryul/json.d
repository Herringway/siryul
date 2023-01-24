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
		import std.traits : OriginalType;
		if (value.type == JSONType.string) {
			result = value.str.tryConvert!T;
		} else {
			OriginalType!T tmp;
			deserialize(value, path, tmp);
			result = tmp.tryConvert!T;
		}
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (isIntegral!T && !is(T == enum)) {
		expect(value, JSONType.integer, JSONType.string);
		if (value.type == JSONType.string) {
			result = value.str.tryConvert!T;
		} else {
			result = value.integer.tryConvert!T;
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
	void deserialize(T)(JSONValue value, string path, out T result) if (isSumType!T) {
		static foreach (Type; T.Types) {
			try {
				Type tmp;
				deserialize(value, path, tmp);
				trustedAssign(result, tmp); //result has not been initialized yet, so this is safe
				return;
			} catch (JSONDException e) {}
		}
		throw new JSONDException("No matching types");
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (isFloatingPoint!T) {
		expect(value, JSONType.float_, JSONType.integer, JSONType.string);
		if (value.type == JSONType.string) {
			result =value.str.tryConvert!T;
		} else if (value.type == JSONType.integer) {
			result = value.integer.tryConvert!T;
		} else {
			result = value.floating.tryConvert!T;
		}
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (isSomeString!T) {
		expect(value, JSONType.string, JSONType.integer, JSONType.null_, JSONType.float_);
		if (value.type == JSONType.integer) {
			result = value.integer.tryConvert!T;
		} else if (value.type == JSONType.float_) {
			result = value.floating.tryConvert!T;
		} else if (value.type == JSONType.null_) {
			result = T.init;
		} else {
			result = value.str.tryConvert!T;
		}
	}
	void deserialize(T : P*, P)(JSONValue value, string path, out T result) {
		result = new P;
		deserialize(value, path, *result);
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (is(T == struct) && !isSumType!T && !isNullable!T && !hasDeserializationMethod!T && !hasDeserializationTemplate!T) {
		static if (isTimeType!T) {
			string dateString;
			deserialize(value, path, dateString);
			result = T.fromISOExtString(dateString);
		} else static if (is(T : Duration)) {
			string durationString;
			deserialize(value, path, durationString);
			result = fromISODurationString(durationString);
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
					const valueIsAbsent = (memberName !in value.objectNoRef) || (value.objectNoRef[memberName].type == JSONType.null_);
					static if ((hasUDA!(field, Optional) || (!!(flags & DeSiryulize.optionalByDefault)) && !hasUDA!(field, Required)) || hasIndirections!(typeof(field))) {
						if (!hasConvertFromFunc!(T, field) && valueIsAbsent) {
							continue;
						}
					} else {
						enforce!JSONDException(memberName in value.objectNoRef, "Missing non-@Optional "~memberName~" in node");
					}
					static if (hasConvertFromFunc!(T, field)) {
						alias fromFunc = getConvertFromFunc!(T, field);
						try {
							Parameters!(fromFunc)[0] param;
							if (!valueIsAbsent) {
								deserialize(value[memberName], newPath, param);
							}
							__traits(getMember, result, member) = fromFunc(param);
						} catch (Exception e) {
							e.msg = "Error deserializing "~newPath~": "~e.msg;
							throw e;
						}
					} else {
						deserialize(value[memberName], newPath, __traits(getMember, result, member));
					}
				}
			}
		}
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (isSomeChar!T) {
		import std.range.primitives : front;
		expect(value, JSONType.string, JSONType.null_);
		if (value.type == JSONType.null_) {
			result = T.init;
		} else {
			result = value.str.front.tryConvert!T;
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
		import std.traits : Parameters;
		Parameters!(deserializationMethod!T) tmp;
		deserialize(value, path, tmp);
		result = deserializationMethod!T(tmp);
	}
	void deserialize(T)(JSONValue value, string path, out T result) if (isAggregateType!T && hasDeserializationTemplate!T) {
		import std.traits : Parameters;
		Parameters!(T.fromSiryulType!())[0] tmp;
		deserialize(value, path, tmp);
		result = deserializationTemplate!T(tmp);
	}
}

template serialize(Serializer : JSON, BitFlags!Siryulize flags) {
	import std.traits : hasUDA, isAggregateType, Unqual;
	private JSONValue serialize(T)(ref const T value) if (is(T == struct) && !isSumType!T && !isNullable!T && !isTimeType!T && !hasSerializationMethod!T && !hasSerializationTemplate!T) {
		import std.traits : FieldNameTuple;
		string[string] arr;
		auto output = JSONValue(arr);
		foreach (member; FieldNameTuple!T) {
			static if (__traits(getProtection, __traits(getMember, T, member)) == "public") {
				if (__traits(getMember, value, member).isSkippableValue!flags) {
					continue;
				}
				enum memberName = getMemberName!(__traits(getMember, T, member));
				static if (hasConvertToFunc!(T, __traits(getMember, T, member))) {
					output[memberName] = serialize(getConvertToFunc!(T, __traits(getMember, T, member))(__traits(getMember, value, member)));
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
	private JSONValue serialize(T)(ref const T value) if (hasUDA!(value, AsString) || is(T == enum)) {
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
