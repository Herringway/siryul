module siryul.common;
import std.typecons : Nullable, NullableRef;
import std.traits : TemplateArgsOf, hasUDA, getUDAs, arity;
///Serialization options
enum Siryulize {
	none, ///Default behaviour
	omitNulls = 1 << 0, ///Omit null values from output
	omitInits = 1 << 1 ///Omit values == type.init from output
}
///Deserialization options
enum DeSiryulize {
	none, ///Default behaviour
	optionalByDefault = 1 << 0 ///All members will be considered to be @Optional
}
/++
 + Thrown when an error occurs
 +/
class SiryulException : Exception {
	package this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
/++
 + Thrown when a serialization error occurs
 +/
class SerializeException : SiryulException {
	package this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
/++
 + Thrown when a deserialization error occurs
 +/
class DeserializeException : SiryulException {
	package this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
package template isNullable(T) {
	enum isNullable = isNullableValue!T || isNullableRef!T;
}
package template isNullableValue(T) {
	static if(__traits(compiles, TemplateArgsOf!T) && __traits(compiles, Nullable!(TemplateArgsOf!T)) && is(T == Nullable!(TemplateArgsOf!T)))
		enum isNullableValue = true;
	else
		enum isNullableValue = false;
}
package template isNullableRef(T) {
	static if(__traits(compiles, TemplateArgsOf!T) && __traits(compiles, NullableRef!(TemplateArgsOf!T)) && is(T == NullableRef!(TemplateArgsOf!T)))
		enum isNullableRef = true;
	else
		enum isNullableRef = false;
}
static assert(isNullable!(Nullable!int));
static assert(isNullable!(Nullable!(int, 0)));
static assert(isNullable!(NullableRef!int));
static assert(!isNullable!int);

/++
 + (De)serialize field using a different name.
 +
 + Especially useful for fields that happen to use D keywords.
 +/
struct SiryulizeAs {
	///Serialized field name
	string name;
}
///Used when nonpresence of field is not an error
enum Optional;
/++
 + Use custom parser functions for a given field.
 +
 + The function names must exist as methods in the struct. Any (de)serializable
 + type may be used for fromFunc's argument and toFunc's return value, but
 + fromFunc's return type and toFunc's argument type must be the same as the
 + field's type.
 +/
struct CustomParser {
	///Function to be used in deserialization
	string fromFunc;
	///Function to be used in serialization
	string toFunc;
}
///Write field as string
enum AsString;
///Write field as binary (NYI)
enum AsBinary;
package template isSimpleList(T) {
	import std.traits : isSomeString, isArray;
	import std.range : isInputRange;
	enum isSimpleList = isInputRange!T || (isArray!T && !isSomeString!T);
}
package T* moveToHeap(T)(ref T value) {
    import core.memory : GC;
    import std.algorithm : moveEmplace;
    auto ptr = cast(T*)GC.malloc(T.sizeof, 0, typeid(T));
    moveEmplace(value, *ptr);
    return ptr;
}
package template getMemberName(alias T, string def) {
	static if (hasUDA!(T, SiryulizeAs)) {
		enum getMemberName = getUDAs!(T, SiryulizeAs)[0].name;
	} else
		enum getMemberName = def;
}
unittest {
	struct TestStruct {
		string something;
		@SiryulizeAs("Test") string somethingElse;
	}
	assert(getMemberName!(__traits(getMember, TestStruct, "something"), "something") == "something");
	assert(getMemberName!(__traits(getMember, TestStruct, "somethingElse"), "somethingElse") == "Test");
}
package template getConvertToFunc(T, alias member) {
	static if (hasUDA!(member, CustomParser)) {
		import std.meta : AliasSeq;
		alias getConvertToFunc = AliasSeq!(__traits(getMember, T, getUDAs!(member, CustomParser)[0].toFunc))[0];
		static assert(arity!getConvertToFunc == 1, "Arity of conversion function must be exactly 1");
	} else
		alias getConvertToFunc = (const(typeof(member)) v) { return v; };
}
unittest {
	import std.datetime : SysTime;
	struct TimeTest {
		@CustomParser("fromJunk", "toJunk") SysTime time;
		string nothing;
		static SysTime fromJunk(string) {
			return SysTime.min;
		}
		static string toJunk(SysTime) {
			return "this has nothing to do with time.";
		}
	}
	assert(getConvertToFunc!(TimeTest, TimeTest.time)(SysTime.min) == "this has nothing to do with time.");
	assert(getConvertToFunc!(TimeTest, TimeTest.nothing)("test") == "test");
}
package template getConvertFromFunc(T, alias member) {
	static if (hasUDA!(member, CustomParser)) {
		import std.meta : AliasSeq;
		alias getConvertFromFunc = AliasSeq!(__traits(getMember, T, getUDAs!(member, CustomParser)[0].fromFunc))[0];
		static assert(arity!getConvertFromFunc == 1, "Arity of conversion function must be exactly 1");
	} else
		alias getConvertFromFunc = (typeof(member) v) { return v; };
}
unittest {
	import std.datetime : SysTime;
	struct TimeTest {
		@CustomParser("fromJunk", "toJunk") SysTime time;
		string nothing;
		static SysTime fromJunk(string) {
			return SysTime.min;
		}
		static string toJunk(SysTime) {
			return "this has nothing to do with time.";
		}
	}
	assert(getConvertFromFunc!(TimeTest, TimeTest.time)("yep") == SysTime.min);
	assert(getConvertFromFunc!(TimeTest, TimeTest.nothing)("test") == "test");
}