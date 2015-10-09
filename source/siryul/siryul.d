/++
 + Macros:
 + 	SUPPORTEDFORMATS = YAML, JSON, AutoDetect
 + 	SUPPORTEDAUTOFORMATS = .yml, .yaml for YAML and .json for JSON
 + 	SUPPORTEDSTRUCTURES = structs, built-in data types, Nullable, and std.datetime structs
 +/
module siryul.siryul;
import siryul;
import std.typecons, std.traits;

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
T fromFile(T, Format = AutoDetect)(string path) {
	static if (is(Format == AutoDetect)) {
		import std.path;
		switch(path.extension) {
			case ".yml", ".yaml":
				return fromFile!(T, YAML)(path);
			case ".json":
				return fromFile!(T, JSON)(path);
			default:
				throw new SerializeException("Unknown extension");
		}
	} else { //Not autodetecting
		import std.file : read;
		return fromString!(T,Format)(cast(string)path.read());
	}
}
///
unittest {
	import std.stdio : File;
	import std.path : exists;
	import std.file : remove;
	import std.exception : assertThrown;
	struct testStruct {
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
	assert(fromFile!(testStruct, YAML)("struct.yml") == testStruct("b"));
	//Read examples from respective files using automatic format detection
	assert(fromFile!uint("int.yml") == 9);
	assert(fromFile!string("string.json") == "test");
	assert(fromFile!testStruct("struct.yml") == testStruct("b"));


	assertThrown("file.obviouslybadextension".fromFile!uint);
}
/++
 + Deserializes data from a string.
 + 
 + String is assumed to be UTF-8 encoded. If no format (or AutoDetect) is
 + specified, an attempt at autodetction is made.
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
T fromString(T, Format = AutoDetect)(string str) if (!is(Format == AutoDetect) || canAutomaticallyDeserializeString!T) {
	static if (is(Format == AutoDetect)) {
		static if (is(T == struct) || isAssociativeArray!T) {
			if (str[0] == '{')
				return fromString!(T, JSON)(str);
			return fromString!(T, YAML)(str);
		} else static if (isArray!T) {
			if (str[0] == '[')
				return fromString!(T, JSON)(str);
			return fromString!(T, YAML)(str);
		}
	} else //Not autodetecting
		return Format.parseString!T(str);
}
///
unittest {
	struct testStruct {
		string a;
	}
	//Compare a struct serialized into two different formats
	auto aStruct = fromString!(testStruct, JSON)(`{"a": "b"}`);
	auto anotherStruct = fromString!(testStruct, YAML)("---\na: b");
	assert(aStruct == anotherStruct);

	//Compare a struct serialized into two different formats and auto-detect format
	auto aStruct2 = fromString!testStruct(`{"a": "b"}`);
	auto anotherStruct2 = fromString!testStruct("---\na: b");
	assert(aStruct2 == anotherStruct2);
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
@property string toString(Format, T)(T data) {
	return Format.asString(data);
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
@property void toFile(Format = AutoDetect, T)(T data, string path) {
	static if (is(Format == AutoDetect)) {
		import std.path;
		switch(path.extension) {
			case ".yml", ".yaml":
				data.toFile!YAML(path);
				break;
			case ".json":
				data.toFile!JSON(path);
				break;
			default:
				throw new DeserializeException("Unknown extension");
		}
	} else { //Not autodetecting
		import std.stdio : File;
		File(path, "w").write(data.toString!Format);
	}
}
///
unittest {
	import std.file : remove;
	import std.path : exists;
	import std.exception : assertThrown;
	struct testStruct {
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
	testStruct("b").toFile!YAML("struct.yml");

	//Check that contents are correct
	assert("int.yml".fromFile!uint == 3);
	assert("string.json".fromFile!string == "str");
	assert("struct.yml".fromFile!testStruct == testStruct("b"));

	//Write the integer "3" to "int-auto.yml", but detect format automatically
	3.toFile("int-auto.yml");
	//Write the string "str" to "string-auto.json", but detect format automatically
	"str".toFile("string-auto.json");
	//Write a structure to "struct-auto.yml", but detect format automatically
	testStruct("b").toFile("struct-auto.yml");

	//Check that contents are correct
	assert("int-auto.yml".fromFile!uint == 3);
	assert("string-auto.json".fromFile!string == "str");
	assert("struct-auto.yml".fromFile!testStruct == testStruct("b"));

	//Bad extension for auto-detection mechanism
	assertThrown(3.toFile("file.obviouslybadextension"));
}
version(unittest) {
	struct Test2 {
		string inner;
	}
}
@safe unittest {
	import std.stdio : writeln;
	import std.algorithm : filter, canFind;
	import std.exception : assertThrown;
	import std.file;
	import std.datetime;
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
	void RunTest2(T, U)(T input, U expected) @safe {
		import std.string : format;
		foreach (siryulizer; siryulizers) {
			assert(isSiryulizer!siryulizer);
			auto gotYAMLValue = input.toFormattedString!siryulizer.fromString!(U, siryulizer);
			string vals;
			() @trusted {
				vals = format("expected %s, got %s", expected, gotYAMLValue);
			}();
			assert(gotYAMLValue == expected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, vals));
			static if (canAutomaticallyDeserializeString!U)
				assert(input.toFormattedString!siryulizer.fromString!U == expected, "Automagic "~T.stringof~"->"~siryulizer.stringof~"->"~U.stringof~" failed");
		}
	}
	void RunTest2_Fail(T, U)(U value) @safe nothrow {
		assertThrown(value.toString!YAML.fromString!(T, YAML));
		assertThrown(value.toString!JSON.fromString!(T, JSON));
	}
	void RunTest(T)(T expected) @safe {
		RunTest2(expected, expected);
	}
	void RunTest_Fail(T)(T expected) @safe {
		RunTest2_Fail!T(expected);
	}
	auto testInstance = Test("beep", 2, 4, ["derp", "blorp"], ["one":1, "two":3], false, ["Test2":Test2("test")], 4.5, 'g');
	
	RunTest(testInstance);
	RunTest(testInstance.d);
	RunTest(testInstance.g);
	@safe struct stringCharTest {
		char a;
		wchar b;
		dchar c;
		string d;
		wstring e;
		dstring f;
	}
	RunTest(stringCharTest('a', '‽', '\U00010300', "↑↑↓↓←→←→ⒷⒶ", "↑↑↓↓←→←→ⒷⒶ", "↑↑↓↓←→←→ⒷⒶ"));

	assert(`{"a": null, "b": null, "c": null, "d": null, "e": null, "f": null}`.fromString!(stringCharTest,JSON) == stringCharTest.init);

	int[4] staticArray = [0, 1, 2, 3];
	RunTest(staticArray);


	RunTest(TimeOfDay(01, 01, 01));
	RunTest(Date(2000, 01, 01));
	RunTest(DateTime(2000, 01, 01, 01, 01, 01));
	RunTest(SysTime(DateTime(2000, 01, 01), UTC()));

	RunTest2([0,1,2,3,4].filter!((a) => a%2 != 1), [0, 2, 4]);

	enum testEnum : uint { test = 0, something = 1, wont = 3, ya = 2 }
	
	RunTest2(3, testEnum.wont);

	RunTest2(testEnum.something, testEnum.something);
	RunTest2(testEnum.something, "something");

	@safe struct testNull {
		import std.typecons;
		uint notNull;
		string aString;
		uint[] emptyArray;
		Nullable!uint aNullable;
		Nullable!(uint,0) anotherNullable;
	}
	auto resultYAML = testNull().toString!YAML.fromString!(testNull, YAML);
	auto resultJSON = testNull().toString!JSON.fromString!(testNull, JSON);

	assert(resultYAML.notNull == 0);
	assert(resultJSON.notNull == 0);
	assert(resultYAML.aString == "");
	assert(resultJSON.aString == "");
	assert(resultYAML.emptyArray == []);
	assert(resultJSON.emptyArray == []);
	assert(resultYAML.aNullable.isNull());
	assert(resultJSON.aNullable.isNull());
	assert(resultYAML.anotherNullable.isNull());
	assert(resultJSON.anotherNullable.isNull());
	auto nullableTest2 = testNull(1, "a");
	nullableTest2.aNullable = 3;
	nullableTest2.anotherNullable = 4;
	RunTest(nullableTest2);

	struct SiryulizeAsTest {
		@SiryulizeAs("word") string something;
	}
	RunTest(SiryulizeAsTest("a"));
	assert(SiryulizeAsTest("a").toString!YAML.canFind("word"));
	assert(SiryulizeAsTest("a").toString!JSON.canFind("word"));

	struct testNull2 {
		@Optional @SiryulizeAs("v") Nullable!bool value;
	}
	auto testval = testNull2();
	testval.value = true;
	RunTest(testval);
	testval.value = false;
	RunTest(testval);
	assert(testNull2().toString!YAML.fromString!(testNull2, YAML).value.isNull);
	assert(testNull2().toString!JSON.fromString!(testNull2, JSON).value.isNull);
	assert(`{}`.fromString!(testNull2, JSON).value.isNull);
	assert(`---`.fromString!(testNull2, YAML).value.isNull);

	RunTest2_Fail!bool("b");
	assert(`null`.fromString!(wstring, JSON) == "");
	assert(`null`.fromString!(wstring, YAML) == "");
	assert(`null`.fromString!(wchar, JSON) == wchar.init);
	assert(`null`.fromString!(wchar, YAML) == wchar.init);

	//Autoconversion tests
	//string <-> int
	RunTest2("3", 3);
	RunTest2(3, "3");
	//string <-> float
	RunTest2("3.0", 3.0);
	RunTest2(3.0, "3");
}

class SiryulException : Exception {
	this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
class SerializeException : SiryulException {
	this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
class DeserializeException : SiryulException {
	this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
		super(msg, file, line);
	}
}
enum Optional;
enum AsString;
enum AsBinary;
enum AutoDetect;
struct SiryulizeAs { string name; }

template isNullable(T) {
	static if(__traits(compiles, TemplateArgsOf!T) && __traits(compiles, Nullable!(TemplateArgsOf!T)) && is(T == Nullable!(TemplateArgsOf!T)))
		enum isNullable = true;
	else
		enum isNullable = false;
}
static assert(isNullable!(Nullable!int));
static assert(isNullable!(Nullable!(int, 0)));
static assert(!isNullable!int);

template isTimeType(T) {
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

template canAutomaticallyDeserializeString(T) {
	enum canAutomaticallyDeserializeString = (isArray!T && !isSomeString!T) || isAssociativeArray!T || (is(T == struct) && !isTimeType!T);
}
static assert(canAutomaticallyDeserializeString!(string[]));
static assert(canAutomaticallyDeserializeString!(string[string]));
private struct exampleStruct {}
static assert(canAutomaticallyDeserializeString!(exampleStruct));
static assert(!canAutomaticallyDeserializeString!string);
static assert(!canAutomaticallyDeserializeString!uint);

template getUDAValue(alias T, UDA) {
	enum getUDAValue = () {
		static assert(hasUDA!(T, UDA));
		foreach(uda; __traits(getAttributes, T))
			static if(is(typeof(uda) == UDA))
				return uda;
		assert(0);
	}();
}
unittest {
	@SiryulizeAs("a") string thinger;
	static assert(getUDAValue!(thinger, SiryulizeAs).name == "a");
}