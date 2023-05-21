/++
 + Macros:
 + 	SUPPORTEDSTRUCTURES = structs, built-in data types, Nullable, and std.datetime structs
 +/
module siryul.siryul;
import siryul;
import std.datetime;
import std.meta;
import std.range;
alias siryulizers = AliasSeq!(JSON, YAML);

/++
 + Deserializes data from a file.
 +
 + Files are assumed to be UTF-8 encoded.
 +
 + Supports $(SUPPORTEDSTRUCTURES).
 +
 + Params:
 + T = Type stored in the file
 + Format = Serialization format
 + path = Absolute or relative path to the file
 +
 + Returns: Data from the file in the format specified
 +/
T fromFile(T, Format, DeSiryulize flags = DeSiryulize.none)(string path) if (isSiryulizer!Format) {
	import std.algorithm : joiner;
	import std.file : readText;
	auto lines = readText(path);
	return Format.parseInput!(T, flags)(lines, path);
}
///
@safe unittest {
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
}
/++
 + Deserializes data from a string.
 +
 + String is assumed to be UTF-8 encoded.
 +
 + Params:
 + T = Type of the data to be deserialized
 + Format = Serialization format
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
@safe unittest {
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
 + Format = Serialization format
 + data = The data to be serialized
 +
 + Returns: A string in the specified format representing the user's data, UTF-8 encoded
 +/
@property auto toString(Format, Siryulize flags = Siryulize.none, T)(T data) if (isSiryulizer!Format) {
	return Format.asString!flags(data);
}
///
@safe unittest {
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
 + Format = Serialization format
 + data = The data to be serialized
 + path = The path for the file to be written
 +/
@property void toFile(Format, Siryulize flags = Siryulize.none, T)(T data, string path) if (isSiryulizer!Format) {
	import std.algorithm : copy;
	import std.stdio : File;
	data.toFormattedString!(Format, flags).copy(File(path, "w").lockingTextWriter());
}
///
@safe unittest {
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
	assert("int.yml".fromFile!(uint, YAML) == 3);
	assert("string.json".fromFile!(string, JSON) == "str");
	assert("struct.yml".fromFile!(TestStruct, YAML) == TestStruct("b"));
}
