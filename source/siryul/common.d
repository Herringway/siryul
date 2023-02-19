module siryul.common;
import std.meta : Filter, templateAnd, templateNot, templateOr;
import std.range : isInputRange, isOutputRange;
import std.traits : arity, getSymbolsByUDA, getUDAs, hasUDA, isArray, isAssociativeArray, isInstanceOf, isIterable, isSomeString, TemplateArgsOf, TemplateOf;
import std.typecons : BitFlags, Nullable, NullableRef;
import std.sumtype : SumType;
import core.time;

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
private struct Optional_ {}
private struct Required_ {}
private struct Skip_ {}
/++
 + Used when nonpresence of field is not an error. The field will be set to its
 + .init value. If being able to detect nonpresence is desired, ensure that
 + the default value cannot appear in the data or use a Nullable type.
 +/
enum Optional = Optional_.init;

///Used when nonpresence of field is an error.
enum Required = Required_.init;

///Used for fields that should be skipped
enum Skip = Skip_.init;

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
private struct AsString_ {}
private struct AsBinary_ {}
private struct SerializationMethod_ {}
private struct DeserializationMethod_ {}
///Write field as string
enum AsString = AsString_.init;
///Write field as binary (NYI)
enum AsBinary = AsBinary_.init;
///Marks a method for use in serialization
enum SerializationMethod = SerializationMethod_.init;
///Marks a method for use in deserialization
enum DeserializationMethod= DeserializationMethod_.init;

enum hasSerializationMethod(alias T) = is(typeof(serializationMethod!T));
template serializationMethod(alias T) {
	static foreach (m; __traits(allMembers, T)) {
		static foreach (overload; __traits(getOverloads, T, m)) {
			static if (!is(typeof(serializationMethod_)) && isSerializationMethod!overload) {
				alias serializationMethod_ = overload;
			} else static if (isSerializationMethod!overload) {
				static assert(!is(typeof(serializationMethod_)), "Only one serialization method may be specified");
			}
		}
	}
	alias serializationMethod = serializationMethod_;
}
template deserializationMethod(alias T) {
	static foreach (m; __traits(allMembers, T)) {
		static foreach (overload; __traits(getOverloads, T, m)) {
			static if (!is(typeof(deserializationMethod_)) && isDeserializationMethod!overload) {
				alias deserializationMethod_ = overload;
			} else static if (isDeserializationMethod!overload) {
				static assert(!is(typeof(deserializationMethod_)), "Only one deserialization method may be specified");
			}
		}
	}
	alias deserializationMethod = deserializationMethod_;
}
enum hasDeserializationMethod(alias T) = is(typeof(deserializationMethod!T));

