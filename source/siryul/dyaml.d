module siryul.dyaml;
import dyaml;
import siryul.common;
import core.time : Duration;
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
		import std.format : format;
		import std.utf : byChar;
		auto str = data.byChar.to!(char[]);
		auto loader = Loader.fromString(str);
		loader.name = filename;
		try {
			T result;
			deserialize(Node(loader.load()), result, BitFlags!DeSiryulize(flags));
			return result;
		} catch (MarkedYAMLException e) {
			throw new DeserializeException(convertMark(e.mark), format!"Parsing error: %s"(e.msg));
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
	static private siryul.common.Mark convertMark(dyaml.Mark dyamlMark) @safe pure nothrow @nogc {
		siryul.common.Mark mark;
		with (mark) {
			filename = dyamlMark.name;
			line = dyamlMark.line;
			column = dyamlMark.column;
		}
		return mark;
	}
	static struct Node {
		private dyaml.Node node;
		Nullable!(siryul.common.Mark) getMark() const @safe pure nothrow {
			return typeof(return)(convertMark(node.startMark));
		}
		bool hasTypeConvertible(T)() const {
			static if (is(T == typeof(null))) {
				return node.type == NodeType.null_;
			} else static if (is(T : Duration)) {
				return false;
			} else {
				return node.tag == expectedTag!T;
			}
		}
		T getType(T)() {
			import std.datetime : SysTime;
			static if (is(T == typeof(null))) {
				return node.type == NodeType.null_;
			} else static if (is(T: const(char)[])) {
				return node.get!string;
			} else static if (is(T : bool)) {
				return node.get!bool;
			} else static if (is(T == ulong)) {
				return node.get!ulong;
			} else static if (is(T == long)) {
				return node.get!long;
			} else static if (is(T : real)) {
				return node.get!real;
			} else static if (is(T : SysTime)) {
				return node.get!SysTime;
			} else {
				assert(0, "Cannot represent type");
			}
		}
		bool hasClass(Classification c) const @safe pure {
			final switch (c) {
				case Classification.scalar:
					return node.nodeID == NodeID.scalar;
				case Classification.sequence:
					return node.nodeID == NodeID.sequence;
				case Classification.mapping:
					return node.nodeID == NodeID.mapping;
			}
		}
		Node opIndex(size_t index) @safe {
			return Node(node[index]);
		}
		Node opIndex(string index) @safe {
			return Node(node[index]);
		}
		size_t length() const @safe {
			return node.length;
		}
		bool opBinaryRight(string op : "in")(string key) {
			return !!(key in node);
		}
		int opApply(scope int delegate(string k, Node v) @safe dg) @safe {
			foreach (dyaml.Node k, dyaml.Node v; node) {
				const result = dg(k.get!string, Node(v));
				if (result != 0) {
					return result;
				}
			}
			return 0;
		}
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
template serialize(Serializer : YAML, BitFlags!Siryulize flags) {
	import std.conv : text, to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.traits : arity, FieldNameTuple, isAggregateType, isAssociativeArray, isPointer, isSomeString, isStaticArray, PointerTarget, Unqual;
	private Node serialize(const typeof(null) value) {
		return Node(YAMLNull());
	}
	private Node serialize(ref const SysTime value) {
		return Node(value.to!SysTime, "tag:yaml.org,2002:timestamp");
	}
	private Node serialize(ref const TimeOfDay value) {
		return Node(value.toISOExtString);
	}
	private Node serialize(ref const Duration value) {
		return Node(value.asISO8601String.text);
	}
	private Node serialize(T)(auto ref const T value) if (isSomeChar!T) {
		return serialize([value]);
	}
	private Node serialize(T)(auto ref const T value) if (canStoreUnchanged!T) {
		return Node(value.to!T);
	}
	private Node serialize(T)(auto ref const T value) if (!canStoreUnchanged!T && (isSomeString!T || (isStaticArray!T && isSomeChar!(ElementType!T)))) {
		import std.utf : toUTF8;
		return serialize(value[].toUTF8().idup);
	}
	private Node serialize(T)(auto ref const T value) if (shouldStringify!value || is(T == enum)) {
		return Node(value.text);
	}
	private Node serialize(T)(auto ref const T value) if (isAssociativeArray!T) {
		Node[Node] output;
		foreach (k, v; value) {
			output[serialize(k)] = serialize(v);
		}
		return Node(output);
	}
	private Node serialize(T)(auto ref T values) if (isSimpleList!T && !isSomeChar!(ElementType!T) && !isNullable!T) {
		Node[] output;
		foreach (value; values) {
			output ~= serialize(value);
		}
		return Node(output);
	}
	private Node serialize(T)(auto ref const T value) if (isPointer!T) {
		return serialize(*value);
	}
	private Node serialize(T)(auto ref const T value) if (is(T == struct) && !hasSerializationMethod!T && !hasSerializationTemplate!T) {
		static if (is(T == Date) || is(T == DateTime)) {
			return Node(value.toISOExtString, "tag:yaml.org,2002:timestamp");
		} else static if (isSumType!T) {
			import std.sumtype : match;
			return value.match!(v => serialize(v));
		} else static if (isNullable!T) {
			if (value.isNull) {
				return serialize(null);
			} else {
				return serialize(value.get);
			}
		} else {
			import std.meta : AliasSeq;
			static string[] empty;
			Node output = Node(empty, empty);
			foreach (member; FieldNameTuple!T) {
				alias field = AliasSeq!(__traits(getMember, T, member));
				static if (!mustSkip!field && (__traits(getProtection, field) == "public")) {
					if (__traits(getMember, value, member).isSkippableValue!flags) {
						continue;
					}
					enum memberName = getMemberName!field;
					try {
						static if (hasConvertToFunc!(T, field)) {
							auto val = serialize(getConvertToFunc!(T, field)(__traits(getMember, value, member)));
							output.add(memberName, val);
						} else {
							output.add(memberName, serialize(__traits(getMember, value, member)));
						}
					} catch (Exception e) {
						throw new YAMLSException("Error serializing: "~e.msg, e.file, e.line);
					}
				}
			}
			return output;
		}
	}
	private Node serialize(T)(auto ref T value) if (isAggregateType!T && hasSerializationMethod!T) {
		return serialize(__traits(getMember, value, __traits(identifier, serializationMethod!T)));
	}
	private Node serialize(T)(auto ref T value) if (isAggregateType!T && hasSerializationTemplate!T) {
		const v = __traits(getMember, value, __traits(identifier, serializationTemplate!T));
		return serialize(v);
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
	static if(is(T : const(char)[])) {
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
