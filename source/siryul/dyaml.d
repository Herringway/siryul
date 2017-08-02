module siryul.dyaml;
import dyaml;
import dyaml.stream;
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
	enum emptyObject = "---\n...";
	package static T parseInput(T, DeSiryulize flags, U)(U data) if (isInputRange!U && isSomeChar!(ElementType!U)) {
		import std.conv : to;
		import std.utf : byChar;
		auto loader = Loader.fromString(data.byChar.to!(char[])).load();
		return loader.fromYAML!(T, BitFlags!DeSiryulize(flags));
	}
	package static string asString(Siryulize flags, T)(T data) {
		debug enum path = T.stringof;
		else enum path = "";
		auto stream = new YMemoryStream();
		auto dumper = Dumper(stream);
		auto representer = new Representer;
		representer.defaultCollectionStyle = CollectionStyle.Block;
		representer.defaultScalarStyle = ScalarStyle.Plain;
		dumper.representer = representer;
		dumper.explicitStart = false;
		dumper.dump(data.toYAML!(BitFlags!Siryulize(flags), path)());
		return stream.toStr;
	}
}
private @property string toStr(YMemoryStream stream) @trusted {
	import std.string : assumeUTF;
	return assumeUTF(stream.data);
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
private T fromYAML(T, BitFlags!DeSiryulize flags)(Node node) @safe if (!isInfinite!T) {
	import std.conv : to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.exception : enforce;
	import std.meta : AliasSeq;
	import std.range : enumerate, isOutputRange;
	import std.traits : arity, FieldNameTuple, ForeachType, getUDAs, hasIndirections, hasUDA, isArray, isAssociativeArray, isFloatingPoint, isIntegral, isSomeString, isStaticArray, KeyType, OriginalType, Parameters, TemplateArgsOf, ValueType;
	import std.utf : byCodeUnit;
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
			return node.isNull ? T.init : T(node.fromYAML!(TemplateArgsOf!T[0], flags));
		} else static if (isIntegral!T || isSomeString!T || isFloatingPoint!T) {
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			if (node.tag == `tag:yaml.org,2002:str`)
				return node.get!string.to!T;
			static if (isIntegral!T)
				enforce(node.tag == `tag:yaml.org,2002:int`, new YAMLException("Attempted to read a float as an integer"));
			static if (isSomeString!T)
				enforce(node.tag != `tag:yaml.org,2002:bool`, new YAMLException("Attempted to read a non-string as a string"));
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
				enum memberName = getMemberName!(__traits(getMember, T, member));
				static if (hasUDA!(__traits(getMember, T, member), Optional) || hasIndirections!(typeof(__traits(getMember, T, member)))) {
					if (!node.containsKey(memberName))
						continue;
				} else
					enforce(node.containsKey(memberName), new YAMLException("Missing non-@Optional "~memberName~" in node"));
				alias fromFunc = getConvertFromFunc!(T, __traits(getMember, output, member));
				static if (hasUDA!(__traits(getMember, T, member), IgnoreErrors)) {
					try {
						__traits(getMember, output, member) = fromFunc(node[memberName].fromYAML!(Parameters!(fromFunc)[0], flags));
					} catch (YAMLException) {}
				} else
					__traits(getMember, output, member) = fromFunc(node[memberName].fromYAML!(Parameters!(fromFunc)[0], flags));
			}
			return output;
		} else static if(isOutputRange!(T, ElementType!T)) {
			enforce(node.isSequence(), new YAMLException("Attempted to read a non-sequence as a "~T.stringof));
			T output;
			foreach (Node newNode; node)
				output ~= fromYAML!(ElementType!T, flags)(newNode);
			return output;
		} else static if (isStaticArray!T && isSomeChar!(ElementType!T)) {
			enforce(node.isScalar(), new YAMLException("Attempted to read a non-scalar as a "~T.stringof));
			T output;
			foreach (i, chr; node.fromYAML!((ForeachType!T)[], flags).byCodeUnit.enumerate(0))
				output[i] = chr;
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
			enforce(node.tag == `tag:yaml.org,2002:bool`, new YAMLException("Expecting a boolean value"));
			return node.get!T;
		} else
			static assert(false, "Cannot read type "~T.stringof~" from YAML"); //unreachable, hopefully.
	} catch (NodeException e) {
		throw new YAMLException(e.msg);
	}
}
private @property Node toYAML(BitFlags!Siryulize flags, string path = "", T)(T type) @safe if (!isInfinite!T) {
	import std.conv : text, to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.meta : AliasSeq;
	import std.traits : arity, FieldNameTuple, getUDAs, hasUDA, isAssociativeArray, isSomeString, isStaticArray, Unqual;
	alias Undecorated = Unqual!T;
	static if (hasUDA!(type, AsString) || is(Undecorated == enum)) {
		return Node(type.text);
	} else static if (isNullable!Undecorated) {
		if (type.isNull) {
			return Node(YAMLNull());
		} else {
			return type.get().toYAML!flags;
		}
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
	} else static if (isSomeString!Undecorated || (isStaticArray!Undecorated && isSomeChar!(ElementType!Undecorated))) {
		import std.utf : toUTF8;
		return type[].toUTF8().idup.toYAML!flags;
	} else static if(isAssociativeArray!Undecorated) {
		Node[Node] output;
		foreach (key, value; type)
			output[key.toYAML!flags] = value.toYAML!flags;
		return Node(output);
	} else static if(isSimpleList!Undecorated) {
		Node[] output;
		foreach (value; type)
			output ~= value.toYAML!(flags, path);
		return Node(output);
	} else static if (is(Undecorated == struct)) {
		static string[] empty;
		Node output = Node(empty, empty);
		foreach (member; FieldNameTuple!T) {
			debug enum newPath = path~"."~member;
			else enum newPath = "";
			static if (!!(flags & Siryulize.omitInits)) {
				static if (isNullable!(typeof(__traits(getMember, type, member)))) {
					if (__traits(getMember, type, member).isNull)
						continue;
				} else if (__traits(getMember, type, member) == __traits(getMember, type, member).init)
					continue;
			}
			enum memberName = getMemberName!(__traits(getMember, T, member));
			() @trusted {
				try {
					auto val = getConvertToFunc!(T, __traits(getMember, type, member))(__traits(getMember, type, member)).toYAML!(flags, newPath);
					static if (!!(flags & Siryulize.omitNulls)) {
						if (val !is null) {
							output.add(memberName, val);
						}
					} else {
						output.add(memberName, val);
					}
				} catch (Throwable e) {
					e.msg = "Error serializing "~newPath~": "~e.msg;
					throw e;
				}
			}();
		}
		return output;
	} else
		static assert(false, "Cannot write type "~T.stringof~" to YAML"); //unreachable, hopefully
}
private template canStoreUnchanged(T) {
	import std.traits : isFloatingPoint, isIntegral;
	enum canStoreUnchanged = isIntegral!T || is(T == bool) || isFloatingPoint!T || is(T == string);
}