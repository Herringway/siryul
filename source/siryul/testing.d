module siryul.testing;

import siryul.common;
import siryul.siryul;

import std.conv;
import std.datetime;
import std.exception;
import std.range;
import std.traits;
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
}
private auto sampleTime = SysTime(DateTime(2015, 10, 7, 15, 4, 46), UTC());

private alias toFormattedString = toString;

void runTests(S)() if (isSiryulizer!S) {
	import std.algorithm : filter;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.sumtype : SumType;
	import std.format : format;
	static void runTest2(T, U, size_t line = __LINE__)(auto ref T input, auto ref U expected) {
		import std.stdio : writeln;
		enum testDoc = format!"%s test (line %s)"(S.stringof, line);
		void writeValue(V)(string str, V value) {
			static if (isPointer!V && isCopyable!(typeof(*value))) {
				writeln(str, "\n ", *value);
			} else {
				writeln(str, "\n ", value);
			}
		}
		debug(verbosetesting) {
			writeln("-----");
			writeValue("Input:", input);
		}
		auto gotString = input.toFormattedString!S;
		debug(verbosetesting) writeln("Serialized:\n", gotString);
		auto gotValue = gotString.fromString!(U, S)(testDoc);
		static if (!isSumType!U) {
			auto gotValueOmit = input.toFormattedString!(S, Siryulize.omitInits).fromString!(U, S, DeSiryulize.optionalByDefault)(testDoc);
		}
		debug(verbosetesting) writeValue("Output:", gotValue);
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
	static void runTest2Fail(T, U, size_t linec = __LINE__)(auto ref U value, string file = __FILE__, size_t line = __LINE__) {
		enum testDoc = format!"%s test (line %s)"(S.stringof, linec);
		assertThrown(value.toFormattedString!S.fromString!(T, S)(testDoc), "Expected "~S.stringof~" to throw for "~value.text~" to "~T.stringof, file, line);
	}
	static void runTest(T, size_t line = __LINE__)(auto ref T expected) {
		runTest2!(T, T, line)(expected, expected);
	}
	static void runTestFail(T, size_t line = __LINE__)(auto ref T expected) {
		runTest2Fail!(T, T, line)(expected);
	}
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
	runTest(0);
	runTest(-100);
	runTest(ulong.max);
	runTest(long.max);
	//runTest(long.min);

	auto testInstance = Test("beep", 2, 4, ["derp", "blorp"], ["one":1, "two":3], false, ["Test2":Test2("test")], 4.5, 'g');

	runTest(testInstance);
	runTest(testInstance.d);
	runTest(testInstance.g);
	struct StringCharTest {
		char a;
		wchar b;
		dchar c;
		string d;
		wstring e;
		dstring f;
	}
	runTest(StringCharTest('a', '‽', '\U00010300', "↑↑↓↓←→←→ⒷⒶ", "↑↑↓↓←→←→ⒷⒶ", "↑↑↓↓←→←→ⒷⒶ"));

	int[4] staticArray = [0, 1, 2, 3];
	runTest(staticArray);

	runTest(Nullable!int(4));
	runTest2(Nullable!int(), null);
	runTest(TimeOfDay(1, 1, 1));
	runTest(Date(2000, 1, 1));
	runTest(DateTime(2000, 1, 1, 1, 1, 1));
	runTest(SysTime(DateTime(2000, 1, 1), UTC()));

	runTest2([0,1,2,3,4].filter!((a) => a%2 != 1), [0, 2, 4]);


	runTest2(3, TestEnum.wont);

	runTest2(TestEnum.something, TestEnum.something);
	runTest2(TestEnum.something, "something");

	runTest(TestNull());
	auto nullableTest2 = TestNull(1, "a");
	nullableTest2.aNullable = 3;
	nullableTest2.anotherNullable = 4;
	nullableTest2.noDate = SysTime(DateTime(2000, 1, 1), UTC());
	nullableTest2.noEnum = TestEnum.ya;
	runTest(nullableTest2);

	struct SiryulizeAsTest {
		@SiryulizeAs("word") string something;
	}
	struct SiryulizeAsTest2 {
		string word;
	}
	runTest(SiryulizeAsTest("a"));
	runTest2(SiryulizeAsTest("a"), SiryulizeAsTest2("a"));

	struct TestNull2 {
		@Optional @SiryulizeAs("v") Nullable!bool value;
	}
	auto testval = TestNull2();
	testval.value = true;
	runTest(testval);
	testval.value = false;
	runTest(testval);
	assert(TestNull2().toFormattedString!S.fromString!(TestNull2, S)(S.stringof ~ " null test").value.isNull);
	assert(Empty().toFormattedString!S.fromString!(TestNull2, S)(S.stringof ~ " null test 2").value.isNull);

	runTest2Fail!bool("b");
	runTest2(Nullable!string.init, wstring.init);
	runTest2(Nullable!char.init, wchar.init);

	//Autoconversion tests
	//string <-> int
	runTest2("3", 3);
	runTest2(3, "3");
	//string <-> float
	runTest2("3.0", 3.0);
	runTest2(3.0, "3");

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
	runTest2(TimeTest(sampleTime), TimeTestString("this has nothing to do with time."));
	runTest2(TimeTestString("this has nothing to do with time."), TimeTest(sampleTime));

	union Unhandleable { //Unions are too dangerous to handle automatically
		int a;
		char[4] b;
	}
	assert(!__traits(compiles, runTest(Unhandleable())));

	import std.typecons : Flag;
	runTest2(true, Flag!"Yep".yes);

	import std.utf : toUTF16, toUTF32;
	enum testStr = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
	enum testStrD = testStr.toUTF16;
	enum testStrW = testStr.toUTF32;
	char[32] testChr = testStr;
	runTest2(testChr, testStr);
	runTest2(testStr, testChr);
	dchar[32] testChr2 = testStr;
	runTest2(testChr2, testStrD);
	runTest2(testStrD, testChr2);
	wchar[32] testChr3 = testStr;
	runTest2(testChr3, testStrW);
	runTest2(testStrW, testChr3);

	//int -> float[] array doesn't even make sense, should be rejected
	runTest2Fail!(float[])(3);
	//Precision loss should be rejected by default
	runTest2Fail!int(3.5);
	//bool -> string???
	runTest2Fail!string(true);
	//string -> bool???
	runTest2Fail!bool("nah");

	struct PrivateTest {
		private uint x;
		bool y;
	}

	runTest(PrivateTest(0,true));

	struct StructPtr {
		ubyte[100] bytes;
	}
	StructPtr* structPtr = new StructPtr;
	runTest(structPtr);
	structPtr.bytes[0] = 1;
	runTest(structPtr);

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
	runTest2(CustomSerializer(true), false);
	runTest2(false, CustomSerializer(true));

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
	runTest2(CustomSerializer2(true), SimpleWrapper(false));
	runTest2(SimpleWrapper(false), CustomSerializer2(true));

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
	runTest2(SerializableUnion(true), false);
	runTest2(false, SerializableUnion(true));

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
	runTest2(new SerializableClass(true), false);
	runTest2(false, new SerializableClass(true));

	static struct RequiredTest {
		@Required bool x;
		int y;
	}
	static struct RequiredTest2 {
		int y;
	}
	runTest(RequiredTest());
	assert(Empty().toString!S.fromString!(RequiredTest2, S, DeSiryulize.optionalByDefault)(S.stringof ~ " required test").y == 0, "Required test failed for "~S.stringof);
	assertThrown(RequiredTest2(4).toString!S.fromString!(RequiredTest, S, DeSiryulize.optionalByDefault)(S.stringof ~ " required test 2"), "Required test failed for "~S.stringof);
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
	runTest(a);
	runTest(b);
	runTest(c);
	runTest2(SumTestA(20, "hi"), a);
	runTest2(SumTestB(true, 123.0), b);
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
	runTest(SumTest2("hello"));
	runTest(SumTest2(2.0));
	runTest2(SumTest2(2.0), SumTest2Alt(2.0));
	static struct LargeStruct {
		@disable this(this);
		uint[0x10000] largeData;
	}
	auto largeVal = new LargeStruct;
	runTest(largeVal);

	static struct NewHelper {
		bool val;
		int toSiryulType()() @safe {
			return val;
		}
		static NewHelper fromSiryulType()(int val) @safe {
			return NewHelper(!!val);
		}
	}
	runTest2(NewHelper(true), 1);
	runTest2(NewHelper(false), 0);
	runTest2(1, NewHelper(true));
	runTest2(0, NewHelper(false));
	const systime = sampleTime;
	runTest2(systime, sampleTime);
	runTest(1.hours);
	static struct SkipTest {
		@Skip int val;
		@Skip int defaultValue = 75;
		@Skip SkipTest* unhandled;
	}
	runTest2(SkipTest(42, 13), SkipTest());
	runTest2(SkipTest(42, 13), Empty());
	runTest2Fail!Test2(Empty());
	static struct StructWithIndirections {
		char[] aString;
		int[] someNumbers;
	}
	const(StructWithIndirections)[] constIndirectionTest = [StructWithIndirections(['a', 'b', 'c'], [1,2,3])];
	runTest(constIndirectionTest);
	immutable(StructWithIndirections)[] constIndirectionTest2 = [StructWithIndirections(['a', 'b', 'c'], [1,2,3])];
	runTest(constIndirectionTest2);

	runTest([TestEnum.something : 5]);

	assert(collectException!DeserializeException(4.toString!S.fromString!(Test2, S)("keepfilename.txt")).mark.name == "keepfilename.txt");
	static struct LocationTest {
		int foo;
		static uint marks;
		void siryulMark()(scope const Mark mark) {
			marks++;
		}
	}
	const locstr = [LocationTest(), LocationTest()].toString!S;
	const unused = locstr.fromString!(LocationTest[], S)(S.stringof ~ " location test");
	assert(LocationTest.marks == 2);
}
