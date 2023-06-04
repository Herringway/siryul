module siryul.common;
import std.datetime : Date, DateTime, SysTime;
import std.format;
import std.meta : Filter, templateAnd, templateNot, templateOr;
import std.range : ElementType, isInputRange, isOutputRange;
import std.traits;
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
	Mark mark;
	package this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
	package this(Mark mark, string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		import std.conv : text;
		this.mark = mark;
		try {
			super(text(mark, ": ",msg), file, line);
		} catch (Exception) { assert(0); }
	}
	package this(string msg, Nullable!Mark mark, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		if (mark.isNull) {
			this(msg, file, line);
		} else {
			this(mark.get, msg, file, line);
		}
	}
}

struct Mark {
	string filename = "<unknown>";
	ulong line;
	ulong column;
	void toString(T)(T sink) const if (isOutputRange!(T, char[])) {
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
bool isSkippableValue(T)(const scope ref T value, BitFlags!Siryulize flags) @safe pure {
	import std.traits : hasMember, isFloatingPoint;
	bool result = false;
	if (flags.omitNulls) {
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
	if (flags.omitInits) {
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
	void runTest(T)(T value, bool[3] expected) {
		assert(isSkippableValue(value, skipInits) == expected[0]);
		assert(isSkippableValue(value, skipNulls) == expected[1]);
		assert(isSkippableValue(value, skipNothing) == expected[2]);
	}
	const nint = Nullable!int();
	assert(isSkippableValue(nint, skipInits));
	assert(isSkippableValue(nint, skipNulls));
	assert(!isSkippableValue(nint, skipNothing));

	const nint2 = Nullable!(int, 0)();
	assert(isSkippableValue(nint2, skipInits));
	assert(isSkippableValue(nint2, skipNulls));
	assert(!isSkippableValue(nint2, skipNothing));

	const nint3 = Nullable!(int, 100)();
	assert(isSkippableValue(nint3, skipInits));
	assert(isSkippableValue(nint3, skipNulls));
	assert(!isSkippableValue(nint3, skipNothing));

	const i = 0;
	assert(isSkippableValue(i, skipInits));
	assert(!isSkippableValue(i, skipNulls));
	assert(!isSkippableValue(i, skipNothing));

	const i2 = 1;
	assert(!isSkippableValue(i2, skipInits));
	assert(!isSkippableValue(i2, skipNulls));
	assert(!isSkippableValue(i2, skipNothing));

	const a = [];
	assert(isSkippableValue(a, skipInits));
	assert(isSkippableValue(a, skipNulls));
	assert(!isSkippableValue(a, skipNothing));

	const a2 = [1];
	assert(!isSkippableValue(a2, skipInits));
	assert(!isSkippableValue(a2, skipNulls));
	assert(!isSkippableValue(a2, skipNothing));

	const int[1] a3;
	assert(isSkippableValue(a3, skipInits));
	assert(!isSkippableValue(a3, skipNulls));
	assert(!isSkippableValue(a3, skipNothing));

	const string[string] aa;
	assert(isSkippableValue(aa, skipInits));
	assert(isSkippableValue(aa, skipNulls));
	assert(!isSkippableValue(aa, skipNothing));

	const aa2 = [1:1];
	assert(!isSkippableValue(aa2, skipInits));
	assert(!isSkippableValue(aa2, skipNulls));
	assert(!isSkippableValue(aa2, skipNothing));

	static struct AssocWrapped { int[int] a; }
	AssocWrapped aa3; // https://issues.dlang.org/show_bug.cgi?id=13622
	assert(isSkippableValue(aa3, skipInits));
	assert(!isSkippableValue(aa3, skipNulls));
	assert(!isSkippableValue(aa3, skipNothing));

	const int* p;
	assert(isSkippableValue(p, skipInits));
	assert(isSkippableValue(p, skipNulls));
	assert(!isSkippableValue(p, skipNothing));

	class X {}
	const X x;
	assert(isSkippableValue(x, skipInits));
	assert(isSkippableValue(x, skipNulls));
	assert(!isSkippableValue(x, skipNothing));

	struct Y {
		int a;
	}
	const Y y;
	assert(isSkippableValue(y, skipInits));
	assert(!isSkippableValue(y, skipNulls));
	assert(!isSkippableValue(y, skipNothing));

	const y2 =Y(1);
	assert(!isSkippableValue(y2, skipInits));
	assert(!isSkippableValue(y2, skipNulls));
	assert(!isSkippableValue(y2, skipNothing));

	const double f;
	assert(isSkippableValue(f, skipInits));
	assert(!isSkippableValue(f, skipNulls));
	assert(!isSkippableValue(f, skipNothing));

	const f2 = 2.0;
	assert(!isSkippableValue(f2, skipInits));
	assert(!isSkippableValue(f2, skipNulls));
	assert(!isSkippableValue(f2, skipNothing));
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

package enum Classification {
	scalar,
	sequence,
	mapping,
}

void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isIntegral!T && !(is(T == enum))) {
	if (node.hasTypeConvertible!(const(char)[])) {
		result = node.getType!(const(char)[]).tryConvert!T(node.getMark);
	} else if (node.hasTypeConvertible!long) {
		result = cast(T)node.getType!long();
	} else if (node.hasTypeConvertible!ulong) {
		result = cast(T)node.getType!ulong();
	} else {
		throw new DeserializeException(format!"Could not convert node of type '%s' to integral type"(node.type), node.getMark);
	}
}
void deserialize(NodeType)(NodeType node, out bool result, BitFlags!DeSiryulize flags) {
	if (node.hasTypeConvertible!bool) {
		result = node.getType!bool;
	} else {
		throw new DeserializeException("Could not convert node to boolean type", node.getMark);
	}
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isSomeString!T) {
	if (node.hasTypeConvertible!(typeof(null))) {
		// result is already a null string
	} else if (node.hasTypeConvertible!string) {
		result = node.getType!string.tryConvert!T(node.getMark);
	} else if (node.hasTypeConvertible!long) {
		result = node.getType!long.tryConvert!T(node.getMark);
	} else if (node.hasTypeConvertible!ulong) {
		result = node.getType!ulong.tryConvert!T(node.getMark);
	} else if (node.hasTypeConvertible!real) {
		result = node.getType!real.tryConvert!T(node.getMark);
	} else {
		throw new DeserializeException("Could not convert node to string", node.getMark);
	}
}
void deserialize(T : P*, P, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) {
	result = new P;
	deserialize(node, *result, flags);
}

void deserialize(NodeType)(NodeType, out typeof(null), BitFlags!DeSiryulize) {}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isNullable!T) {
	if (node.hasTypeConvertible!(typeof(null))) {
		result.nullify();
	} else {
		typeof(result.get) tmp;
		deserialize(node, tmp, flags);
		result = tmp;
	}
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (is(T == struct) && !isTimeType!T && !is(T == Duration) && !isSumType!T && !isNullable!T && !hasDeserializationMethod!T && !hasDeserializationTemplate!T) {
	import std.exception : enforce;
	import std.meta : AliasSeq;
	import std.traits : arity, FieldNameTuple, ForeachType, hasIndirections, isAssociativeArray, isFloatingPoint, isIntegral, isPointer, isSomeChar, isSomeString, isStaticArray, OriginalType, Parameters, PointerTarget, TemplateArgsOf, ValueType;
	expect(node, Classification.mapping);
	foreach (member; FieldNameTuple!T) {
		alias field = AliasSeq!(__traits(getMember, T, member));
		static if (!mustSkip!field && __traits(getProtection, field) == "public") {
			//debug string newPath = path~"."~member;
			//else string newPath = path;
			const optional = isOptional!field || !!(flags & DeSiryulize.optionalByDefault);
			enum memberName = getMemberName!field;
			const valueIsAbsent = (memberName !in node) || (node[memberName].hasTypeConvertible!(typeof(null)));
			if (optional && !isRequired!field && !hasConvertFromFunc!(T, field) && valueIsAbsent) {
				continue;
			}
			static if (!hasIndirections!(typeof(field)) && !hasConvertFromFunc!(T, field)) {
				enforce(memberName in node, new DeserializeException("Missing non-@Optional "~memberName~" in node", node.getMark));
			}
			static if (hasConvertFromFunc!(T, field)) {
				alias fromFunc = getConvertFromFunc!(T, field);
				Parameters!(fromFunc)[0] param;
				if (!valueIsAbsent) {
					deserialize(node[memberName], param, flags);
				}
				__traits(getMember, result, member) = fromFunc(param);
			} else {
				deserialize(node[memberName], __traits(getMember, result, member), flags);
			}
		}
	}
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isSumType!T) {
	static foreach (Type; T.Types) {
		try {
			Type tmp;
			deserialize(node, tmp, flags);
			trustedAssign(result, tmp); //result has not been initialized yet, so this is safe
			return;
		} catch (DeserializeException e) {}
	}
	throw new DeserializeException("No matching types", node.getMark);
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (is(T == enum)) {
	import std.traits : OriginalType;
	if (node.hasTypeConvertible!string) {
		result = node.getType!string.tryConvert!T(node.getMark);
	} else {
		OriginalType!T tmp;
		deserialize(node, tmp, flags);
		result = tmp.tryConvert!T(node.getMark);
	}
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isTimeType!T) {
	import std.datetime : SysTime;
	if (node.hasTypeConvertible!SysTime) {
		result = cast(T)node.getType!SysTime();
	} else if (node.hasTypeConvertible!string) {
		result = T.fromISOExtString(node.getType!string);
	} else {
		throw new DeserializeException("Could not convert node to time type", node.getMark);
	}
}
void deserialize(NodeType)(NodeType node, out Duration result, BitFlags!DeSiryulize flags) {
	if (node.hasTypeConvertible!Duration) {
		result = node.getType!Duration();
	} else if (node.hasTypeConvertible!string) {
		result = node.getType!string.fromISODurationString;
	} else {
		throw new DeserializeException("Could not convert node to duration type", node.getMark);
	}
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isFloatingPoint!T) {
	if (node.hasTypeConvertible!real) {
		result = node.getType!real();
	} else if (node.hasTypeConvertible!long) {
		result = node.getType!long.tryConvert!T(node.getMark);
	} else if (node.hasTypeConvertible!ulong) {
		result = node.getType!ulong.tryConvert!T(node.getMark);
	} else {
		result = node.getType!string.tryConvert!T(node.getMark);
	}
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isOutputRange!(T, ElementType!T) && !isSomeString!T && !isNullable!T) {
	import std.conv : text;
	if (node.hasClass(Classification.sequence)) {
		result = new T(node.length);
		foreach (idx, ref element; result) {
			//debug string newPath = path ~ "["~idx.text~"]";
			//else string newPath = path;
			deserialize(node[idx], element, flags);
		}
	} else {
		throw new DeserializeException("Could not parse node as array", node.getMark);
	}
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isStaticArray!T) {
	import std.conv : text;
	import std.traits : ForeachType, isSomeChar;
	static if (isSomeChar!(ElementType!T)) {
		import std.range : enumerate;
		import std.utf : byCodeUnit;
		expect!(const(char)[])(node);
		string str;
		deserialize(node, str, flags);
		foreach (i, ref chr; result) {
			chr = str[i];
		}
	} else {
		import std.exception : enforce;
		expect(node, Classification.sequence);
		enforce(node.length == T.length, new DeserializeException("Static array length mismatch", node.getMark));
		foreach (idx, ref element; result) {
			//debug string newPath = path ~ "["~i.text~"]";
			//else string newPath = path;
			deserialize(node[idx], element, flags);
		}
	}
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isSomeChar!T) {
	import std.array : front;
	if (!node.hasTypeConvertible!(typeof(null))) {
		expect(node, Classification.scalar);
		result = cast(T)node.getType!string.front;
	}
}
void deserialize(V, K, NodeType)(NodeType node, out V[K] result, BitFlags!DeSiryulize flags) {
	expect(node, Classification.mapping);
	foreach (string k, NodeType v; node) {
		V val;
		deserialize(v, val, flags);
		result[k] = val;
	}
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isAggregateType!T && hasDeserializationMethod!T) {
	Parameters!(deserializationMethod!T) tmp;
	deserialize(node, tmp, flags);
	result = deserializationMethod!T(tmp);
}
void deserialize(T, NodeType)(NodeType node, out T result, BitFlags!DeSiryulize flags) if (isAggregateType!T && hasDeserializationTemplate!T) {
	Parameters!(T.fromSiryulType!()) tmp;
	deserialize(node, tmp, flags);
	result = deserializationTemplate!T(tmp);
}
private T tryConvert(T, V)(V value, Nullable!Mark mark) {
	import std.conv : ConvException, to;
	try {
		return value.to!T;
	} catch (ConvException) {
		throw new DeserializeException(format!("Cannot convert value '%s' to type "~T.stringof)(value), mark);
	}
}
private void expect(NodeType)(NodeType node, Classification class_, string file = __FILE__, ulong line = __LINE__) {
	import std.algorithm : among;
	import std.exception : enforce;
	enforce(node.hasClass(class_), new DeserializeException(format!"Expected %s"(class_), node.getMark, file, line));
}
private void expect(T, NodeType)(NodeType node, string file = __FILE__, ulong line = __LINE__) {
	import std.algorithm : among;
	import std.exception : enforce;
	enforce(node.hasTypeConvertible!T, new DeserializeException(format!"Expected %s"(T.stringof), node.getMark, file, line));
}

Node serialize(Node, T)(ref const T value, BitFlags!Siryulize flags) if (is(T == struct) && !isSumType!T && !isNullable!T && !isTimeType!T && !hasSerializationMethod!T && !hasSerializationTemplate!T && !(is(T: const(Duration)))) {
	import std.meta : AliasSeq;
	import std.traits : FieldNameTuple;
	EmptyMapping!Node output;
	foreach (member; FieldNameTuple!T) {
		alias field = AliasSeq!(__traits(getMember, T, member));
		static if (!mustSkip!field && (__traits(getProtection, field) == "public")) {
			if (__traits(getMember, value, member).isSkippableValue(flags)) {
				continue;
			}
			enum memberName = getMemberName!field;
			static if (hasConvertToFunc!(T, field)) {
				output[memberName] = serialize!Node(getConvertToFunc!(T, field)(__traits(getMember, value, member)), flags);
			} else {
				output[memberName] = serialize!Node(__traits(getMember, value, member), flags);
			}
		}
	}
	return output.toNode!Node;
}
Node serialize(Node, T)(ref const T value, BitFlags!Siryulize flags) if (isNullable!T) {
	if (value.isNull) {
		return serialize!Node(null, flags);
	} else {
		return serialize!Node(value.get, flags);
	}
}
Node serialize(Node, T)(ref const T value, BitFlags!Siryulize flags) if (isSumType!T) {
	import std.sumtype : match;
	return value.match!(v => serialize!Node(v, flags));
}
Node serialize(Node)(const typeof(null) value, BitFlags!Siryulize flags) {
	return Node();
}
Node serialize(Node, T)(ref const T value, BitFlags!Siryulize flags) if (shouldStringify!value || is(T == enum)) {
	import std.conv : text;
	return Node(value.text);
}
Node serialize(Node, T)(ref const T value, BitFlags!Siryulize flags) if (isPointer!T) {
	return serialize!Node(*value, flags);
}
Node serialize(Node, T)(ref const T value, BitFlags!Siryulize flags) if (isTimeType!T) {
	return Node(value.toISOExtString());
}
Node serialize(Node)(ref const Duration value, BitFlags!Siryulize flags) {
	import std.conv : text;
	return Node(value.asISO8601String().text);
}
Node serialize(Node, T)(ref const T value, BitFlags!Siryulize flags) if (isSomeChar!T) {
	import std.utf : toUTF8;
	return Node([value].toUTF8);
}
Node serialize(Node, T)(ref const T value, BitFlags!Siryulize flags) if ((isSomeString!T || isStaticString!T) && !is(T : string)) {
	import std.utf : toUTF8;
	return Node(value[].toUTF8);
}
Node serialize(Node, T)(const T value, BitFlags!Siryulize flags) if (Node.canStoreUnchanged!(Unqual!T) && !is(T == enum)) {
	return Node(value);
}
Node serialize(Node, T)(ref T values, BitFlags!Siryulize flags) if (isSimpleList!T && !isNullable!T && !isStaticString!T && !isNullable!T) {
	Node[] output;
	foreach (value; values) {
		output ~= serialize!Node(value, flags);
	}
	return Node(output);
}
Node serialize(Node, T)(ref T values, BitFlags!Siryulize flags) if (isAssociativeArray!T) {
	EmptyMapping!Node output;
	foreach (key, value; values) {
		output[key] = serialize!Node(value, flags);
	}
	return output.toNode!Node;
}
Node serialize(Node, T)(ref T value, BitFlags!Siryulize flags) if (isAggregateType!T && hasSerializationMethod!T) {
	return serialize!Node(__traits(getMember, value, __traits(identifier, serializationMethod!T)), flags);
}
Node serialize(Node, T)(ref T value, BitFlags!Siryulize flags) if (isAggregateType!T && hasSerializationTemplate!T) {
	const v = __traits(getMember, value, __traits(identifier, serializationTemplate!T));
	return serialize!Node(v, flags);
}

private template EmptyMapping(Node) {
	static if (Node.hasStringIndexing) {
		alias EmptyMapping = Node.emptyMapping;
	} else {
		alias EmptyMapping = Node[string];
	}
}

private Node toNode(Node)(EmptyMapping!Node input) {
	static if (Node.hasStringIndexing) {
		return input;
	} else {
		return Node(input);
	}
}

/++
 + Determines whether or not the given type is a valid (de)serializer
 +/
template isSiryulizer(T) {
	debug enum isSiryulizer = true;
	else enum isSiryulizer = __traits(compiles, () {
		uint val = T.parseInput!(uint, DeSiryulize.none)("", "");
		string str = T.asString!(Siryulize.none)(3);
	});
}
