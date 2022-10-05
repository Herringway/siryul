/++
 + Macros:
 + 	SUPPORTEDFORMATS = YAML, JSON, AutoDetect
 + 	SUPPORTEDAUTOFORMATS = .yml, .yaml for YAML and .json for JSON
 + 	SUPPORTEDSTRUCTURES = structs, built-in data types, Nullable, and std.datetime structs
 +/
module siryul.siryul;
import siryul;
import std.datetime;
import std.meta;
import std.range;
import std.traits;
import std.typecons;
alias siryulizers = AliasSeq!(JSON, YAML);

/++
 + Deserializes data from a file.
 +
 + Files are assumed to be UTF-8 encoded. If no format (or AutoDetect) is
 + specified, an attempt at autodetection is made.
 +
 + Supports $(SUPPORTEDSTRUCTURES).
 +
 + Params:
 + T = Type stored in the file
 + Format = Serialization format ($(SUPPORTEDFORMATS))
 + path = Absolute or relative path to the file
 +
 + Returns: Data from the file in the format specified
 +/
T fromFile(T, Format = AutoDetect, DeSiryulize flags = DeSiryulize.none)(string path) if (isSiryulizer!Format || is(Format == AutoDetect)) {
	static if (is(Format == AutoDetect)) {
		import std.path : extension;
		switch(path.extension) {
			foreach (siryulizer; siryulizers) {
				foreach (type; siryulizer.extensions) {
					case type:
						return fromFile!(T, siryulizer, flags)(path);
				}
			}
			default:
				throw new SerializeException("Unknown extension");
		}
	} else { //Not autodetecting
		import std.algorithm : joiner;
		import std.file : read;
		auto lines = () @trusted { return cast(string)read(path); }();
		return Format.parseInput!(T, flags)(lines, path);
	}
}
///
@system unittest {
	import std.exception : assertThrown;
	import std.file : exists, remove;
	import std.stdio : File;
	struct TestStruct {
		string a;
	}
	//Write some example files...
	File("int.yml", "w").write("---\n9");
	File("string.json", "w").write(`"test"`);
	File("struct.yml", "w").write("---\na: b");
	scope(exit) { //Clean up when done
		if ("int.yml".exists) {
			remove("int.yml");
		}
		if ("string.json".exists) {
			remove("string.json");
		}
		if ("struct.yml".exists) {
			remove("struct.yml");
		}
	}
	//Read examples from respective files
	assert(fromFile!(uint, YAML)("int.yml") == 9);
	assert(fromFile!(string, JSON)("string.json") == "test");
	assert(fromFile!(TestStruct, YAML)("struct.yml") == TestStruct("b"));
	//Read examples from respective files using automatic format detection
	assert(fromFile!uint("int.yml") == 9);
	assert(fromFile!string("string.json") == "test");
	assert(fromFile!TestStruct("struct.yml") == TestStruct("b"));

	assertThrown("file.obviouslybadextension".fromFile!uint);
}
/++
 + Deserializes data from a string.
 +
 + String is assumed to be UTF-8 encoded.
 +
 + Params:
 + T = Type of the data to be deserialized
 + Format = Serialization format ($(SUPPORTEDFORMATS))
 + str = A string containing serialized data in the specified format
 +
 + Supports $(SUPPORTEDSTRUCTURES).
 +
 + Returns: Data contained in the string
 +/
T fromString(T, Format, DeSiryulize flags = DeSiryulize.none,U)(U str) if (isSiryulizer!Format && isInputRange!U) {
	return Format.parseInput!(T, flags)(str, "<string>");
}
///
unittest {
	struct TestStruct {
		string a;
	}
	//Compare a struct serialized into two different formats
	const aStruct = fromString!(TestStruct, JSON)(`{"a": "b"}`);
	const anotherStruct = fromString!(TestStruct, YAML)("---\na: b");
	assert(aStruct == anotherStruct);
}
/++
 + Serializes data to a string.
 +
 + UTF-8 encoded by default.
 +
 + Supports $(SUPPORTEDSTRUCTURES).
 +
 + Params:
 + Format = Serialization format ($(SUPPORTEDFORMATS))
 + data = The data to be serialized
 +
 + Returns: A string in the specified format representing the user's data, UTF-8 encoded
 +/
@property auto toString(Format, Siryulize flags = Siryulize.none, T)(T data) if (isSiryulizer!Format) {
	return Format.asString!flags(data);
}
///
unittest {
	//3 as a JSON object
	assert(3.toString!JSON == `3`);
	//"str" as a JSON object
	assert("str".toString!JSON == `"str"`);
}
///For cases where toString is already defined
alias toFormattedString = toString;
/++
 + Serializes data to a file.
 +
 + Any format supported by this library may be specified. If no format is
 + specified, it will be chosen from the file extension if possible.
 +
 + Supports $(SUPPORTEDSTRUCTURES).
 +
 + This function will NOT create directories as necessary.
 +
 + Params:
 + Format = Serialization format ($(SUPPORTEDFORMATS))
 + data = The data to be serialized
 + path = The path for the file to be written
 +/
