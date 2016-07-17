/++
 + Macros:
 + 	SUPPORTEDFORMATS = YAML, JSON, AutoDetect
 + 	SUPPORTEDAUTOFORMATS = .yml, .yaml for YAML and .json for JSON
 + 	SUPPORTEDSTRUCTURES = structs, built-in data types, Nullable, and std.datetime structs
 +/
module siryul.siryul;
import siryul;
import std.typecons, std.traits, std.range, std.meta;
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
				foreach (type; siryulizer.types) {
					case type:
						return fromFile!(T, siryulizer, flags)(path);
				}
			}
			default:
				throw new SerializeException("Unknown extension");
		}
	} else { //Not autodetecting
		import std.stdio : File, KeepTerminator;
		import std.algorithm : joiner;
		return fromString!(T, Format, flags)(File(path, "r").byLine(KeepTerminator.yes).joiner());
	}
}
///
unittest {
	import std.stdio : File;
	import std.path : exists;
	import std.file : remove;
	import std.exception : assertThrown;
	struct TestStruct {
		string a;
	}
	//Write some example files...
	File("int.yml", "w").write("---\n9");
	File("string.json", "w").write(`"test"`);
	File("struct.yml", "w").write("---\na: b");
	scope(exit) { //Clean up when done
		if ("int.yml".exists)
			remove("int.yml");
		if ("string.json".exists)
			remove("string.json");
		if ("struct.yml".exists)
			remove("struct.yml");
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
	return Format.parseInput!(T, flags)(str);
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
				foreach (type; siryulizer.types) {
					case type:
						return data.toFile!(siryulizer, flags)(path);
				}
			}
			default:
				throw new DeserializeException("Unknown extension");
		}
	} else { //Not autodetecting
		import std.stdio : File;
		import std.algorithm : copy;
		data.toFormattedString!(Format, flags).copy(File(path, "w").lockingTextWriter());
	}
}
///
unittest {
	import std.file : remove;
	import std.path : exists;
	import std.exception : assertThrown;
	struct TestStruct {
		string a;
	}
	scope(exit) { //Clean up when done
		if ("int.yml".exists)
			remove("int.yml");
		if ("string.json".exists)
			remove("string.json");
		if ("struct.yml".exists)
			remove("struct.yml");
		if ("int-auto.yml".exists)
			remove("int-auto.yml");
		if ("string-auto.json".exists)
			remove("string-auto.json");
		if ("struct-auto.yml".exists)
			remove("struct-auto.yml");
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
		void toString(scope void delegate(const(char)[]) @safe sink) @safe const {
			import std.format : formattedWrite;
			sink("TestNull(");
			formattedWrite(sink, "%s, ", notNull);
			formattedWrite(sink, "%s, ", aString);
			formattedWrite(sink, "%s, ", emptyArray);
			if (aNullable.isNull)
				sink("null, ");
			else
				formattedWrite(sink, "%s, ", aNullable.get);
			if (anotherNullable.isNull)
				sink("null, ");
			else
				formattedWrite(sink, "%s, ", anotherNullable.get);
			if (noDate.isNull)
				sink("null, ");
			else
				formattedWrite(sink, "%s, ", noDate.get);
			if (noEnum.isNull)
				sink("null, ");
			else
				formattedWrite(sink, "%s, ", noEnum.get);
			sink(")");
		}
	}
}
@safe unittest {
	import std.stdio : writeln;
	import std.algorithm : filter, canFind;
	import std.conv : to, text;
	import std.exception : assertThrown;
	import std.format : format;
	import std.datetime : DateTime, SysTime, Date, TimeOfDay;
	import std.meta : AliasSeq, Filter;
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
	alias SkipImmutable = Flag!"SkipImmutable";
	void runTest2(SkipImmutable flag = SkipImmutable.no, T, U)(T input, U expected) @safe {
		foreach (siryulizer; siryulizers) {
			assert(isSiryulizer!siryulizer);
			auto gotYAMLValue = input.toFormattedString!siryulizer.fromString!(U, siryulizer);
			auto gotYAMLValueOmit = input.toFormattedString!(siryulizer, Siryulize.omitInits).fromString!(U, siryulizer, DeSiryulize.optionalByDefault);
			static if (flag == SkipImmutable.no) {
				///Awkward workaround to avoid immutable/const casts in @safe.
				auto result = () @trusted {
					return tuple(cast(immutable)(cast(immutable)input).toFormattedString!siryulizer.fromString!(U, siryulizer),
					(cast(const(T))input).toFormattedString!siryulizer.fromString!(U, siryulizer),
					cast(immutable)expected,
					cast(const)expected);
				}();
				immutable immutableTest = result[0];
				immutable immutableExpected = result[2];
				const constTest = result[1];
				const constExpected = result[3];
			}
			auto vals = format("expected %s, got %s", expected, gotYAMLValue);
			auto valsOmit = format("expected %s, got %s", expected, gotYAMLValueOmit);
			assert(gotYAMLValue == expected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, vals));
			static if (flag == SkipImmutable.no) {
				assert(constTest == constExpected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, vals));
				assert(immutableTest == immutableExpected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, vals));
			}
			assert(gotYAMLValueOmit == expected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, valsOmit));
		}
	}
	void runTest2Fail(T, U)(U value) @safe {
		foreach (siryulizer; siryulizers)
			assertThrown(value.toString!siryulizer.fromString!(T, siryulizer), "Expected "~siryulizer.stringof~" to throw for "~value.text~" to "~T.stringof);
	}
	void runTest(T)(T expected) @safe {
		runTest2(expected, expected);
	}
	void runTestFail(T)(T expected) @safe {
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


	runTest(TimeOfDay(01, 01, 01));
	runTest(Date(2000, 01, 01));
	runTest(DateTime(2000, 01, 01, 01, 01, 01));
	runTest(SysTime(DateTime(2000, 01, 01), UTC()));

	runTest2!(SkipImmutable.yes)([0,1,2,3,4].filter!((a) => a%2 != 1), [0, 2, 4]);


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
	nullableTest2.noDate = SysTime(DateTime(2000, 01, 01), UTC());
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
		assert(siryulizer.emptyObject.fromString!(TestNull2, siryulizer).value.isNull);
	}

	runTest2Fail!bool("b");
	runTest2!(SkipImmutable.yes)(Nullable!string.init, wstring.init);
	runTest2!(SkipImmutable.yes)(Nullable!char.init, wchar.init);

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
		static SysTime fromJunk(string) {
			return SysTime(DateTime(2015,10,07,15,04,46),UTC());
		}
		static string toJunk(SysTime) {
			return "this has nothing to do with time.";
		}
	}
	struct TimeTestString {
		string time;
	}
	runTest2(TimeTest(SysTime(DateTime(2015,10,07,15,04,46),UTC())), TimeTestString("this has nothing to do with time."));
	runTest2(TimeTestString("this has nothing to do with time."), TimeTest(SysTime(DateTime(2015,10,07,15,04,46),UTC())));

	union Unhandleable { //Unions are too dangerous to handle automatically
		int a;
		char[4] b;
	}
	assert(!__traits(compiles, runTest(Unhandleable())));

	import std.typecons : Flag;
	runTest2(true, Flag!"Yep".yes);

	char[32] testChr = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
	runTest2(testChr, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
	runTest2("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", testChr);
	dchar[32] testChr2 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
	runTest2(testChr2, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"d);
	runTest2("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"d, testChr2);
	wchar[32] testChr3 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
	runTest2(testChr3, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"w);
	runTest2("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"w, testChr3);

	//int -> float[] array doesn't even make sense, should be rejected
	runTest2Fail!(float[])(3);
	//Precision loss should be rejected by default
	runTest2Fail!int(3.5);
}
///Use standard ISO8601 format for dates and times - YYYYMMDDTHHMMSS.FFFFFFFTZ
enum ISO8601;
///Use extended ISO8601 format for dates and times - YYYY-MM-DDTHH:MM:SS.FFFFFFFTZ
///Generally more readable than standard format.
enum ISO8601Extended;
///Autodetect the serialization format where possible.
enum AutoDetect;
package template isTimeType(T) {
	import std.datetime;
	enum isTimeType = is(T == DateTime) || is(T == SysTime) || is(T == TimeOfDay) || is(T == Date);
}
private import std.datetime;
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
		uint val = T.parseInput!(uint, DeSiryulize.none)("");
		string str = T.asString!(Siryulize.none)(3);
	});
}
static assert(allSatisfy!(isSiryulizer, siryulizers));
debug {} else static assert(!isSiryulizer!uint);
