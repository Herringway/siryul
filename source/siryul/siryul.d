module siryul.siryul;
import siryul;
import std.typecons, std.traits;

T fromFile(T, Format)(string path) {
	import std.file : read;
	return fromString!(T,Format)(cast(string)path.read());
}
T fromFile(T)(string path) {
	import std.path;
	switch(path.extension) {
		case ".yml", ".yaml":
			return fromFile!(T, YAML)(path);
		case ".json":
			return fromFile!(T, JSON)(path);
		default:
			throw new SerializeException("Unknown extension");
	}
}
T fromString(T, Format)(string data) {
	return Format.parseString!T(data);
}
@property string asString(Format, T)(T data) {
	return Format.asString(data);
}
void writeFile(Format, T)(T data, string path) {
	import std.stdio : File;
	File(path, "w").write(data.asString!Format);
}
void writeFile(T)(T data, string path) {
	import std.path;
	switch(path.extension) {
		case ".yml", ".yaml":
			writeFile!YAML(data, path);
			break;
		case ".json":
			writeFile!JSON(data, path);
			break;
		default:
			throw new DeserializeException("Unknown extension");
	}
}
version(unittest) {
	struct Test2 {
		string inner;
	}
}
unittest {
	import std.stdio : writeln;
	import std.algorithm : filter;
	import std.file;
	struct Test {
		string a;
		uint b;
		ubyte c;
		string[] d;
		short[string] e;
		@Optional bool f = false;
		Test2[string] g;
		double h;
	}
	void RunTest2(T, U)(T input, U expected) {
		assert(input.asString!YAML.fromString!(U, YAML) == expected);
		assert(input.asString!JSON.fromString!(U, JSON) == expected);
	}
	void RunTest(T)(T expected) {
		RunTest2(expected, expected);
	}
	auto testInstance = Test("beep", 2, 4, ["derp", "blorp"], ["one":1, "two":3], false, ["Test2":Test2("test")], 4.5);
	scope(exit) if ("test.json".exists) remove("test.json");
	scope(exit) if ("test.yml".exists) remove("test.yml");
	testInstance.writeFile("test.json");
	testInstance.writeFile("test.yml");
	assert(fromFile!(Test)("test.json") == testInstance);
	assert(fromFile!(Test)("test.yml") == testInstance);

	assert(`{"a": "beep","b": 2,"c": 4,"d": ["derp","blorp"],"e": {"one": 1,"two": 3},"g": {"Test2":{"inner": "test"}}, "h": 4.5}`.fromString!(Test,JSON) == testInstance);
	assert(`{"a": "beep","b": 2,"c": 4,"d": ["derp","blorp"],"e": {"one": 1,"two": 3},"f": false,"g": {"Test2":{"inner": "test"}}, "h": 4.5}`.fromString!(Test,JSON) == testInstance);
	
	RunTest(testInstance);

	int[4] staticArray = [0, 1, 2, 3];
	RunTest(staticArray);

	import std.datetime;

	RunTest(TimeOfDay(01, 01, 01));
	RunTest(Date(2000, 01, 01));
	RunTest(DateTime(2000, 01, 01, 01, 01, 01));
	RunTest(SysTime(DateTime(2000, 01, 01), UTC()));

	RunTest2([0,1,2,3,4].filter!((a) => a%2 != 1), [0, 2, 4]);

	enum testEnum { test, something, wont, ya }

	RunTest2(testEnum.something, testEnum.something);
	RunTest2(testEnum.something, "something");

	struct testNull {
		import std.typecons;
		uint notNull;
		string aString;
		Nullable!uint aNullable;
		Nullable!(uint,0) anotherNullable;
	}
	auto resultYAML = testNull().asString!YAML.fromString!(testNull, YAML);
	auto resultJSON = testNull().asString!JSON.fromString!(testNull, JSON);

	assert(resultYAML.notNull == 0);
	assert(resultJSON.notNull == 0);
	assert(resultYAML.aString == "");
	assert(resultJSON.aString == "");
	assert(resultYAML.aNullable.isNull());
	assert(resultJSON.aNullable.isNull());
	assert(resultYAML.anotherNullable.isNull());
	assert(resultJSON.anotherNullable.isNull());
	auto nullableTest2 = testNull(1, "a");
	nullableTest2.aNullable = 3;
	nullableTest2.anotherNullable = 4;
	RunTest(nullableTest2);
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


template isNullable(T) {
	static if(__traits(compiles, TemplateArgsOf!T) && __traits(compiles, Nullable!(TemplateArgsOf!T)) && is(T == Nullable!(TemplateArgsOf!T)))
		enum isNullable = true;
	else
		enum isNullable = false;
}
static assert(isNullable!(Nullable!int));
static assert(isNullable!(Nullable!(int, 0)));
static assert(!isNullable!int);
