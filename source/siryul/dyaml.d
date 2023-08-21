module siryul.dyaml;
import dyaml;
import siryul.common;
import core.time : Duration;
import std.datetime.systime : SysTime;
import std.range.primitives : ElementType, isInfinite, isInputRange;
import std.traits : isSomeChar;
import std.typecons;

/++
 + YAML (YAML Ain't Markup Language) serialization format
 +/
struct YAML {
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
			throw new DeserializeException(format!"Parsing error: %s"(e.msg), convertMark(e.mark));
		}
	}
	package static string asString(Siryulize flags, T)(T data) {
		import std.array : appender;
		auto buf = appender!string;
		auto dumper = dumper();
		dumper.defaultCollectionStyle = CollectionStyle.block;
		dumper.defaultScalarStyle = ScalarStyle.plain;
		dumper.explicitStart = false;
		dumper.dump(buf, serialize!(Node)(data, BitFlags!Siryulize(flags)).node);
		return buf.data;
	}
	static private siryul.common.Mark convertMark(dyaml.Mark dyamlMark) @safe pure nothrow {
		return siryul.common.Mark(dyamlMark.name, dyamlMark.line ,dyamlMark.column);
	}
	static struct Node {
		private dyaml.Node node = dyaml.Node(YAMLNull());
		this(T)(T value) if (canStoreUnchanged!T) {
			this.node = dyaml.Node(value);
		}
		this(Node[] newNodes) @safe pure {
			dyaml.Node[] nodes;
			nodes.reserve(newNodes.length);
			foreach (newNode; newNodes) {
				nodes ~= newNode.node;
			}
			this.node = dyaml.Node(nodes);
		}
		this(Node[string] newNodes) @safe pure {
			dyaml.Node[dyaml.Node] nodes;
			foreach (newKey, newNode; newNodes) {
				nodes[dyaml.Node(newKey)] = newNode.node;
			}
			this.node = dyaml.Node(nodes);
		}
		private this(dyaml.Node node) @safe pure nothrow @nogc {
			this.node = node;
		}
		siryul.common.Mark getMark() const @safe pure nothrow {
			return convertMark(node.startMark);
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
		string type() const @safe {
			final switch (node.type) {
				case NodeType.null_:
				case NodeType.invalid:
				case NodeType.merge: return "null";
				case NodeType.boolean: return "bool";
				case NodeType.integer: return "long";
				case NodeType.decimal: return "real";
				case NodeType.timestamp: return "SysTime";
				case NodeType.string: return "string";
				case NodeType.binary: return "ubyte[]";
				case NodeType.mapping: return "Node[Node]";
				case NodeType.sequence: return "Node[]";
			}
		}
		template canStoreUnchanged(T) {
			import std.traits : isFloatingPoint, isIntegral;
			enum canStoreUnchanged = !is(T == enum) && (isIntegral!T || is(T : bool) || isFloatingPoint!T || is(T == string));
		}
		enum hasStringIndexing = false;
	}
}

private template expectedTag(T) {
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

@safe unittest {
	import siryul.testing;
	runTests!YAML();
}
