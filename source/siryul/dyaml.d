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
	package enum emptyObject = "---\n...";
	package static T parseInput(T, DeSiryulize flags, U)(U data) if (isInputRange!U && isSomeChar!(ElementType!U)) {
		import std.conv : to;
		import std.utf : byChar;
		auto str = data.byChar.to!(char[]);
		auto loader = Loader.fromString(str).load();
		return loader.fromYAML!(T, BitFlags!DeSiryulize(flags));
	}
	package static string asString(Siryulize flags, T)(T data) {
		import std.array : appender;
		debug enum path = T.stringof;
		else enum path = "";
		auto buf = appender!string;
		auto dumper = dumper();
		dumper.defaultCollectionStyle = CollectionStyle.block;
		dumper.defaultScalarStyle = ScalarStyle.plain;
		dumper.explicitStart = false;
		dumper.dump(buf, toYAML!(BitFlags!Siryulize(flags))(data, path));
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
private T fromYAML(T, BitFlags!DeSiryulize flags)(Node node) if (!isInfinite!T) {
	import std.conv : to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.exception : enforce;
	import std.meta : AliasSeq;
	import std.range : enumerate, isOutputRange;
	import std.traits : arity, FieldNameTuple, ForeachType, getUDAs, hasIndirections, hasUDA, isArray, isAssociativeArray, isFloatingPoint, isIntegral, isPointer, isSomeString, isStaticArray, KeyType, OriginalType, Parameters, PointerTarget, TemplateArgsOf, ValueType;
	import std.utf : byCodeUnit;
	if (node.type == NodeType.null_) {
		return T.init;
	}
	try {
		static if (is(T == struct) && hasDeserializationMethod!T) {
			return deserializationMethod!T(fromYAML!(Parameters!(deserializationMethod!T), flags)(node));
		} else static if (is(T == enum)) {
			enforce!YAMLDException(node.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
			if (node.tag == `tag:yaml.org,2002:str`)
				return node.get!string.to!T;
			else
				return node.fromYAML!(OriginalType!T, flags).to!T;
		} else static if (isNullable!T) {
			return node.type == NodeType.null_ ? T.init : T(node.fromYAML!(TemplateArgsOf!T[0], flags));
		} else static if (isIntegral!T || isSomeString!T || isFloatingPoint!T) {
			enforce!YAMLDException(node.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
			if (node.tag == `tag:yaml.org,2002:str`)
				return node.get!string.to!T;
			static if (isIntegral!T) {
				enforce!YAMLDException(node.tag == `tag:yaml.org,2002:int`, "Attempted to read a float as an integer");
				return node.get!T;
			} else static if (isSomeString!T) {
				enforce!YAMLDException(node.tag != `tag:yaml.org,2002:bool`, "Attempted to read a non-string as a string");
				return node.get!string.to!T;
			} else {
				return node.get!T;
			}
		} else static if (isSomeChar!T) {
			import std.array : front;
			enforce!YAMLDException(node.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
			return cast(T)node.get!string.front;
		} else static if (is(T == SysTime) || is(T == DateTime) || is(T == Date)) {
			enforce!YAMLDException(node.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
			return node.get!SysTime.to!T;
		} else static if (is(T == TimeOfDay)) {
			enforce!YAMLDException(node.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
			return TimeOfDay.fromISOExtString(node.get!string);
		} else static if (is(T == struct)  || (isPointer!T && is(PointerTarget!T == struct))) {
			enforce!YAMLDException(node.nodeID == NodeID.mapping, "Attempted to read a non-mapping as a "~T.stringof);
			T output;
			static if (isPointer!T) {
				output = new PointerTarget!T;
				alias Undecorated = PointerTarget!T;
			} else {
				alias Undecorated = T;
			}
			foreach (member; FieldNameTuple!Undecorated) {
				static if (__traits(getProtection, __traits(getMember, Undecorated, member)) == "public") {
					alias field = AliasSeq!(__traits(getMember, Undecorated, member));
					enum memberName = getMemberName!field;
					static if ((hasUDA!(field, Optional) || (!!(flags & DeSiryulize.optionalByDefault))) || hasIndirections!(typeof(field))) {
						if (!node.containsKey(memberName))
							continue;
					} else {
						enforce!YAMLDException(node.containsKey(memberName), "Missing non-@Optional "~memberName~" in node");
					}
					alias fromFunc = getConvertFromFunc!(T, __traits(getMember, Undecorated, member));
					static if (hasUDA!(__traits(getMember, Undecorated, member), IgnoreErrors)) {
						try {
							__traits(getMember, output, member) = fromFunc(node[memberName].fromYAML!(Parameters!(fromFunc)[0], flags));
						} catch (YAMLDException) {}
					} else
						__traits(getMember, output, member) = fromFunc(node[memberName].fromYAML!(Parameters!(fromFunc)[0], flags));
				}
			}
			return output;
		} else static if(isOutputRange!(T, ElementType!T)) {
			enforce!YAMLDException(node.nodeID == NodeID.sequence, "Attempted to read a non-sequence as a "~T.stringof);
			T output;
			foreach (Node newNode; node)
				output ~= fromYAML!(ElementType!T, flags)(newNode);
			return output;
		} else static if (isStaticArray!T && isSomeChar!(ElementType!T)) {
			enforce!YAMLDException(node.nodeID == NodeID.scalar, "Attempted to read a non-scalar as a "~T.stringof);
			T output;
			foreach (i, chr; node.fromYAML!((ForeachType!T)[], flags).byCodeUnit.enumerate(0))
				output[i] = chr;
			return output;
		} else static if(isStaticArray!T) {
			enforce!YAMLDException(node.nodeID == NodeID.sequence, "Attempted to read a non-sequence as a "~T.stringof);
			T output;
			size_t i;
			foreach (Node newNode; node)
				output[i++] = fromYAML!(ElementType!T, flags)(newNode);
			return output;
		} else static if(isAssociativeArray!T) {
			enforce!YAMLDException(node.nodeID == NodeID.mapping, "Attempted to read a non-mapping as a "~T.stringof);
			T output;
			foreach (Node key, Node value; node)
				output[fromYAML!(KeyType!T, flags)(key)] = fromYAML!(ValueType!T, flags)(value);
			return output;
		} else static if (is(T == bool)) {
			enforce!YAMLDException(node.tag == `tag:yaml.org,2002:bool`, "Expecting a boolean value");
			return node.get!T;
		} else
			static assert(false, "Cannot read type "~T.stringof~" from YAML"); //unreachable, hopefully.
	} catch (NodeException e) {
		throw new YAMLDException(e.msg);
	}
}
private @property Node toYAML(BitFlags!Siryulize flags, T)(T type, string path = "") if (!isInfinite!T) {
	import std.conv : text, to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.meta : AliasSeq;
	import std.traits : arity, FieldNameTuple, getSymbolsByUDA, getUDAs, hasUDA, isAssociativeArray, isPointer, isSomeString, isStaticArray, PointerTarget, Unqual;
	static if (isPointer!T) {
		alias Undecorated = Unqual!(PointerTarget!T);
	} else {
		alias Undecorated = Unqual!T;
	}
	static if (is(T == struct) && hasSerializationMethod!T) {
		return toYAML!flags(mixin("type."~__traits(identifier, serializationMethod!T)), path);
	} else static if (hasUDA!(type, AsString) || is(Undecorated == enum)) {
		return Node(type.text);
	} else static if (isNullable!Undecorated) {
		if (type.isNull) {
			return Node(YAMLNull());
		} else {
			return toYAML!flags(type.get(), path);
		}
	} else static if (is(Undecorated == SysTime)) {
		return Node(type.to!Undecorated, "tag:yaml.org,2002:timestamp");
	} else static if (is(Undecorated == DateTime) || is(Undecorated == Date)) {
		return Node(type.toISOExtString(), "tag:yaml.org,2002:timestamp");
	} else static if (is(Undecorated == TimeOfDay)) {
		return Node(type.toISOExtString());
	} else static if (isSomeChar!Undecorated) {
		return toYAML!flags([type], path);
	} else static if (canStoreUnchanged!Undecorated) {
		return Node(type.to!Undecorated);
	} else static if (isSomeString!Undecorated || (isStaticArray!Undecorated && isSomeChar!(ElementType!Undecorated))) {
		import std.utf : toUTF8;
		return toYAML!flags(type[].toUTF8().idup, path);
	} else static if(isAssociativeArray!Undecorated) {
		Node[Node] output;
		foreach (key, value; type)
			output[toYAML!flags(key, path)] = toYAML!flags(value, path);
		return Node(output);
	} else static if(isSimpleList!Undecorated) {
		Node[] output;
		foreach (value; type)
			output ~= toYAML!flags(value, path);
		return Node(output);
	} else static if (is(Undecorated == struct)) {
		static string[] empty;
		Node output = Node(empty, empty);
		foreach (member; FieldNameTuple!Undecorated) {
			static if (__traits(getProtection, __traits(getMember, Undecorated, member)) == "public") {
				debug string newPath = path~"."~member;
				else string newPath = "";
				static if (!!(flags & Siryulize.omitInits)) {
					static if (isNullable!(typeof(__traits(getMember, type, member)))) {
						if (__traits(getMember, type, member).isNull)
							continue;
					} else {
						if (__traits(getMember, type, member) == __traits(getMember, type, member).init) {
							continue;
						}
					}
				}
				enum memberName = getMemberName!(__traits(getMember, Undecorated, member));
				try {
					static if (isPointer!(typeof(mixin("type."~member))) && !!(flags & Siryulize.omitNulls)) {
						if (mixin("type."~member) is null) {
							continue;
						}
					}
					static if (hasConvertToFunc!(T, __traits(getMember, Undecorated, member))) {
						auto val = toYAML!flags(getConvertToFunc!(T, __traits(getMember, Undecorated, member))(mixin("type."~member)), newPath);
						output.add(memberName, val);
					} else {
						output.add(memberName, toYAML!(flags)(mixin("type."~member), newPath));
					}
				} catch (Exception e) {
					e.msg = "Error serializing "~newPath~": "~e.msg;
					throw e;
				}
			}
		}
		return output;
	} else
		static assert(false, "Cannot write type "~T.stringof~" to YAML"); //unreachable, hopefully
}
private template canStoreUnchanged(T) {
	import std.traits : isFloatingPoint, isIntegral;
	enum canStoreUnchanged = isIntegral!T || is(T == bool) || isFloatingPoint!T || is(T == string);
}