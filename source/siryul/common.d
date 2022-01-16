module siryul.common;
import std.meta : templateAnd, templateNot, templateOr;
import std.range : isInputRange, isOutputRange;
import std.traits : arity, getSymbolsByUDA, getUDAs, hasUDA, isArray, isAssociativeArray, isInstanceOf, isIterable, isSomeString, TemplateArgsOf, TemplateOf;
import std.typecons : BitFlags, Nullable, NullableRef;
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
	ErrorMark mark;
	package this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
	package this(ErrorMark mark, string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		import std.conv : text;
		this.mark = mark;
		try {
			super(text(mark, ": ",msg), file, line);
		} catch (Exception) { assert(0); }
	}
}

struct ErrorMark {
	string filename = "<unknown>";
	ulong line;
	ulong column;
	void toString(T)(T sink) const if (isOutputRange!(T, char[])) {
		import std.format : formattedWrite;
		sink.formattedWrite!"%s (line %s, column %s)"(filename, line, column);
	}
}

package enum isNullable(T) = isInstanceOf!(Nullable, T);
static assert(isNullable!(Nullable!int));
static assert(isNullable!(Nullable!(int, 0)));
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
/++
 + Used when nonpresence of field is not an error. The field will be set to its
 + .init value. If being able to detect nonpresence is desired, ensure that
 + the default value cannot appear in the data or use a Nullable type.
 +/
enum Optional;

///Used when nonpresence of field is an error.
enum Required;

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
///Errors are ignored; value will be .init
enum IgnoreErrors;
///Marks a method for use in serialization
enum SerializationMethod;
///Marks a method for use in deserialization
enum DeserializationMethod;

enum hasSerializationMethod(T) = getSymbolsByUDA!(T, SerializationMethod).length == 1;
alias serializationMethod(T) = getSymbolsByUDA!(T, SerializationMethod)[0];
enum hasDeserializationMethod(T) = getSymbolsByUDA!(T, DeserializationMethod).length == 1;
alias deserializationMethod(T) = getSymbolsByUDA!(T, DeserializationMethod)[0];

alias isSimpleList = templateAnd!(isIterable, templateNot!isSomeString, templateNot!isAssociativeArray);
static assert(isSimpleList!(int[]));
static assert(isSimpleList!(string[]));
static assert(!isSimpleList!(string));
static assert(!isSimpleList!(char[]));
static assert(!isSimpleList!(int));
static assert(!isSimpleList!(int[string]));
static assert(isSimpleList!(char[10]));

package template getMemberName(alias T) {
	static if (hasUDA!(T, SiryulizeAs)) {
		enum getMemberName = getUDAs!(T, SiryulizeAs)[0].name;
	} else
		enum getMemberName = T.stringof;
}
unittest {
	struct TestStruct {
		string something;
		@SiryulizeAs("Test") string somethingElse;
	}
	assert(getMemberName!(__traits(getMember, TestStruct, "something")) == "something");
	assert(getMemberName!(__traits(getMember, TestStruct, "somethingElse")) == "Test");
}
template hasConvertToFunc(T, alias member) {
	static if (hasUDA!(member, CustomParser)) {
		enum hasConvertToFunc = true;
	} else static if (is(typeof(T.toSiryulHelper!(member.stringof)))) {
		enum hasConvertToFunc = true;
	} else {
		enum hasConvertToFunc = false;
	}
}
package template getConvertToFunc(T, alias member) {
	static if (hasUDA!(member, CustomParser)) {
		import std.meta : AliasSeq;
		alias getConvertToFunc = AliasSeq!(__traits(getMember, T, getUDAs!(member, CustomParser)[0].toFunc))[0];
	} else static if (is(typeof(T.toSiryulHelper!(member.stringof)))) {
		alias getConvertToFunc = T.toSiryulHelper!(member.stringof);
	} else {
		alias getConvertToFunc = (const(typeof(member)) v) { return v; };
	}
	static assert(arity!getConvertToFunc == 1, "Arity of conversion function must be exactly 1");
}
version(unittest) {
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
	struct TimeTest2 {
		SysTime time;
		string nothing;
		static auto toSiryulHelper(string T)(SysTime) if(T == "time") {
			return "this has nothing to do with time.";
		}
		static auto fromSiryulHelper(string T)(string) if (T == "time") {
			return SysTime.min;
		}
	}
}
unittest {
	import std.datetime : SysTime;
	assert(getConvertToFunc!(TimeTest, TimeTest.time)(SysTime.min) == "this has nothing to do with time.");
	assert(getConvertToFunc!(TimeTest, TimeTest.nothing)("test") == "test");
	assert(getConvertToFunc!(TimeTest2, TimeTest2.time)(SysTime.min) == "this has nothing to do with time.");
	assert(getConvertToFunc!(TimeTest2, TimeTest2.nothing)("test") == "test");
}
package template getConvertFromFunc(T, alias member) {
	static if (hasUDA!(member, CustomParser)) {
		import std.meta : AliasSeq;
		alias getConvertFromFunc = AliasSeq!(__traits(getMember, T, getUDAs!(member, CustomParser)[0].fromFunc))[0];
	} else static if (is(typeof(T.fromSiryulHelper!(member.stringof)))) {
		alias getConvertFromFunc = T.fromSiryulHelper!(member.stringof);
	} else {
		alias getConvertFromFunc = (typeof(member) v) { return v; };
	}
	static assert(arity!getConvertFromFunc == 1, "Arity of conversion function must be exactly 1");
}
unittest {
	import std.datetime : SysTime;
	assert(getConvertFromFunc!(TimeTest, TimeTest.time)("yep") == SysTime.min);
	assert(getConvertFromFunc!(TimeTest, TimeTest.nothing)("test") == "test");
	assert(getConvertFromFunc!(TimeTest2, TimeTest2.time)("yep") == SysTime.min);
	assert(getConvertFromFunc!(TimeTest2, TimeTest2.nothing)("test") == "test");
}

template isStaticString(T) {
	import std.range : ElementType;
	import std.traits : isSomeChar, isStaticArray;
	enum isStaticString = isStaticArray!T && isSomeChar!(ElementType!T);
}
template isTimeType(T) {
	import std.datetime : DateTime, Date, SysTime, TimeOfDay;
	enum isTimeType = is(T == SysTime) || is(T == DateTime) || is(T == Date) || is(T == TimeOfDay);
}
