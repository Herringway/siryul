module siryul.common;
import std.meta : templateAnd, templateNot, templateOr;
import std.range : isInputRange, isOutputRange;
import std.traits : arity, getSymbolsByUDA, getUDAs, hasUDA, isArray, isAssociativeArray, isInstanceOf, isIterable, isSomeString, TemplateArgsOf, TemplateOf;
import std.typecons : BitFlags, Nullable, NullableRef;
import std.sumtype : SumType;

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

package enum isSumType(T) = isInstanceOf!(SumType, T);
static assert(isSumType!(SumType!int));
static assert(isSumType!(SumType!(int, bool)));
static assert(!isSumType!int);

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
		alias getConvertToFunc = __traits(getMember, T, getUDAs!(member, CustomParser)[0].toFunc);
	} else static if (is(typeof(T.toSiryulHelper!(member.stringof)))) {
		alias getConvertToFunc = T.toSiryulHelper!(member.stringof);
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
	assert(getConvertToFunc!(TimeTest2, TimeTest2.time)(SysTime.min) == "this has nothing to do with time.");
}
template hasConvertFromFunc(T, alias member) {
	static if (hasUDA!(member, CustomParser)) {
		enum hasConvertFromFunc = true;
	} else static if (is(typeof(T.fromSiryulHelper!(member.stringof)))) {
		enum hasConvertFromFunc = true;
	} else {
		enum hasConvertFromFunc = false;
	}
}
package template getConvertFromFunc(T, alias member) {
	static if (hasUDA!(member, CustomParser)) {
		import std.meta : AliasSeq;
		alias getConvertFromFunc = AliasSeq!(__traits(getMember, T, getUDAs!(member, CustomParser)[0].fromFunc))[0];
	} else static if (is(typeof(T.fromSiryulHelper!(member.stringof)))) {
		alias getConvertFromFunc = T.fromSiryulHelper!(member.stringof);
	}
	static assert(arity!getConvertFromFunc == 1, "Arity of conversion function must be exactly 1");
}
unittest {
	import std.datetime : SysTime;
	auto str1 = "yep";
	assert(getConvertFromFunc!(TimeTest, TimeTest.time)(str1) == SysTime.min);
	assert(getConvertFromFunc!(TimeTest2, TimeTest2.time)(str1) == SysTime.min);
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

bool isSkippableValue(BitFlags!Siryulize flags, T)(const scope ref T value) @safe pure {
	import std.traits : hasMember, isFloatingPoint;
	bool result = false;
	static if (flags.omitNulls) {
		static if (hasMember!(typeof(value), "isNull")) {
			if (value.isNull) {
				return true;
			}
		} else static if (is(typeof(value is null))) {
			if (value is null) {
				return true;
			}
		}
	}
	static if (flags.omitInits) {
		static if (is(typeof(T.init is null))) {
			if (value is T.init) {
				return true;
			}
		} else static if (isArray!T) {
			foreach (const element; value) {
				if (element != element.init) {
					return false;
				}
			}
			result = true;
		} else static if (T.init == T.init) {
			if (value == const(T).init) {
				return true;
			}
		} else static if (isFloatingPoint!T) {
			import std.math.traits : isNaN;
			if (value.isNaN) {
				return true;
			}
		}
	}
	return result;
}

@safe pure unittest {
	enum skipInits = BitFlags!Siryulize(Siryulize.omitInits);
	enum skipNulls = BitFlags!Siryulize(Siryulize.omitNulls);
	enum skipNothing = BitFlags!Siryulize();
	const nint = Nullable!int();
	assert(isSkippableValue!skipInits(nint));
	assert(isSkippableValue!skipNulls(nint));
	assert(!isSkippableValue!skipNothing(nint));

	const nint2 = Nullable!(int, 0)();
	assert(isSkippableValue!skipInits(nint2));
	assert(isSkippableValue!skipNulls(nint2));
	assert(!isSkippableValue!skipNothing(nint2));

	const nint3 = Nullable!(int, 100)();
	assert(isSkippableValue!skipInits(nint3));
	assert(isSkippableValue!skipNulls(nint3));
	assert(!isSkippableValue!skipNothing(nint3));

	const i = 0;
	assert(isSkippableValue!skipInits(i));
	assert(!isSkippableValue!skipNulls(i));
	assert(!isSkippableValue!skipNothing(i));

	const i2 = 1;
	assert(!isSkippableValue!skipInits(i2));
	assert(!isSkippableValue!skipNulls(i2));
	assert(!isSkippableValue!skipNothing(i2));

	const a = [];
	assert(isSkippableValue!skipInits(a));
	assert(isSkippableValue!skipNulls(a));
	assert(!isSkippableValue!skipNothing(a));

	const a2 = [1];
	assert(!isSkippableValue!skipInits(a2));
	assert(!isSkippableValue!skipNulls(a2));
	assert(!isSkippableValue!skipNothing(a2));

	const int[1] a3;
	assert(isSkippableValue!skipInits(a3));
	assert(!isSkippableValue!skipNulls(a3));
	assert(!isSkippableValue!skipNothing(a3));

	const string[string] aa;
	assert(isSkippableValue!skipInits(aa));
	assert(isSkippableValue!skipNulls(aa));
	assert(!isSkippableValue!skipNothing(aa));

	const aa2 = [1:1];
	assert(!isSkippableValue!skipInits(aa2));
	assert(!isSkippableValue!skipNulls(aa2));
	assert(!isSkippableValue!skipNothing(aa2));

	static struct AssocWrapped { int[int] a; }
	AssocWrapped aa3; // https://issues.dlang.org/show_bug.cgi?id=13622
	assert(isSkippableValue!skipInits(aa3));
	assert(!isSkippableValue!skipNulls(aa3));
	assert(!isSkippableValue!skipNothing(aa3));

	const int* p;
	assert(isSkippableValue!skipInits(p));
	assert(isSkippableValue!skipNulls(p));
	assert(!isSkippableValue!skipNothing(p));

	class X {}
	const X x;
	assert(isSkippableValue!skipInits(x));
	assert(isSkippableValue!skipNulls(x));
	assert(!isSkippableValue!skipNothing(x));

	struct Y {
		int a;
	}
	const Y y;
	assert(isSkippableValue!skipInits(y));
	assert(!isSkippableValue!skipNulls(y));
	assert(!isSkippableValue!skipNothing(y));

	const y2 =Y(1);
	assert(!isSkippableValue!skipInits(y2));
	assert(!isSkippableValue!skipNulls(y2));
	assert(!isSkippableValue!skipNothing(y2));

	const double f;
	assert(isSkippableValue!skipInits(f));
	assert(!isSkippableValue!skipNulls(f));
	assert(!isSkippableValue!skipNothing(f));

	const f2 = 2.0;
	assert(!isSkippableValue!skipInits(f2));
	assert(!isSkippableValue!skipNulls(f2));
	assert(!isSkippableValue!skipNothing(f2));
}

package void trustedAssign(T, T2)(out T dest, T2 val) @trusted {
	dest = val;
}