enum hasSerializationTemplate(T) = is(typeof(T.toSiryulType));
alias serializationTemplate(T) = T.toSiryulType;
enum hasDeserializationTemplate(T) = is(typeof(T.fromSiryulType));
alias deserializationTemplate(T) = T.fromSiryulType;

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
		enum getMemberName = __traits(identifier, T);
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
	struct TimeTest {
		import std.datetime : SysTime;
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
		import std.datetime : SysTime;
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
		import std.datetime : SysTime;
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
	enum isTimeType = is(T : const SysTime) || is(T : const DateTime) || is(T : const Date) || is(T : const TimeOfDay);
}
unittest {
	import std.datetime : DateTime, Date, SysTime, TimeOfDay;
	static assert(isTimeType!SysTime);
	static assert(isTimeType!DateTime);
	static assert(isTimeType!Date);
	static assert(isTimeType!TimeOfDay);
	static assert(isTimeType!(immutable SysTime));
	static assert(isTimeType!(immutable DateTime));
	static assert(isTimeType!(immutable Date));
	static assert(isTimeType!(immutable TimeOfDay));
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

private struct ISO8601FormattedDuration {
	Duration duration;
	void tmp() {
		import std.array : Appender;
		Appender!(char[]) a;
		toString(a);
	}
	void toString(W)(ref W writer) const {
		import std.format : formattedWrite, sformat;
		import std.range : put;
		Duration temp = duration;
		put(writer, 'P');
		if (temp >= 1.weeks) {
			writer.formattedWrite!"%sW"(temp.total!"weeks");
			temp -= temp.total!"weeks".weeks;
		}
		if (temp >= 1.days) {
			writer.formattedWrite!"%sD"(temp.total!"days");
			temp -= temp.total!"days".days;
		}
		bool timePrinted;
		if (temp >= 1.hours) {
			writer.formattedWrite!"T%sH"(temp.total!"hours");
			temp -= temp.total!"hours".hours;
			timePrinted = true;
		}
		if (temp >= 1.minutes) {
			if (!timePrinted) {
				put(writer, 'T');
				timePrinted = true;
			}
			writer.formattedWrite!"%sM"(temp.total!"minutes");
			temp -= temp.total!"minutes".minutes;
		}
		if (temp > 0.seconds) {
			if (!timePrinted) {
				put(writer, 'T');
				timePrinted = true;
			}
			writer.formattedWrite!"%s"(temp.total!"seconds");
			temp -= temp.total!"seconds".seconds;
			if (temp > 0.seconds) {
				char[10] buffer;
				auto formatted = sformat!"%s"(buffer[], temp.total!"hnsecs" /  10_000_000.0);
				writer.formattedWrite!".%s"(formatted[2 .. $]);
			}
			put(writer, 'S');
		}
	}
}
ISO8601FormattedDuration asISO8601String(Duration duration) @safe pure nothrow {
	return ISO8601FormattedDuration(duration);
}

@safe pure unittest {
	import std.conv : text;
	assert(1.days.asISO8601String.text == "P1D");
	assert((1.days + 1.seconds).asISO8601String.text == "P1DT1S");
	assert(1.seconds.asISO8601String.text == "PT1S");
	assert((1.seconds + 100.msecs).asISO8601String.text == "PT1.1S");
}

Duration fromISODurationString(string str) @safe pure {
	import std.exception : enforce;
	import std.conv : parse;
	import std.math : ceil;
	string dateUnits = "YMWD";
	string timeUnits = "HMS";
	Duration result;
	enforce(str[0] == 'P', new Exception("Not an ISO8601 duration - String does not start with P"));
	str = str[1 .. $];
	bool timestamp;
	while (str.length > 0) {
		if (str[0] == 'T') {
			timestamp = true;
			str = str[1 .. $];
		}
		const amount = str.parse!double();
		if (timestamp) {
			while ((timeUnits.length > 0) && (timeUnits[0] != str[0])) {
				timeUnits = timeUnits[1 .. $];
			}
			if (timeUnits.length == 0) {
				throw new Exception("Unexpected time unit '"~str[0]~"' in string");
			}
			switch (str[0]) {
				case 'H':
					result += (cast(long)amount).hours;
					break;
				case 'M':
					result += (cast(long)amount).minutes;
					break;
				case 'S':
					result += (cast(long)amount).seconds;
					double fraction = ceil(amount) - amount;
					result += (cast(long)(fraction * 10_000_000)).hnsecs;
					break;
				default: assert(0);
			}
		} else {
			while ((dateUnits.length > 0) && (dateUnits[0] != str[0])) {
				dateUnits = dateUnits[1 .. $];
			}
			if (dateUnits.length == 0) {
				throw new Exception("Unexpected date unit '"~str[0]~"' in string");
			}
			switch (str[0]) {
				case 'Y':
				case 'M':
					throw new Exception("Ambiguous date unit '"~str[0]~"' in string");
				case 'W':
					result += (cast(long)amount).weeks;
					break;
				case 'D':
					result += (cast(long)amount).days;
					break;
				default: assert(0);
			}
		}
		str = str[1 .. $];
	}
	return result;
}

@safe pure unittest {
	assert("P1D".fromISODurationString == 1.days);
	assert("P1W1D".fromISODurationString == 1.weeks + 1.days);
	assert("P1W1DT0.5S".fromISODurationString == 1.weeks + 1.days + 500.msecs);
	assert("PT5S".fromISODurationString == 5.seconds);
}

private template typeMatches(T) {
	enum typeMatches(alias t) = is(typeof(t) == T);
}

enum isSerializationMethod(alias sym) = Filter!(typeMatches!SerializationMethod_, __traits(getAttributes, sym)).length == 1;

enum isDeserializationMethod(alias sym) = Filter!(typeMatches!DeserializationMethod_, __traits(getAttributes, sym)).length == 1;

enum isOptional(alias sym) = Filter!(typeMatches!Optional_, __traits(getAttributes, sym)).length == 1;

enum isRequired(alias sym) = Filter!(typeMatches!Required_, __traits(getAttributes, sym)).length == 1;

enum mustSkip(alias sym) = Filter!(typeMatches!Skip_, __traits(getAttributes, sym)).length == 1;

enum shouldStringify(alias sym) = Filter!(typeMatches!AsString_, __traits(getAttributes, sym)).length == 1;
