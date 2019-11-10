module siryul.dyaml;
import dyaml;
import siryul.common;
import std.range.primitives : ElementType, isInfinite, isInputRange;
import std.traits : isSomeChar;
import std.typecons;

/++
 + YAML (YAML Ain't Markup Language) serialization format
 +/
struct YAML {
	private import std.meta : AliasSeq;
	package alias types = AliasSeq!(".yml", ".yaml");
	package static T parseInput(T, DeSiryulize flags, U)(U data) if (isInputRange!U && isSomeChar!(ElementType!U)) {
		import std.conv : to;
		import std.utf : byChar;
		auto str = data.byChar.to!(char[]);
		auto loader = Loader.fromString(str).load();
		try {
			T result;
			deserialize!(YAML, BitFlags!DeSiryulize(flags))(loader, "", result);
			return result;
		} catch (NodeException e) {
			debug(norethrow) throw e;
			else throw new YAMLDException(e.msg);
		}
	}
	package static string asString(Siryulize flags, T)(T data) {
		import std.array : appender;
		auto buf = appender!string;
		auto dumper = dumper();
		dumper.defaultCollectionStyle = CollectionStyle.block;
		dumper.defaultScalarStyle = ScalarStyle.plain;
		dumper.explicitStart = false;
		dumper.dump(buf, serialize!(YAML, BitFlags!Siryulize(flags))(data));
		return buf.data;
	}
}
/++
 + Thrown on YAML deserialization errors
 +/
class YAMLDException : DeserializeException {
	this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
/++
 + Thrown on YAML serialization errors
 +/
class YAMLSException : SerializeException {
	this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
template deserialize(Serializer : YAML, BitFlags!DeSiryulize flags) {
	import std.conv : to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.exception : enforce;
	import std.range : enumerate, isOutputRange, put;
	import std.traits : arity, FieldNameTuple, ForeachType, getUDAs, hasIndirections, hasUDA, isArray, isAssociativeArray, isFloatingPoint, isIntegral, isPointer, isSomeString, isStaticArray, KeyType, OriginalType, Parameters, PointerTarget, TemplateArgsOf, ValueType;
	import std.utf : byCodeUnit;
	void deserialize(T)(Node value, string path, out T result) if (is(T == enum)) {
		import std.conv : to;
		import std.traits : OriginalType;
		enforce!YAMLDException(value.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
		if (value.tag == `tag:yaml.org,2002:str`) {
			result = value.get!string.to!T;
		} else {
			OriginalType!T tmp;
			deserialize(value, path, tmp);
			result = tmp.to!T;
		}
	}
	void deserialize(T)(Node value, string path, out T result) if (is(T == TimeOfDay)) {
		enforce!YAMLDException(value.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
		result = TimeOfDay.fromISOExtString(value.get!string);
	}
	void deserialize(T)(Node value, string path, out T result) if (isNullable!T) {
		if (value.type == NodeType.null_) {
			result.nullify();
		} else {
			typeof(result.get) tmp;
			deserialize(value, path, tmp);
			result = tmp;
		}
	}
	void deserialize(Node value, string path, out bool result) {
		enforce!YAMLDException(value.tag == `tag:yaml.org,2002:bool`, "Expecting a boolean value");
		result = value.get!bool;
	}
	void deserialize(V, K)(Node value, string path, out V[K] result) {
		enforce!YAMLDException(value.nodeID == NodeID.mapping, "Attempted to read a non-mapping as a "~(V[K]).stringof);
		foreach (Node k, Node v; value) {
			K key;
			V val;
			deserialize(k, path, key);
			deserialize(v, path, val);
			result[key] = val;
		}
	}
	void deserialize(T, size_t N)(Node value, string path, out T[N] result) {
		static if (isSomeChar!T) {
			enforce!YAMLDException(value.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~(T[N]).stringof);
			ForeachType!(T[N])[] str;
			deserialize(value, path, str);
			foreach (i, chr; str.byCodeUnit.enumerate(0)) {
				enforce!YAMLDException(i < N, "Static array too small to contain all elements");
				result[i] = chr;
			}
			return;
		} else {
			enforce!YAMLDException(value.nodeID == NodeID.sequence, "Attempted to read a non-sequence as a "~(T[N]).stringof);
			size_t i;
			foreach (Node newNode; value) {
				enforce!YAMLDException(i < N, "Static array too small to contain all elements");
				deserialize(newNode, path, result[i++]);
			}
			return;
		}
	}
	void deserialize(T)(Node value, string path, out T result) if (isOutputRange!(T, ElementType!T) && !isSomeString!T) {
		if (value.type != NodeType.null_) {
			enforce!YAMLDException(value.nodeID == NodeID.sequence, "Attempted to read a non-sequence as a "~T.stringof);
			foreach (Node newNode; value) {
				ElementType!T ele;
				deserialize(newNode, path, ele);
				result ~= ele;
			}
		}
	}
	void deserialize(T)(Node value, string path, out T result) if (is(T == struct) && !isNullable!T && !isTimeType!T) {
		static if (hasDeserializationMethod!T) {
			Parameters!(deserializationMethod!T) tmp;
			deserialize(value, path, tmp);
			result = deserializationMethod!T(tmp);
			return;
		} else {
			import std.exception : enforce;
			import std.meta : AliasSeq;
			import std.traits : arity, FieldNameTuple, ForeachType, getUDAs, hasIndirections, hasUDA, isAssociativeArray, isFloatingPoint, isIntegral, isPointer, isSomeChar, isSomeString, isStaticArray, OriginalType, Parameters, PointerTarget, TemplateArgsOf, ValueType;
			enforce!YAMLDException(value.nodeID == NodeID.mapping, "Attempted to read a non-mapping as a "~T.stringof);
			foreach (member; FieldNameTuple!T) {
				static if (__traits(getProtection, __traits(getMember, T, member)) == "public") {
					debug string newPath = path~"."~member;
					else string newPath = path;
					alias field = AliasSeq!(__traits(getMember, T, member));
					enum memberName = getMemberName!field;
					static if ((hasUDA!(field, Optional) || (!!(flags & DeSiryulize.optionalByDefault))) || hasIndirections!(typeof(field))) {
						if (memberName !in value) {
							continue;
						}
					} else {
						enforce!YAMLDException(memberName in value, "Missing non-@Optional "~memberName~" in node");
					}
					alias fromFunc = getConvertFromFunc!(T, field);
					try {
						Parameters!(fromFunc)[0] param;
						static if (hasUDA!(field, IgnoreErrors)) {
							try {
								deserialize(value[memberName], newPath, param);
								__traits(getMember, result, member) = fromFunc(param);
							} catch (YAMLDException) {} //just skip it
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
	void deserialize(T)(Node value, string path, out T result) if (is(T == SysTime) || is(T == DateTime) || is(T == Date)) {
		enforce!YAMLDException(value.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
		result = value.get!SysTime.to!T;
	}
	void deserialize(T)(Node value, string path, out T result) if (isSomeChar!T) {
		import std.array : front;
		if (value.type != NodeType.null_) {
			enforce!YAMLDException(value.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
			result = cast(T)value.get!string.front;
		}
	}
	void deserialize(T)(Node value, string path, out T result) if (isSomeString!T && !canStoreUnchanged!T && !is(T == enum)) {
		string str;
		deserialize(value, path, str);
		result = str.to!T;
	}
	void deserialize(T)(Node value, string path, out T result) if (canStoreUnchanged!T && !is(T == enum)) {
		enforce!YAMLDException(value.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
		if (value.tag == `tag:yaml.org,2002:str`) {
			result = value.get!string.to!T;
		} else {
			static if (isIntegral!T) {
				enforce!YAMLDException(value.tag == `tag:yaml.org,2002:int`, "Attempted to read a float as an integer");
				result = value.get!T;
			} else static if (isSomeString!T) {
				enforce!YAMLDException(value.tag != `tag:yaml.org,2002:bool`, "Attempted to read a non-string as a string");
				if (value.type != NodeType.null_) {
					result = value.get!T;
				}
			} else {
				result = value.get!T;
			}
		}
	}
	void deserialize(T : P*, P)(Node value, string path, out T result) {
		result = new P;
		deserialize(value, path, *result);
	}
	void deserialize(Node, string, out typeof(null)) {}
}
template serialize(Serializer : YAML, BitFlags!Siryulize flags) {
	import std.conv : text, to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.traits : arity, FieldNameTuple, getSymbolsByUDA, getUDAs, hasUDA, isAssociativeArray, isPointer, isSomeString, isStaticArray, PointerTarget, Unqual;
	private auto serialize(const typeof(null) value) {
		return Node(YAMLNull());
	}
	private auto serialize(const SysTime value) {
		return Node(value.to!SysTime, "tag:yaml.org,2002:timestamp");
	}
	private auto serialize(const TimeOfDay value) {
		return Node(value.toISOExtString);
	}
	private auto serialize(T)(const T value) if (isSomeChar!T) {
		return serialize([value]);
	}
	private auto serialize(T)(const T value) if (canStoreUnchanged!T && !is(T == enum)) {
		return Node(value.to!T);
	}
	private auto serialize(T)(const T value) if (!canStoreUnchanged!T && (isSomeString!T || (isStaticArray!T && isSomeChar!(ElementType!T)))) {
		import std.utf : toUTF8;
		return serialize(value[].toUTF8().idup);
	}
	private auto serialize(T)(const T value) if (hasUDA!(value, AsString) || is(T == enum)) {
		return Node(value.text);
	}
	private auto serialize(T)(const T value) if (isAssociativeArray!T) {
		Node[Node] output;
		foreach (k, v; value) {
			output[serialize(k)] = serialize(v);
		}
		return Node(output);
	}
	private auto serialize(T)(T values) if (isSimpleList!T && !isSomeChar!(ElementType!T)) {
		Node[] output;
		foreach (value; values) {
			output ~= serialize(value);
		}
		return Node(output);
	}
	private auto serialize(T)(auto ref const T value) if (isPointer!T) {
		return serialize(*value);
	}
	private auto serialize(T)(const T value) if (is(T == struct)) {
		static if (hasSerializationMethod!T) {
			return serialize(mixin("value."~__traits(identifier, serializationMethod!T)));
		} else static if (is(T == Date) || is(T == DateTime)) {
			return Node(value.toISOExtString, "tag:yaml.org,2002:timestamp");
		} else static if (isNullable!T) {
			if (value.isNull) {
				return serialize(null);
			} else {
				return serialize(value.get);
			}
		} else {
			static string[] empty;
			Node output = Node(empty, empty);
			foreach (member; FieldNameTuple!T) {
				static if (__traits(getProtection, __traits(getMember, T, member)) == "public") {
					static if (!!(flags & Siryulize.omitInits)) {
						static if (isNullable!(typeof(__traits(getMember, value, member)))) {
							if (__traits(getMember, value, member).isNull)
								continue;
						} else {
							if (__traits(getMember, value, member) == __traits(getMember, value, member).init) {
								continue;
							}
						}
					}
					enum memberName = getMemberName!(__traits(getMember, T, member));
					try {
						static if (isPointer!(typeof(mixin("value."~member))) && !!(flags & Siryulize.omitNulls)) {
							if (mixin("value."~member) is null) {
								continue;
							}
						}
						static if (hasConvertToFunc!(T, __traits(getMember, T, member))) {
							auto val = serialize(getConvertToFunc!(T, __traits(getMember, T, member))(mixin("value."~member)));
							output.add(memberName, val);
						} else {
							output.add(memberName, serialize(mixin("value."~member)));
						}
					} catch (Exception e) {
						e.msg = "Error serializing: "~e.msg;
						throw e;
					}
				}
			}
			return output;
		}
	}
}
private template expectedTag(T) {
	import std.datetime.systime : SysTime;
	import std.traits : isFloatingPoint, isIntegral;
	static if(isIntegral!T) {
		enum expectedTag = `tag:yaml.org,2002:int`;
	}
	static if(is(T == bool)) {
		enum expectedTag = `tag:yaml.org,2002:bool`;
	}
	static if(isFloatingPoint!T) {
		enum expectedTag = `tag:yaml.org,2002:float`;
	}
	static if(is(T == string)) {
		enum expectedTag = `tag:yaml.org,2002:str`;
	}
	static if(is(T == SysTime)) {
		enum expectedTag = `tag:yaml.org,2002:timestamp`;
	}
}
private template canStoreUnchanged(T) {
	import std.traits : isFloatingPoint, isIntegral;
	enum canStoreUnchanged = isIntegral!T || is(T == bool) || isFloatingPoint!T || is(T == string);
}