@property void toFile(Format = AutoDetect, Siryulize flags = Siryulize.none, T)(T data, string path) if (isSiryulizer!Format || is(Format == AutoDetect)) {
	static if (is(Format == AutoDetect)) {
		import std.path : extension;
		switch(path.extension) {
			foreach (siryulizer; siryulizers) {
				foreach (type; siryulizer.extensions) {
					case type:
						return data.toFile!(siryulizer, flags)(path);
				}
			}
			default:
				throw new DeserializeException("Unknown extension");
		}
	} else { //Not autodetecting
		import std.algorithm : copy;
		import std.stdio : File;
		data.toFormattedString!(Format, flags).copy(File(path, "w").lockingTextWriter());
	}
}
///
unittest {
	import std.exception : assertThrown;
	import std.file : exists, remove;
	struct TestStruct {
		string a;
	}
	scope(exit) { //Clean up when done
		if ("int.yml".exists) {
			remove("int.yml");
		}
		if ("string.json".exists) {
			remove("string.json");
		}
		if ("struct.yml".exists) {
			remove("struct.yml");
		}
		if ("int-auto.yml".exists) {
			remove("int-auto.yml");
		}
		if ("string-auto.json".exists) {
			remove("string-auto.json");
		}
		if ("struct-auto.yml".exists) {
			remove("struct-auto.yml");
		}
	}
	//Write the integer "3" to "int.yml"
	3.toFile!YAML("int.yml");
	//Write the string "str" to "string.json"
	"str".toFile!JSON("string.json");
	//Write a structure to "struct.yml"
	TestStruct("b").toFile!YAML("struct.yml");

	//Check that contents are correct
	assert("int.yml".fromFile!uint == 3);
	assert("string.json".fromFile!string == "str");
	assert("struct.yml".fromFile!TestStruct == TestStruct("b"));

	//Write the integer "3" to "int-auto.yml", but detect format automatically
	3.toFile("int-auto.yml");
	//Write the string "str" to "string-auto.json", but detect format automatically
	"str".toFile("string-auto.json");
	//Write a structure to "struct-auto.yml", but detect format automatically
	TestStruct("b").toFile("struct-auto.yml");

	//Check that contents are correct
	assert("int-auto.yml".fromFile!uint == 3);
	assert("string-auto.json".fromFile!string == "str");
	assert("struct-auto.yml".fromFile!TestStruct == TestStruct("b"));

	//Bad extension for auto-detection mechanism
	assertThrown(3.toFile("file.obviouslybadextension"));
}
version(unittest) {
	struct Empty {}
	struct Test2 {
		string inner;
	}
	enum TestEnum : uint { test = 0, something = 1, wont = 3, ya = 2 }
	struct TestNull {
		import std.typecons : Nullable;
		uint notNull;
		string aString;
		uint[] emptyArray;
		Nullable!uint aNullable;
		Nullable!(uint,0) anotherNullable;
		Nullable!SysTime noDate;
		Nullable!TestEnum noEnum;
		void toString(W)(ref W sink) @safe const {
			import std.format : formattedWrite;
			sink("TestNull(");
			formattedWrite(sink, "%s, ", notNull);
			formattedWrite(sink, "%s, ", aString);
			formattedWrite(sink, "%s, ", emptyArray);
			formattedWrite(sink, "%s, ", aNullable);
			formattedWrite(sink, "%s, ", anotherNullable);
			formattedWrite(sink, "%s, ", noDate);
			formattedWrite(sink, "%s, ", noEnum);
			sink(")");
		}
	}
}
@system unittest {
	import std.algorithm : canFind, filter;
	import std.conv : text, to;
	import std.datetime : Date, DateTime, SysTime, TimeOfDay;
	import std.exception : assertThrown;
	import std.format : format;
	import std.meta : AliasSeq, Filter;
	import std.stdio : writeln;
	import std.sumtype : SumType;
	import std.traits : Fields;
	static assert(siryulizers.length > 0);
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
	void runTest2(T, U)(auto ref T input, auto ref U expected) {
		import std.traits : isPointer;
		foreach (siryulizer; siryulizers) {
			assert(isSiryulizer!siryulizer);
			auto gotYAMLValue = input.toFormattedString!siryulizer.fromString!(U, siryulizer);
			static if (!isSumType!U) {
				auto gotYAMLValueOmit = input.toFormattedString!(siryulizer, Siryulize.omitInits).fromString!(U, siryulizer, DeSiryulize.optionalByDefault);
			}
			debug(verbosetesting) {
				writeln("-----");
				static if (isPointer!T) {
					writeln("Input:\n ", *input);
				} else {
					writeln("Input:\n ", input);
				}
				writeln("Serialized:\n", input.toFormattedString!siryulizer);
				static if (isPointer!T) {
					writeln("Output:\n ", *gotYAMLValue);
				} else {
					writeln("Output:\n ", gotYAMLValue);
				}
			}
			static if (isPointer!T && isPointer!U) {
				assert(*gotYAMLValue == *expected, format("%s->%s->%s failed", T.stringof, siryulizer.stringof, U.stringof));
				static if (!isSumType!U) {
					assert(*gotYAMLValueOmit == *expected, format("%s->%s->%s failed", T.stringof, siryulizer.stringof, U.stringof));
				}
			} else {
				auto vals = format("expected %s, got %s", expected, gotYAMLValue);
				assert(gotYAMLValue == expected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, vals));
				static if (!isSumType!U) {
					auto valsOmit = format("expected %s, got %s", expected, gotYAMLValueOmit);
					assert(gotYAMLValueOmit == expected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, valsOmit));
				}
			}
		}
	}
	void runTest2Fail(T, U)(auto ref U value, string file = __FILE__, size_t line = __LINE__) {
		foreach (siryulizer; siryulizers) {
			assertThrown(value.toString!siryulizer.fromString!(T, siryulizer), "Expected "~siryulizer.stringof~" to throw for "~value.text~" to "~T.stringof, file, line);
		}
	}
	void runTest(T)(auto ref T expected) {
		runTest2(expected, expected);
	}
	void runTestFail(T)(auto ref T expected) {
		runTest2Fail!T(expected);
	}
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

	assert(`{"a": null, "b": null, "c": null, "d": null, "e": null, "f": null}`.fromString!(StringCharTest,JSON) == StringCharTest.init);

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

	foreach (siryulizer; siryulizers) {
		auto result = TestNull().toFormattedString!siryulizer.fromString!(TestNull, siryulizer);

		assert(result.notNull == 0);
		assert(result.aString == "");
		assert(result.emptyArray == []);
		assert(result.aNullable.isNull());
		assert(result.anotherNullable.isNull());
		assert(result.noDate.isNull());
		assert(result.noEnum.isNull());
	}
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
	foreach (siryulizer; siryulizers) {
		assert(TestNull2().toString!siryulizer.fromString!(TestNull2, siryulizer).value.isNull);
		assert(Empty().toString!siryulizer.fromString!(TestNull2, siryulizer).value.isNull);
	}

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
			return SysTime(DateTime(2015,10,7,15,4,46),UTC());
		}
		static string toJunk(SysTime) @safe {
			return "this has nothing to do with time.";
		}
	}
	struct TimeTestString {
		string time;
	}
	runTest2(TimeTest(SysTime(DateTime(2015,10,7,15,4,46),UTC())), TimeTestString("this has nothing to do with time."));
	runTest2(TimeTestString("this has nothing to do with time."), TimeTest(SysTime(DateTime(2015,10,7,15,4,46),UTC())));

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
	foreach (siryulizer; siryulizers) {
		assert(Empty().toString!siryulizer.fromString!(RequiredTest2, siryulizer, DeSiryulize.optionalByDefault).y == 0, "Required test failed for "~siryulizer.stringof);
		assertThrown(RequiredTest2(4).toString!siryulizer.fromString!(RequiredTest, siryulizer, DeSiryulize.optionalByDefault), "Required test failed for "~siryulizer.stringof);
	}
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

	static struct LargeStruct {
		@disable this(this);
		uint[0x10000] largeData;
	}
	auto largeVal = new LargeStruct;
	runTest(largeVal);
}
///Use standard ISO8601 format for dates and times - YYYYMMDDTHHMMSS.FFFFFFFTZ
enum ISO8601;
///Use extended ISO8601 format for dates and times - YYYY-MM-DDTHH:MM:SS.FFFFFFFTZ
///Generally more readable than standard format.
enum ISO8601Extended;
///Autodetect the serialization format where possible.
enum AutoDetect;
package template isTimeType(T) {
	enum isTimeType = is(T == DateTime) || is(T == SysTime) || is(T == TimeOfDay) || is(T == Date);
}
static assert(isTimeType!DateTime);
static assert(isTimeType!SysTime);
static assert(isTimeType!Date);
static assert(isTimeType!TimeOfDay);
static assert(!isTimeType!string);
static assert(!isTimeType!uint);
static assert(!isTimeType!(DateTime[]));
/++
 + Gets the value contained within an UDA (only first attribute)
 +/
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
static assert(allSatisfy!(isSiryulizer, siryulizers));
debug {} else static assert(!isSiryulizer!uint);
