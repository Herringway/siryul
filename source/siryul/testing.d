module siryul.testing;

import siryul.common;
import siryul.siryul;

import std.conv;
import std.datetime;
import std.exception;
import std.range;
import std.typecons;

private struct Empty {}
private struct Test2 {
	string inner;
}
private enum TestEnum : uint { test = 0, something = 1, wont = 3, ya = 2 }
private struct TestNull {
	import std.typecons : Nullable;
	uint notNull;
	string aString;
	uint[] emptyArray;
	Nullable!uint aNullable;
	Nullable!(uint, 0) anotherNullable;
	Nullable!SysTime noDate;
	Nullable!TestEnum noEnum;
	void toString(W)(ref W sink) @trusted const { //@trusted because of a Nullable!(T, typeof(T)).toString. also it's just for test purposes and doesn't matter
		import std.format : formattedWrite;
		formattedWrite!"TestNull(%s, %s, %s, %s, %s, %s, %s)"(sink, notNull, aString, emptyArray, aNullable, anotherNullable, noDate, noEnum);
	}
	void foo() {
		NullSink s;
		toString(s);
	}
}
private auto sampleTime = SysTime(DateTime(2015, 10, 7, 15, 4, 46), UTC());

private alias toFormattedString = toString;

private void runTest2(S, T, U)(auto ref T input, auto ref U expected) {
	import std.format : format;
	import std.traits : isPointer;
	auto gotValue = input.toFormattedString!S.fromString!(U, S);
	static if (!isSumType!U) {
		auto gotValueOmit = input.toFormattedString!(S, Siryulize.omitInits).fromString!(U, S, DeSiryulize.optionalByDefault);
	}
	debug(verbosetesting) {
		import std.stdio : writeln;
		writeln("-----");
		static if (isPointer!T && isCopyable!(typeof(*input))) {
			writeln("Input:\n ", *input);
		} else {
			writeln("Input:\n ", input);
		}
		writeln("Serialized:\n", input.toFormattedString!S);
		static if (isPointer!T && isCopyable!(typeof(*input))) {
			writeln("Output:\n ", *gotValue);
		} else {
			writeln("Output:\n ", gotValue);
		}
	}
	static if (isPointer!T && isPointer!U) {
		assert(*gotValue == *expected, format("%s->%s->%s failed", T.stringof, S.stringof, U.stringof));
		static if (!isSumType!U) {
			assert(*gotValueOmit == *expected, format("%s->%s->%s failed", T.stringof, S.stringof, U.stringof));
		}
	} else {
		auto vals = format("expected %s, got %s", expected, gotValue);
		assert(gotValue == expected, format("%s->%s->%s failed, %s", T.stringof, S.stringof, U.stringof, vals));
		static if (!isSumType!U) {
			auto valsOmit = format("expected %s, got %s", expected, gotValueOmit);
			assert(gotValueOmit == expected, format("%s->%s->%s failed, %s", T.stringof, S.stringof, U.stringof, valsOmit));
		}
	}
}
private void runTest2Fail(S, T, U)(auto ref U value, string file = __FILE__, size_t line = __LINE__) {
	assertThrown(value.toFormattedString!S.fromString!(T, S), "Expected "~S.stringof~" to throw for "~value.text~" to "~T.stringof, file, line);
}
private void runTest(S, T)(auto ref T expected) {
	runTest2!S(expected, expected);
}
private void runTestFail(S, T)(auto ref T expected) {
	runTest2Fail!(S, T)(expected);
}
void runTests(S)() if (isSiryulizer!S) {
	import std.algorithm : filter;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.sumtype : SumType;
	struct Test {
		string a;
		uint b;
		ubyte c;
		string[] d;
		short[string] e;
		@Optional bool f = false;
		Test2[string] g;
		double h;
		char i;
	}
	runTest!S(0);
	runTest!S(-100);
	runTest!S(ulong.max);
	runTest!S(long.max);
	//runTest!S(long.min);

	auto testInstance = Test("beep", 2, 4, ["derp", "blorp"], ["one":1, "two":3], false, ["Test2":Test2("test")], 4.5, 'g');

	runTest!S(testInstance);
	runTest!S(testInstance.d);
	runTest!S(testInstance.g);
	struct StringCharTest {
		char a;
		wchar b;
		dchar c;
		string d;
		wstring e;
		dstring f;
	}
	runTest!S(StringCharTest('a', '‽', '\U00010300', "↑↑↓↓←→←→ⒷⒶ", "↑↑↓↓←→←→ⒷⒶ", "↑↑↓↓←→←→ⒷⒶ"));

	int[4] staticArray = [0, 1, 2, 3];
	runTest!S(staticArray);

	runTest!S(Nullable!int(4));
	runTest2!S(Nullable!int(), null);
	runTest!S(TimeOfDay(1, 1, 1));
	runTest!S(Date(2000, 1, 1));
	runTest!S(DateTime(2000, 1, 1, 1, 1, 1));
	runTest!S(SysTime(DateTime(2000, 1, 1), UTC()));

	runTest2!S([0,1,2,3,4].filter!((a) => a%2 != 1), [0, 2, 4]);


	runTest2!S(3, TestEnum.wont);

	runTest2!S(TestEnum.something, TestEnum.something);
	runTest2!S(TestEnum.something, "something");

	auto result = TestNull().toFormattedString!S.fromString!(TestNull, S);

	assert(result.notNull == 0);
	assert(result.aString == "");
	assert(result.emptyArray == []);
	assert(result.aNullable.isNull());
	assert(result.anotherNullable.isNull());
	assert(result.noDate.isNull());
	assert(result.noEnum.isNull());
	auto nullableTest2 = TestNull(1, "a");
	nullableTest2.aNullable = 3;
	nullableTest2.anotherNullable = 4;
	nullableTest2.noDate = SysTime(DateTime(2000, 1, 1), UTC());
	nullableTest2.noEnum = TestEnum.ya;
	runTest!S(nullableTest2);

	struct SiryulizeAsTest {
		@SiryulizeAs("word") string something;
	}
	struct SiryulizeAsTest2 {
		string word;
	}
	runTest!S(SiryulizeAsTest("a"));
	runTest2!S(SiryulizeAsTest("a"), SiryulizeAsTest2("a"));

	struct TestNull2 {
		@Optional @SiryulizeAs("v") Nullable!bool value;
	}
	auto testval = TestNull2();
	testval.value = true;
	runTest!S(testval);
	testval.value = false;
	runTest!S(testval);
	assert(TestNull2().toFormattedString!S.fromString!(TestNull2, S).value.isNull);
	assert(Empty().toFormattedString!S.fromString!(TestNull2, S).value.isNull);

	runTest2Fail!(S, bool)("b");
	runTest2!S(Nullable!string.init, wstring.init);
	runTest2!S(Nullable!char.init, wchar.init);

	//Autoconversion tests
	//string <-> int
	runTest2!S("3", 3);
	runTest2!S(3, "3");
	//string <-> float
	runTest2!S("3.0", 3.0);
	runTest2!S(3.0, "3");

	//Custom parser
	struct TimeTest {
		@CustomParser("fromJunk", "toJunk") SysTime time;
		static SysTime fromJunk(string) @safe {
			return sampleTime;
		}
		static string toJunk(SysTime) @safe {
			return "this has nothing to do with time.";
		}
	}
	struct TimeTestString {
		string time;
	}
	runTest2!S(TimeTest(sampleTime), TimeTestString("this has nothing to do with time."));
	runTest2!S(TimeTestString("this has nothing to do with time."), TimeTest(sampleTime));

	union Unhandleable { //Unions are too dangerous to handle automatically
		int a;
		char[4] b;
	}
	assert(!__traits(compiles, runTest!S(Unhandleable())));

	import std.typecons : Flag;
	runTest2!S(true, Flag!"Yep".yes);

	import std.utf : toUTF16, toUTF32;
	enum testStr = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
	enum testStrD = testStr.toUTF16;
	enum testStrW = testStr.toUTF32;
	char[32] testChr = testStr;
	runTest2!S(testChr, testStr);
	runTest2!S(testStr, testChr);
	dchar[32] testChr2 = testStr;
	runTest2!S(testChr2, testStrD);
	runTest2!S(testStrD, testChr2);
	wchar[32] testChr3 = testStr;
	runTest2!S(testChr3, testStrW);
	runTest2!S(testStrW, testChr3);

	//int -> float[] array doesn't even make sense, should be rejected
	runTest2Fail!(S, float[])(3);
	//Precision loss should be rejected by default
	runTest2Fail!(S, int)(3.5);
	//bool -> string???
	runTest2Fail!(S, string)(true);
	//string -> bool???
	runTest2Fail!(S, bool)("nah");

	struct PrivateTest {
		private uint x;
		bool y;
	}

	runTest!S(PrivateTest(0,true));

	struct StructPtr {
		ubyte[100] bytes;
	}
	StructPtr* structPtr = new StructPtr;
	runTest!S(structPtr);
	structPtr.bytes[0] = 1;
	runTest!S(structPtr);

	static struct CustomSerializer {
		bool x;
		@SerializationMethod
		bool serialize() const @safe {
			return !x;
		}
		@DeserializationMethod
		static auto deserialize(bool input) @safe {
			return CustomSerializer(!input);
		}
	}
	runTest2!S(CustomSerializer(true), false);
	runTest2!S(false, CustomSerializer(true));

	static struct CustomSerializer2 {
		bool x;
		static auto toSiryulHelper(string T)(bool v) if(T == "x") {
			return !v;
		}
		static auto fromSiryulHelper(string T)(bool v) if (T == "x") {
			return !v;
		}
	}
	static struct SimpleWrapper {
		bool x;
	}
	runTest2!S(CustomSerializer2(true), SimpleWrapper(false));
	runTest2!S(SimpleWrapper(false), CustomSerializer2(true));

	static union SerializableUnion {
		bool x;
		int _ignored;
		@SerializationMethod
		bool serialize() const @safe {
			return !x;
		}
		@DeserializationMethod
		static auto deserialize(bool input) @safe {
			return SerializableUnion(!input);
		}
	}
	runTest2!S(SerializableUnion(true), false);
	runTest2!S(false, SerializableUnion(true));

	static class SerializableClass {
		bool x;
		this(bool input) @safe {
			x = input;
		}
		@SerializationMethod
		bool serialize() const @safe {
			return !x;
		}
		@DeserializationMethod
		static auto deserialize(bool input) @safe {
			return new SerializableClass(!input);
		}
		bool opEquals(const SerializableClass rhs) {
			return x == rhs.x;
		}
		override string toString() @safe{
			import std.format : format;
			return format!"SerializableClass(%s)"(x);
		}
		alias opEquals = Object.opEquals;
		bool opEquals(SerializableClass c) @safe { return c.x == x; }
	}
	runTest2!S(new SerializableClass(true), false);
	runTest2!S(false, new SerializableClass(true));

	static struct RequiredTest {
		@Required bool x;
		int y;
	}
	static struct RequiredTest2 {
		int y;
	}
	assert(Empty().toString!S.fromString!(RequiredTest2, S, DeSiryulize.optionalByDefault).y == 0, "Required test failed for "~S.stringof);
	assertThrown(RequiredTest2(4).toString!S.fromString!(RequiredTest, S, DeSiryulize.optionalByDefault), "Required test failed for "~S.stringof);
	struct SumTestA {
		int a;
		string b;
	}
	struct SumTestB {
		bool c;
		float d;
	}

	alias Multiple = SumType!(SumTestA, SumTestB);
	Multiple a = SumTestA(20, "hi");
	Multiple b = SumTestB(true, 123.0);
	Multiple c;
	runTest!S(a);
	runTest!S(b);
	runTest!S(c);
	runTest2!S(SumTestA(20, "hi"), a);
	runTest2!S(SumTestB(true, 123.0), b);
	static struct SumTest2 {
		SumType!(double, string) value;
		this(string str) {
			value = str;
		}
		this(double val) {
			value = val;
		}
	}
	static struct SumTest2Alt {
		double value;
	}
	runTest!S(SumTest2("hello"));
	runTest!S(SumTest2(2.0));
	runTest2!S(SumTest2(2.0), SumTest2Alt(2.0));
	static struct LargeStruct {
		@disable this(this);
		uint[0x10000] largeData;
	}
	auto largeVal = new LargeStruct;
	runTest!S(largeVal);

	static struct NewHelper {
		bool val;
		int toSiryulType()() @safe {
			return val;
		}
		static NewHelper fromSiryulType()(int val) @safe {
			return NewHelper(!!val);
		}
	}
	runTest2!S(NewHelper(true), 1);
	runTest2!S(NewHelper(false), 0);
	runTest2!S(1, NewHelper(true));
	runTest2!S(0, NewHelper(false));
	const systime = sampleTime;
	runTest2!S(systime, sampleTime);
	runTest!S(1.hours);
	static struct SkipTest {
		@Skip int val;
		@Skip int defaultValue = 75;
		@Skip SkipTest* unhandled;
	}
	static struct Nothing {}
	runTest2!S(SkipTest(42, 13), SkipTest());
	runTest2!S(SkipTest(42, 13), Nothing());
}
