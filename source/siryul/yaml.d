module siryul.yaml;
import yaml;
import siryul;
import std.range.primitives : isInfinite;
import std.stream : MemoryStream, SeekPos;
import std.typecons;

struct YAML {
	static T parseString(T)(string data) @safe {
		auto loader = Loader.fromString(data.dup).load();
		return populate!T(loader);
	}
	static string asString(T)(T data) @safe {
		MemoryStream stream;
		() @trusted {
			stream = new MemoryStream();
		}();
		auto dumper = Dumper(stream);
		auto representer = new Representer;
		representer.defaultCollectionStyle = CollectionStyle.Block;
		representer.defaultScalarStyle = ScalarStyle.Plain;
		dumper.representer = representer;
		dumper.explicitStart = false;
		dumper.dump(data.toNode());
		return stream.toStr;
	}
}
@property string toStr(MemoryStream stream) @trusted {
	string output;
	stream.seek(0, SeekPos.Set);
	foreach (char[] line; stream)
		output ~= line.dup~"\n";
	return output;
}
class YAMLException : DeserializeException {
	this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
private T populate(T)(Node node) @safe if (!isInfinite!T) {
	import std.traits, std.exception, std.datetime, std.range;
	import std.range.primitives : ElementType;
	if (node.isNull)
		return T.init;
	try {
		static if (is(T == enum)) {
			import std.conv : to;
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			//if (node.tag == `tag:yaml.org,2002:str`)
				return node.get!string.to!T;
			//else
			//	return node.populate!(OriginalType!T).to!T;
		} else static if (isNullable!T) {
			T output;
			if (node.isNull())
				output.nullify();
			else
				output = node.get!(TemplateArgsOf!T[0]);
			return output;
		} else static if (isIntegral!T || isSomeString!T || isFloatingPoint!T) {
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			return node.get!T;
		} else static if (is(T == SysTime) || is(T == DateTime) || is(T == Date)) {
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			return cast(T)node.get!SysTime;
		} else static if (is(T == TimeOfDay)) {
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			return TimeOfDay.fromISOExtString(node.get!string);
		} else static if (is(T == struct)) {
			enforce(node.isMapping(), new YAMLException("Attempted to read a non-mapping as a "~T.stringof));
			T output;
			foreach (member; FieldNameTuple!T) {
				static if (hasUDA!(__traits(getMember, T, member), SiryulizeAs)) {
					enum memberName = getUDAValue!(__traits(getMember, T, member), SiryulizeAs).name;
					static if (hasUDA!(__traits(getMember, T, member), Optional) || hasIndirections!(typeof(__traits(getMember, T, member)))) {
						if (!node.containsKey(memberName))
							continue;
					} else
						enforce(node.containsKey(memberName), new YAMLException("Missing non-@Optional "~memberName~" in node"));
					__traits(getMember, output, member) = populate!(typeof(__traits(getMember, T, member)))(node[memberName]);
				} else {
					static if (hasUDA!(__traits(getMember, T, member), Optional) || hasIndirections!(typeof(__traits(getMember, T, member)))) {
						if (!node.containsKey(member))
							continue;
					} else
						enforce(node.containsKey(member), new YAMLException("Missing non-@Optional "~member~" in node"));
					__traits(getMember, output, member) = populate!(typeof(__traits(getMember, T, member)))(node[member]);
				}
			}
			return output;
		} else static if(isOutputRange!(T, ElementType!T)) {
			enforce(node.isSequence(), new YAMLException("Attempted to read a non-sequence as a "~T.stringof));
			T output;
			foreach (Node newNode; node)
				output ~= populate!(ElementType!T)(newNode);
			return output;
		} else static if(isStaticArray!T) {
			enforce(node.isSequence(), new YAMLException("Attempted to read a non-sequence as a "~T.stringof));
			T output;
			size_t i;
			foreach (Node newNode; node)
				output[i++] = populate!(ElementType!T)(newNode);
			return output;
		} else static if(isAssociativeArray!T) {
			enforce(node.isMapping(), new YAMLException("Attempted to read a non-mapping as a "~T.stringof));
			T output;
			foreach (Node key, Node value; node)
				output[populate!(KeyType!T)(key)] = populate!(ValueType!T)(value);
			return output;
		} else static if (is(T == bool)) {
			return node.get!T;
		} else
			static assert(false, "Cannot read type "~T.stringof~" from YAML"); //unreachable, hopefully.
	} catch (NodeException e) {
		throw new YAMLException(e.msg);
	}
}
version(unittest) {
	enum testEnum { test, something, wont, ya }
	struct testStruct {
		uint a;
		string b;
	}
}
unittest {
	assert(populate!string(Node("Hello.")) == "Hello.");
	assert(populate!byte(Node(0)) == 0);
	assert(populate!byte(Node(-128)) == -128);
	assert(populate!(string[])(Node(["Hello", "World"])) == ["Hello", "World"]);
	assert(populate!(string[2])(Node(["Hello", "World"])) == ["Hello", "World"]);
	assert(populate!testEnum(Node("wont")) == testEnum.wont);
	{
		auto node = Node(["a": 1]);
		node.add("b", "testString");
		assert(populate!testStruct(node) == testStruct(1, "testString"));
	}
}
private @property Node toNode(T)(T type) @safe if (!isInfinite!T) {
	import std.traits, std.datetime, std.range;
	import std.conv : text;
	static if (hasUDA!(type, AsString) || is(T == enum)) {
		return Node(type.text);
	} else static if (isNullable!T) {
		if (type.isNull)
			return Node(YAMLNull());
		else
			return type.get().toNode;
	} else static if (is(T == SysTime)) {
		return Node(type, "tag:yaml.org,2002:timestamp");
	} else static if (is(T == DateTime) || is(T == Date)) {
		return Node(type.toISOExtString(), "tag:yaml.org,2002:timestamp");
	} else static if (is(T == TimeOfDay)) {
		return Node(type.toISOExtString());
	} else static if (isIntegral!T || isSomeString!T || is(T == bool) || isFloatingPoint!T) {
		return Node(type);
	} else static if(isAssociativeArray!T) {
		Node[Node] output;
		foreach (key, value; type)
			output[key.toNode] = value.toNode;
		return Node(output);
	} else static if(isInputRange!T || isArray!T) {
		Node[] output;
		foreach (value; type)
			output ~= value.toNode;
		return Node(output);
	} else static if (is(T == struct)) {
		static string[] empty;
		Node output = Node(empty, empty);
		foreach (member; FieldNameTuple!T) {
			static if (hasUDA!(__traits(getMember, T, member), SiryulizeAs)) {
				enum memberName = getUDAValue!(__traits(getMember, T, member), SiryulizeAs).name;
				output.add(memberName, __traits(getMember, type, member).toNode);
			} else
				output.add(member, __traits(getMember, type, member).toNode);
		}
		return output;
	} else
		static assert(false, "Cannot write type "~T.stringof~" to YAML"); //unreachable, hopefully
}