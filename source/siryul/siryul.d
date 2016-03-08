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
		import std.file : readText;
		return fromString!(T, Format, flags)(path.readText);
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
T fromString(T, Format = AutoDetect, DeSiryulize flags = DeSiryulize.none,U)(U str) if (((isSiryulizer!Format) || (is(Format == AutoDetect) && canAutomaticallyDeserializeString!T)) && isInputRange!U) {
	static if (is(Format == AutoDetect)) {
		static if (is(T == struct) || isAssociativeArray!T) {
			if (str[0] == '{')
				return fromString!(T, JSON, flags)(str);
			return fromString!(T, YAML, flags)(str);
		} else static if (isArray!T) {
			if (str[0] == '[')
				return fromString!(T, JSON, flags)(str);
			return fromString!(T, YAML, flags)(str);
		}
	} else //Not autodetecting
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

	//Compare a struct serialized into two different formats and auto-detect format
	const aStruct2 = fromString!TestStruct(`{"a": "b"}`);
	const anotherStruct2 = fromString!TestStruct("---\na: b");
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
@property string toString(Format, Siryulize flags = Siryulize.none, T)(T data) if (isSiryulizer!Format) {
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
		File(path, "w").write(data.toString!(Format, flags));
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
}
@safe unittest {
	import std.stdio : writeln;
	import std.algorithm : filter, canFind;
	import std.exception : assertThrown;
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
	void runTest2(SkipImmutable flag = SkipImmutable.no, T, U)(T input, U expected) @trusted {
		import std.string : format;
		import std.conv : to;
		foreach (siryulizer; siryulizers) {
			assert(isSiryulizer!siryulizer);
			auto gotYAMLValue = input.toFormattedString!siryulizer.fromString!(U, siryulizer);
			static if (flag == SkipImmutable.no) {
				auto immutableTest = (cast(immutable(T))input).toFormattedString!siryulizer.fromString!(U, siryulizer);
				auto constTest = (cast(const(T))input).toFormattedString!siryulizer.fromString!(U, siryulizer);
			}
			auto gotYAMLValueOmit = input.toFormattedString!(siryulizer, Siryulize.omitInits).fromString!(U, siryulizer, DeSiryulize.optionalByDefault);
			auto vals = format("expected %s, got %s", expected, gotYAMLValue);
			auto valsOmit = format("expected %s, got %s", expected, gotYAMLValueOmit);
			assert(gotYAMLValue == expected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, vals));
			static if (flag == SkipImmutable.no) {
				assert(constTest == expected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, vals));
				assert(immutableTest == expected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, vals));
			}
			assert(gotYAMLValueOmit == expected, format("%s->%s->%s failed, %s", T.stringof, siryulizer.stringof, U.stringof, valsOmit));
			static if (canAutomaticallyDeserializeString!U)
				assert(input.toFormattedString!siryulizer.fromString!U == expected, "Automagic "~T.stringof~"->"~siryulizer.stringof~"->"~U.stringof~" failed");
		}
	}
	void runTest2Fail(T, U)(U value) @safe nothrow {
		foreach (siryulizer; siryulizers)
			assertThrown(value.toString!siryulizer.fromString!(T, siryulizer));
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
	// dchars need newer version of dyaml
	runTest(StringCharTest('a', '‽', 'a'/+'\U00010300'+/, "↑↑↓↓←→←→ⒷⒶ", "↑↑↓↓←→←→ⒷⒶ", "↑↑↓↓←→←→ⒷⒶ"));

	assert(`{"a": null, "b": null, "c": null, "d": null, "e": null, "f": null}`.fromString!(StringCharTest,JSON) == StringCharTest.init);

	int[4] staticArray = [0, 1, 2, 3];
	runTest(staticArray);


	runTest(TimeOfDay(01, 01, 01));
	runTest(Date(2000, 01, 01));
	runTest(DateTime(2000, 01, 01, 01, 01, 01));
	runTest(SysTime(DateTime(2000, 01, 01), UTC()));

	runTest2!(SkipImmutable.yes)([0,1,2,3,4].filter!((a) => a%2 != 1), [0, 2, 4]);

	enum TestEnum : uint { test = 0, something = 1, wont = 3, ya = 2 }

	runTest2(3, TestEnum.wont);

	runTest2(TestEnum.something, TestEnum.something);
	runTest2(TestEnum.something, "something");

	struct TestNull {
		import std.typecons : Nullable, NullableRef;
		uint notNull;
		string aString;
		uint[] emptyArray;
		Nullable!uint aNullable;
		Nullable!(uint,0) anotherNullable;
		Nullable!SysTime noDate;
		NullableRef!uint nothingRef;
	}
	foreach (siryulizer; siryulizers) {
		auto result = TestNull().toFormattedString!siryulizer.fromString!(TestNull, siryulizer);

		assert(result.notNull == 0);
		assert(result.aString == "");
		assert(result.emptyArray == []);
		assert(result.aNullable.isNull());
		assert(result.anotherNullable.isNull());
		assert(result.noDate.isNull());
		assert(result.nothingRef.isNull());
	}
	auto nullableTest2 = TestNull(1, "a");
	nullableTest2.aNullable = 3;
	nullableTest2.anotherNullable = 4;
	nullableTest2.noDate = SysTime(DateTime(2000, 01, 01), UTC());
	nullableTest2.nothingRef.bind(new uint(5));
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
	foreach (siryulizer; siryulizers)
		assert(TestNull2().toString!siryulizer.fromString!(TestNull2, siryulizer).value.isNull);
	assert(`{}`.fromString!(TestNull2, JSON).value.isNull);
	assert(`---`.fromString!(TestNull2, YAML).value.isNull);

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

	//const int a = 1;
	//runTest(a);
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
///Used when nonpresence of field is not an error
enum Optional;
///Write field as string
enum AsString;
///Write field as binary (NYI)
enum AsBinary;
///Autodetect the serialization format where possible.
enum AutoDetect;
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
template isNullable(T) {
	enum isNullable = isNullableValue!T || isNullableRef!T;
}
template isNullable(alias T) {
	enum isNullable = isNullableValue!(typeof(T)) || isNullableRef!(typeof(T));
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
 + Determines whether or not a given type can be read from a string unambiguously
 +/
template canAutomaticallyDeserializeString(T) {
	enum canAutomaticallyDeserializeString = (isArray!T && !isSomeString!T) || isAssociativeArray!T || (is(T == struct) && !isTimeType!T);
}
static assert(canAutomaticallyDeserializeString!(string[]));
static assert(canAutomaticallyDeserializeString!(string[string]));
private struct ExampleStruct {}
static assert(canAutomaticallyDeserializeString!(ExampleStruct));
static assert(!canAutomaticallyDeserializeString!string);
static assert(!canAutomaticallyDeserializeString!uint);
/++
 + Gets the value contained within an UDA (only first attribute)
 +/
template getUDAValue(alias T, UDA) {
	static if (__traits(compiles, getUDAs!T)) {
		enum getUDAValue = getUDAs!(T, UDA)[0].value;
	} else {
		enum getUDAValue = () {
			static assert(hasUDA!(T, UDA));
			foreach(uda; __traits(getAttributes, T))
				static if(is(typeof(uda) == UDA))
					return uda;
			assert(0);
		}();
	}
}
unittest {
	@SiryulizeAs("a") string thinger;
	static assert(getUDAValue!(thinger, SiryulizeAs).name == "a");
}
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
//static assert(allSatisfy!(isSiryulizer, siryulizers));
//static assert(!isSiryulizer!uint);

T* moveToHeap(T)(ref T value) {
    import core.memory : GC;
    import std.algorithm : moveEmplace;
    auto ptr = cast(T*)GC.malloc(T.sizeof, 0, typeid(T));
    moveEmplace(value, *ptr);
    return ptr;
}