module siryul.yaml;
import yaml;
import siryul;
import std.range.primitives : isInfinite;
import std.stream : MemoryStream, SeekPos;
import std.typecons;

/++
 + YAML (YAML Ain't Markup Language) serialization format
 +/
struct YAML {
	static T parseString(T)(string data) @safe {
		auto loader = Loader.fromString(data.dup).load();
		return loader.fromYAML!T;
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
		dumper.dump(data.toYAML());
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
private T fromYAML(T)(Node node) @safe if (!isInfinite!T) {
	import std.traits, std.exception, std.datetime, std.range, std.conv;
	import std.range.primitives : ElementType;
	import std.conv : to;
	if (node.isNull)
		return T.init;
	try {
		static if (is(T == enum)) {
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			if (node.tag == `tag:yaml.org,2002:str`)
				return node.get!string.to!T;
			else
				return node.fromYAML!(OriginalType!T).to!T;
		} else static if (isNullable!T) {
			T output = node.get!(TemplateArgsOf!T[0]);
			return output;
		} else static if (isIntegral!T || isSomeString!T || isFloatingPoint!T) {
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			if (node.tag == `tag:yaml.org,2002:str`)
				return node.get!string.to!T;
			return node.get!T;
		} else static if (isSomeChar!T) {
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			return node.get!(T[])[0];
		} else static if (is(T == SysTime) || is(T == DateTime) || is(T == Date)) {
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			return node.get!SysTime.to!T;
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
					__traits(getMember, output, member) = node[memberName].fromYAML!(typeof(__traits(getMember, T, member)));
				} else {
					static if (hasUDA!(__traits(getMember, T, member), Optional) || hasIndirections!(typeof(__traits(getMember, T, member)))) {
						if (!node.containsKey(member))
							continue;
					} else
						enforce(node.containsKey(member), new YAMLException("Missing non-@Optional "~member~" in node"));
					__traits(getMember, output, member) = node[member].fromYAML!(typeof(__traits(getMember, T, member)));
				}
			}
			return output;
		} else static if(isOutputRange!(T, ElementType!T)) {
			enforce(node.isSequence(), new YAMLException("Attempted to read a non-sequence as a "~T.stringof));
			T output;
			foreach (Node newNode; node)
				output ~= fromYAML!(ElementType!T)(newNode);
			return output;
		} else static if(isStaticArray!T) {
			enforce(node.isSequence(), new YAMLException("Attempted to read a non-sequence as a "~T.stringof));
			T output;
			size_t i;
			foreach (Node newNode; node)
				output[i++] = fromYAML!(ElementType!T)(newNode);
			return output;
		} else static if(isAssociativeArray!T) {
			enforce(node.isMapping(), new YAMLException("Attempted to read a non-mapping as a "~T.stringof));
			T output;
			foreach (Node key, Node value; node)
				output[fromYAML!(KeyType!T)(key)] = fromYAML!(ValueType!T)(value);
			return output;
		} else static if (is(T == bool)) {
			return node.get!T;
		} else
			static assert(false, "Cannot read type "~T.stringof~" from YAML"); //unreachable, hopefully.
	} catch (NodeException e) {
		throw new YAMLException(e.msg);
	}
}
private @property Node toYAML(T)(T type) @trusted if (!isInfinite!T) {
	import std.traits, std.datetime, std.range;
	import std.conv : text;
	static if (hasUDA!(type, AsString) || is(T == enum)) {
		return Node(type.text);
	} else static if (isNullable!T) {
		if (type.isNull)
			return Node(YAMLNull());
		else
			return type.get().toYAML;
	} else static if (is(T == SysTime)) {
		return Node(type, "tag:yaml.org,2002:timestamp");
	} else static if (is(T == DateTime) || is(T == Date)) {
		return Node(type.toISOExtString(), "tag:yaml.org,2002:timestamp");
	} else static if (is(T == TimeOfDay)) {
		return Node(type.toISOExtString());
	} else static if (isSomeChar!T) {
		return [type].toYAML;
	} else static if (isIntegral!T || is(T == bool) || isFloatingPoint!T || is(T == string)) {
		return Node(type);
	} else static if (isSomeString!T) {
		import std.utf;
		return type.toUTF8().idup.toYAML;
	} else static if(isAssociativeArray!T) {
		Node[Node] output;
		foreach (key, value; type)
			output[key.toYAML] = value.toYAML;
		return Node(output);
	} else static if(isInputRange!T || (isArray!T && !isSomeString!T)) {
		Node[] output;
		foreach (value; type)
			output ~= value.toYAML;
		return Node(output);
	} else static if (is(T == struct)) {
		static string[] empty;
		Node output = Node(empty, empty);
		foreach (member; FieldNameTuple!T) {
			static if (hasUDA!(__traits(getMember, T, member), SiryulizeAs)) {
				enum memberName = getUDAValue!(__traits(getMember, T, member), SiryulizeAs).name;
				output.add(memberName, __traits(getMember, type, member).toYAML);
			} else
				output.add(member, __traits(getMember, type, member).toYAML);
		}
		return output;
	} else
		static assert(false, "Cannot write type "~T.stringof~" to YAML"); //unreachable, hopefully
}