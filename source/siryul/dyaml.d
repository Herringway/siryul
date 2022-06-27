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
	alias extensions = AliasSeq!(".yml", ".yaml");
	package static T parseInput(T, DeSiryulize flags, U)(U data, string filename) if (isInputRange!U && isSomeChar!(ElementType!U)) {
		import std.conv : to;
		import std.utf : byChar;
		auto str = data.byChar.to!(char[]);
		auto loader = Loader.fromString(str);
		loader.name = filename;
		try {
			T result;
			deserialize!(YAML, BitFlags!DeSiryulize(flags))(loader.load(), T.stringof, result);
			return result;
		} catch (NodeException e) {
			debug(norethrow) throw e;
			else throw new YAMLDException(Mark(filename, 0, 0), e.msg);
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
class YAMLUnexpectedNodeIDException : YAMLDException {
	this(const Node node, NodeID id, string file = __FILE__, size_t line = __LINE__) @safe nothrow {
		import std.format : format;
		try {
			super(node.startMark, format!"Expected a %s, got a %s"(id, node.nodeID), file, line);
		} catch (Exception) { assert(0); }
	}
}
/++
 + Thrown on YAML deserialization errors
 +/
class YAMLDException : DeserializeException {
	this(const Mark mark, string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		ErrorMark siryulMark;
		siryulMark.filename = mark.name;
		siryulMark.line = mark.line;
		siryulMark.column = mark.column;
		super(siryulMark, msg, file, line);
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
private void expect(Node node, NodeID expected, string file = __FILE__, ulong line = __LINE__) @safe {
	import std.algorithm : among;
	import std.exception : enforce;
	enforce(node.nodeID == expected, new YAMLUnexpectedNodeIDException(node, expected, file, line));
}
template deserialize(Serializer : YAML, BitFlags!DeSiryulize flags) {
	import std.conv : to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.exception : enforce;
	import std.range : enumerate, isOutputRange, put;
	import std.traits : arity, FieldNameTuple, ForeachType, getUDAs, hasIndirections, hasUDA, isAggregateType, isArray, isAssociativeArray, isFloatingPoint, isIntegral, isPointer, isSomeString, isStaticArray, KeyType, OriginalType, Parameters, PointerTarget, TemplateArgsOf, ValueType;
	import std.utf : byCodeUnit;
	void deserialize(T)(Node value, string path, out T result) if (is(T == enum)) {
		import std.conv : to;
		import std.traits : OriginalType;
		expect(value, NodeID.scalar);
		if (value.tag == `tag:yaml.org,2002:str`) {
			result = value.get!string.to!T;
		} else {
			OriginalType!T tmp;
			deserialize(value, path, tmp);
			result = tmp.to!T;
		}
	}
	void deserialize(Node value, string path, out TimeOfDay result) {
		expect(value, NodeID.scalar);
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
		enforce(value.tag == `tag:yaml.org,2002:bool`, new YAMLDException(value.startMark, "Expecting a boolean value"));
		result = value.get!bool;
	}
	void deserialize(V, K)(Node value, string path, out V[K] result) {
		expect(value, NodeID.mapping);
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
			expect(value, NodeID.scalar);
			ForeachType!(T[N])[] str;
			deserialize(value, path, str);
			foreach (i, chr; str.byCodeUnit.enumerate(0)) {
				enforce(i < N, new YAMLDException(value.startMark, "Static array too small to contain all elements"));
				result[i] = chr;
			}
			return;
		} else {
			expect(value, NodeID.sequence);
			size_t i;
			foreach (Node newNode; value) {
				enforce(i < N, new YAMLDException(value.startMark, "Static array too small to contain all elements"));
				deserialize(newNode, path, result[i++]);
			}
			return;
		}
	}
	void deserialize(T)(Node value, string path, out T result) if (isOutputRange!(T, ElementType!T) && !isSomeString!T && !isNullable!T) {
		if (value.type != NodeType.null_) {
			expect(value, NodeID.sequence);
			foreach (Node newNode; value) {
				ElementType!T ele;
				deserialize(newNode, path, ele);
				result ~= ele;
			}
		}
	}
	void deserialize(T)(Node value, string path, out T result) if (is(T == struct) && !isNullable!T && !isTimeType!T && !hasDeserializationMethod!T) {
		import std.exception : enforce;
		import std.meta : AliasSeq;
		import std.traits : arity, FieldNameTuple, ForeachType, getUDAs, hasIndirections, hasUDA, isAssociativeArray, isFloatingPoint, isIntegral, isPointer, isSomeChar, isSomeString, isStaticArray, OriginalType, Parameters, PointerTarget, TemplateArgsOf, ValueType;
		expect(value, NodeID.mapping);
		foreach (member; FieldNameTuple!T) {
			static if (__traits(getProtection, __traits(getMember, T, member)) == "public") {
				debug string newPath = path~"."~member;
				else string newPath = path;
				alias field = AliasSeq!(__traits(getMember, T, member));
				enum memberName = getMemberName!field;
				static if ((hasUDA!(field, Optional) || (!!(flags & DeSiryulize.optionalByDefault)) && !hasUDA!(field, Required)) || hasIndirections!(typeof(field))) {
					if (memberName !in value) {
						continue;
					}
				} else {
					enforce(memberName in value, new YAMLDException(value.startMark, "Missing non-@Optional "~memberName~" in node"));
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
	void deserialize(T)(Node value, string path, out T result) if (is(T == SysTime) || is(T == DateTime) || is(T == Date)) {
		expect(value, NodeID.scalar);
		result = value.get!SysTime.to!T;
	}
	void deserialize(T)(Node value, string path, out T result) if (isSomeChar!T) {
		import std.array : front;
		if (value.type != NodeType.null_) {
			expect(value, NodeID.scalar);
			result = cast(T)value.get!string.front;
		}
	}
	void deserialize(T)(Node value, string path, out T result) if (isSomeString!T && !canStoreUnchanged!T) {
		string str;
		deserialize(value, path, str);
		result = str.to!T;
	}
	void deserialize(T)(Node value, string path, out T result) if (canStoreUnchanged!T) {
		expect(value, NodeID.scalar);
		if (value.tag == `tag:yaml.org,2002:str`) {
			result = value.get!string.to!T;
		} else {
			static if (isIntegral!T) {
				enforce(value.tag == `tag:yaml.org,2002:int`, new YAMLDException(value.startMark, "Attempted to read a float as an integer"));
				result = value.get!T;
			} else static if (isSomeString!T) {
				enforce(value.tag != `tag:yaml.org,2002:bool`, new YAMLDException(value.startMark, "Attempted to read a non-string as a string"));
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
	void deserialize(T)(Node value, string path, out T result) if (isAggregateType!T && hasDeserializationMethod!T) {
		Parameters!(deserializationMethod!T) tmp;
		deserialize(value, path, tmp);
		result = deserializationMethod!T(tmp);
	}
}
template serialize(Serializer : YAML, BitFlags!Siryulize flags) {
	import std.conv : text, to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.traits : arity, FieldNameTuple, getSymbolsByUDA, getUDAs, hasUDA, isAggregateType, isAssociativeArray, isPointer, isSomeString, isStaticArray, PointerTarget, Unqual;
	private Node serialize(const typeof(null) value) {
		return Node(YAMLNull());
	}
	private Node serialize(const SysTime value) {
		return Node(value.to!SysTime, "tag:yaml.org,2002:timestamp");
	}
	private Node serialize(const TimeOfDay value) {
		return Node(value.toISOExtString);
	}
	private Node serialize(T)(const T value) if (isSomeChar!T) {
		return serialize([value]);
	}
	private Node serialize(T)(const T value) if (canStoreUnchanged!T) {
		return Node(value.to!T);
	}
	private Node serialize(T)(const T value) if (!canStoreUnchanged!T && (isSomeString!T || (isStaticArray!T && isSomeChar!(ElementType!T)))) {
		import std.utf : toUTF8;
		return serialize(value[].toUTF8().idup);
	}
	private Node serialize(T)(const T value) if (hasUDA!(value, AsString) || is(T == enum)) {
		return Node(value.text);
	}
	private Node serialize(T)(const T value) if (isAssociativeArray!T) {
		Node[Node] output;
		foreach (k, v; value) {
			output[serialize(k)] = serialize(v);
		}
		return Node(output);
	}
	private Node serialize(T)(T values) if (isSimpleList!T && !isSomeChar!(ElementType!T) && !isNullable!T) {
		Node[] output;
		foreach (value; values) {
			output ~= serialize(value);
		}
		return Node(output);
	}
	private Node serialize(T)(auto ref const T value) if (isPointer!T) {
		return serialize(*value);
	}
	private Node serialize(T)(const T value) if (is(T == struct) && !hasSerializationMethod!T) {
		static if (is(T == Date) || is(T == DateTime)) {
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
	private Node serialize(T)(auto ref T value) if (isAggregateType!T && hasSerializationMethod!T) {
		return serialize(mixin("value."~__traits(identifier, serializationMethod!T)));
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
	enum canStoreUnchanged = !is(T == enum) && (isIntegral!T || is(T == bool) || isFloatingPoint!T || is(T == string));
}