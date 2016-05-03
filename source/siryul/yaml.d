module siryul.yaml;
private import siryul;
version(Have_dyaml) {
import yaml;
private import std.range.primitives : isInfinite, isInputRange, ElementType;
private import std.stream : MemoryStream, SeekPos;
private import std.typecons;
private import std.traits : isSomeChar;

/++
 + YAML (YAML Ain't Markup Language) serialization format
 +/
struct YAML {
	private import std.meta : AliasSeq;
	package alias types = AliasSeq!(".yml", ".yaml");
	enum emptyObject = "---\n...";
	package static T parseInput(T, DeSiryulize flags, U)(U data) @trusted if (isInputRange!U && isSomeChar!(ElementType!U)) {
		import std.utf : byChar;
		import std.conv : to;
		auto loader = Loader.fromString(data.byChar.to!(char[])).load();
		return loader.fromYAML!(T, BitFlags!DeSiryulize(flags));
	}
	package static string asString(Siryulize flags, T)(T data) @safe {
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
		dumper.dump(data.toYAML!(BitFlags!Siryulize(flags))());
		return stream.toStr;
	}
}
private @property string toStr(MemoryStream stream) @trusted {
	string output;
	stream.seek(0, SeekPos.Set);
	foreach (char[] line; stream)
		output ~= line.dup~"\n";
	return output;
}
/++
 + Thrown on YAML deserialization errors
 +/
class YAMLDException : DeserializeException {
	package this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
/++
 + Thrown on YAML serialization errors
 +/
class YAMLSException : SerializeException {
	package this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
private T fromYAML(T, BitFlags!DeSiryulize flags)(Node node) @trusted if (!isInfinite!T) {
	import std.traits : isSomeString, isStaticArray, isAssociativeArray, isArray, isIntegral, isFloatingPoint, FieldNameTuple, KeyType, hasUDA, getUDAs, hasIndirections, ValueType, OriginalType, TemplateArgsOf, arity, Parameters;
	import std.exception : enforce;
	import std.datetime : SysTime, Date, DateTime, TimeOfDay;
	import std.range : isOutputRange;
	import std.conv : to;
	import std.meta : AliasSeq;
	if (node.isNull)
		return T.init;
	try {
		static if (is(T == enum)) {
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			if (node.tag == `tag:yaml.org,2002:str`)
				return node.get!string.to!T;
			else
				return node.fromYAML!(OriginalType!T, flags).to!T;
		} else static if (isNullable!T) {
			T output;
			auto val = node.fromYAML!(TemplateArgsOf!T[0], flags);
			static if (isNullableValue!T) {
				output = val;
			} else {
				() @trusted {
					output.bind(moveToHeap(val));
				}();
			}
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
				string memberName = member;
				static if (hasUDA!(__traits(getMember, T, member), SiryulizeAs))
					memberName = getUDAValue!(__traits(getMember, T, member), SiryulizeAs).name;
				static if (hasUDA!(__traits(getMember, T, member), Optional) || hasIndirections!(typeof(__traits(getMember, T, member)))) {
					if (!node.containsKey(memberName))
						continue;
				} else
					enforce(node.containsKey(memberName), new YAMLException("Missing non-@Optional "~memberName~" in node"));
				static if (hasUDA!(__traits(getMember, T, member), CustomParser)) {
					alias fromFunc = AliasSeq!(__traits(getMember, output, getUDAValue!(__traits(getMember, output, member), CustomParser).fromFunc))[0];
					assert(arity!fromFunc == 1, "Arity of conversion function must be exactly 1");
					__traits(getMember, output, member) = fromFunc(node[memberName].fromYAML!(Parameters!(fromFunc)[0], flags));
				} else
					__traits(getMember, output, member) = node[memberName].fromYAML!(typeof(__traits(getMember, T, member)), flags);
			}
			return output;
		} else static if(isOutputRange!(T, ElementType!T)) {
			enforce(node.isSequence(), new YAMLException("Attempted to read a non-sequence as a "~T.stringof));
			T output;
			foreach (Node newNode; node)
				output ~= fromYAML!(ElementType!T, flags)(newNode);
			return output;
		} else static if(isStaticArray!T) {
			enforce(node.isSequence(), new YAMLException("Attempted to read a non-sequence as a "~T.stringof));
			T output;
			size_t i;
			foreach (Node newNode; node)
				output[i++] = fromYAML!(ElementType!T, flags)(newNode);
			return output;
		} else static if(isAssociativeArray!T) {
			enforce(node.isMapping(), new YAMLException("Attempted to read a non-mapping as a "~T.stringof));
			T output;
			foreach (Node key, Node value; node)
				output[fromYAML!(KeyType!T, flags)(key)] = fromYAML!(ValueType!T, flags)(value);
			return output;
		} else static if (is(T == bool)) {
			return node.get!T;
		} else
			static assert(false, "Cannot read type "~T.stringof~" from YAML"); //unreachable, hopefully.
	} catch (NodeException e) {
		throw new YAMLException(e.msg);
	}
}
private @property Node toYAML(BitFlags!Siryulize flags, T)(T type) @trusted if (!isInfinite!T) {
	import std.traits : Unqual, hasUDA, getUDAs, isSomeString, isAssociativeArray, FieldNameTuple, arity;
	import std.datetime : SysTime, DateTime, Date, TimeOfDay;
	import std.conv : text, to;
	import std.meta : AliasSeq;
	alias Undecorated = Unqual!T;
	static if (hasUDA!(type, AsString) || is(Undecorated == enum)) {
		return Node(type.text);
	} else static if (isNullable!Undecorated) {
		if (type.isNull && !(flags & Siryulize.omitNulls))
			return Node(YAMLNull());
		else
			return type.get().toYAML!flags;
	} else static if (is(Undecorated == SysTime)) {
		return Node(type.to!Undecorated, "tag:yaml.org,2002:timestamp");
	} else static if (is(Undecorated == DateTime) || is(Undecorated == Date)) {
		return Node(type.toISOExtString(), "tag:yaml.org,2002:timestamp");
	} else static if (is(Undecorated == TimeOfDay)) {
		return Node(type.toISOExtString());
	} else static if (isSomeChar!Undecorated) {
		return [type].toYAML!flags;
	} else static if (canStoreUnchanged!Undecorated) {
		return Node(type.to!Undecorated);
	} else static if (isSomeString!Undecorated) {
		import std.utf : toUTF8;
		return type.toUTF8().idup.toYAML!flags;
	} else static if(isAssociativeArray!Undecorated) {
		Node[Node] output;
		foreach (key, value; type)
			output[key.toYAML!flags] = value.toYAML!flags;
		return Node(output);
	} else static if(isSimpleList!Undecorated) {
		Node[] output;
		foreach (value; type)
			output ~= value.toYAML!flags;
		return Node(output);
	} else static if (is(Undecorated == struct)) {
		static string[] empty;
		Node output = Node(empty, empty);
		foreach (member; FieldNameTuple!T) {
			static if (!!(flags & Siryulize.omitInits)) {
				static if (isNullable!(__traits(getMember, type, member))) {
					if (__traits(getMember, type, member).isNull)
						continue;
				} else if (__traits(getMember, type, member) == __traits(getMember, type, member).init)
					continue;
			}
			string memberName = member;
			static if (hasUDA!(__traits(getMember, T, member), SiryulizeAs))
				memberName = getUDAValue!(__traits(getMember, T, member), SiryulizeAs).name;
			static if (hasUDA!(__traits(getMember, T, member), CustomParser)) {
				alias toFunc = AliasSeq!(__traits(getMember, type, getUDAValue!(__traits(getMember, type, member), CustomParser).toFunc))[0];
				assert(arity!toFunc == 1, "Arity of conversion function must be exactly 1");
				output.add(memberName, toFunc(__traits(getMember, type, member)).toYAML!flags);
			} else
				output.add(memberName, __traits(getMember, type, member).toYAML!flags);
		}
		return output;
	} else
		static assert(false, "Cannot write type "~T.stringof~" to YAML"); //unreachable, hopefully
}
private template canStoreUnchanged(T) {
	import std.traits : isIntegral, isFloatingPoint;
	enum canStoreUnchanged = isIntegral!T || is(T == bool) || isFloatingPoint!T || is(T == string);
}
} else {
	struct YAML {
		private import std.meta : AliasSeq;
		package alias types = AliasSeq!();
		package static T parseInput(T, DeSiryulize flags, U)(U data) @trusted if (isInputRange!U && isSomeChar!(ElementType!U)) {
			assert(0, "YAML Unavailable");
		}
		package static string asString(Siryulize flags, T)(T data) @safe {
			assert(0, "YAML Unavailable");
		}
	}
}