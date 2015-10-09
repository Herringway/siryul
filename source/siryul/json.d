module siryul.json;
import siryul;
private import std.json : JSONValue, parseJSON, toJSON, JSON_TYPE;
import std.traits, std.range;
import std.typecons;
/++
 + JSON (JavaScript Object Notation) serialization format
 +
 + Note that only strings are supported for associative array keys in this format.
 +/
struct JSON {
	static T parseString(T)(string data) @trusted {
		return parseJSON(data).fromJSON!T();
	}
	static string asString(T)(T data) @trusted {
		auto json = data.toJSON;
		return (&json).toJSON(true);
	}
}

private T fromJSON(T)(JSONValue node) @trusted if (!isInfinite!T) {
	import std.traits, std.exception, std.datetime, std.range, std.conv;
	import std.range.primitives : ElementType;
	import std.conv : to;
	import std.meta : AliasSeq;
	static if (is(T == enum)) {
		import std.conv : to;
		if (node.type == JSON_TYPE.STRING)
			return node.str.to!T;
		else
			return node.fromJSON!(OriginalType!T).to!T;
	} else static if (isIntegral!T) {
		if (node.type == JSON_TYPE.STRING)
			return node.str.to!T;
		enforce(node.type == JSON_TYPE.INTEGER, new JSONException("Expecting integer, got "~node.type.text));
		return node.integer.to!T;
	} else static if (isNullable!T) {
		T output;
		if (node.type == JSON_TYPE.NULL)
			output.nullify();
		else
			output = node.fromJSON!(TemplateArgsOf!T[0]);
		return output;
	} else static if (isFloatingPoint!T) {
		if (node.type == JSON_TYPE.STRING)
			return node.str.to!T;
		enforce(node.type == JSON_TYPE.FLOAT, new JSONException("Expecting floating point, got "~node.type.text));
		return node.floating.to!T;
	} else static if (isSomeString!T) {
		if (node.type == JSON_TYPE.INTEGER)
			return node.integer.to!T;
		if (node.type == JSON_TYPE.NULL)
			return T.init;
		return node.str.to!T;
	} else static if (isSomeChar!T) {
		enforce(node.type == JSON_TYPE.STRING || node.type == JSON_TYPE.NULL, new JSONException("Expecting string, got "~node.type.text));
		if (node.type == JSON_TYPE.NULL)
			return T.init;
		return node.str.front.to!T;
	} else static if (is(T == SysTime) || is(T == DateTime) || is(T == Date) || is(T == TimeOfDay)) {
		enforce(node.type == JSON_TYPE.STRING, new JSONException("Expecting timestamp string, got "~node.type.text));
		return T.fromISOExtString(node.str);
	} else static if (is(T == struct)) {
		enforce(node.type == JSON_TYPE.OBJECT, new JSONException("Expecting object, got "~node.type.text));
		T output;
		foreach (member; FieldNameTuple!T) {
			string memberName = member;
			static if (hasUDA!(__traits(getMember, T, member), SiryulizeAs)) {
				memberName = getUDAValue!(__traits(getMember, T, member), SiryulizeAs).name;
			}
			static if (hasUDA!(__traits(getMember, T, member), Optional) || hasIndirections!(typeof(__traits(getMember, T, member)))) {
				if ((memberName !in node.object) || (node.object[memberName].type == JSON_TYPE.NULL))
					continue;
			} else
				enforce(memberName in node.object, new JSONException("Missing non-@Optional "~memberName~" in node"));
			static if (hasUDA!(__traits(getMember, T, member), CustomParser)) {
				alias fromFunc = AliasSeq!(__traits(getMember, output, getUDAValue!(__traits(getMember, output, member), CustomParser).fromFunc))[0];
				assert(arity!fromFunc == 1, "Arity of conversion function must be exactly 1");
				__traits(getMember, output, member) = fromFunc(node[memberName].fromJSON!(Parameters!(fromFunc)[0]));
			} else 
				__traits(getMember, output, member) = fromJSON!(typeof(__traits(getMember, T, member)))(node[memberName]);
		}
		return output;
	} else static if(isOutputRange!(T, ElementType!T)) {
		enforce(node.type == JSON_TYPE.ARRAY, new JSONException("Expecting array, got "~node.type.text));
		T output;
		foreach (JSONValue newNode; node.array)
			output ~= fromJSON!(ElementType!T)(newNode);
		return output;
	} else static if(isStaticArray!T) {
		enforce(node.type == JSON_TYPE.ARRAY, new JSONException("Expecting array, got "~node.type.text));
		T output;
		size_t i;
		foreach (JSONValue newNode; node.array)
			output[i++] = fromJSON!(ElementType!T)(newNode);
		return output;
	} else static if(isAssociativeArray!T) {
		enforce(node.type == JSON_TYPE.OBJECT, new JSONException("Expecting object, got "~node.type.text));
		T output;
		foreach (string key, JSONValue value; node.object)
			output[key] = fromJSON!(ValueType!T)(value);
		return output;
	} else static if (is(T == bool)) {
		if (node.type == JSON_TYPE.TRUE)
			return true;
		else if (node.type == JSON_TYPE.FALSE)
			return false;
		throw new JSONException("Expecting true/false, got "~node.type.text);
	} else
		static assert(false, "Cannot read type "~T.stringof~" from YAML"); //unreachable, hopefully.
}

private @property JSONValue toJSON(T)(T type) @trusted if (!isInfinite!T) {
	import std.traits, std.datetime, std.range;
	import std.conv : text;
	import std.meta : AliasSeq;
	JSONValue output;
	static if (hasUDA!(type, AsString) || is(T == enum)) {
		output = JSONValue(type.text);
	} else static if (isNullable!T) {
		if (type.isNull)
			output = JSONValue();
		else
			output = JSONValue(type.get());
	} else static if (is(T == SysTime) || is(T == DateTime) || is(T == Date) || is(T == TimeOfDay)) {
		output = JSONValue(type.toISOExtString());
	} else static if (isIntegral!T || is(T == string) || is(T == bool) || isFloatingPoint!T) {
		output = JSONValue(type);
	} else static if (isSomeString!T) {
		import std.utf;
		output = JSONValue(type.toUTF8);
	} else static if (isSomeChar!T) {
		output = [type].idup.toJSON;
	} else static if (isAssociativeArray!T) {
		string[string] arr;
		output = JSONValue(arr);
		foreach (key, value; type)
			output.object[key.text] = value.toJSON;
	} else static if(isInputRange!T || isArray!T) {
		string[] arr;
		output = JSONValue(arr);
		foreach (value; type)
			output.array ~= value.toJSON;
	} else static if (is(T == struct)) {
		string[string] arr;
		output = JSONValue(arr);
		foreach (member; FieldNameTuple!T) {
			string memberName = member;
			static if (hasUDA!(__traits(getMember, T, member), SiryulizeAs))
				memberName = getUDAValue!(__traits(getMember, T, member), SiryulizeAs).name;
			static if (hasUDA!(__traits(getMember, T, member), CustomParser)) {
				alias toFunc = AliasSeq!(__traits(getMember, type, getUDAValue!(__traits(getMember, type, member), CustomParser).toFunc))[0];
				assert(arity!toFunc == 1, "Arity of conversion function must be exactly 1");
				output.object[memberName] = toFunc(__traits(getMember, type, member)).toJSON;
			} else
				output.object[memberName] = __traits(getMember, type, member).toJSON;
		}
	} else
		static assert(false, "Cannot write type "~T.stringof~" to YAML"); //unreachable, hopefully
	return output;
}
class JSONException : DeserializeException {
	this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}