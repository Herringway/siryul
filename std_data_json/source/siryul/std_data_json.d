module siryul.std_data_json;

import core.time : Duration;
private import siryul.common;
private import std.conv;
private import std.range;
private import std.traits;
private import std.typecons;

import stdx.data.json;

/++
 + JSON (JavaScript Object Notation) serialization format
 +
 + Note that only strings are supported for associative array keys in this format.
 +/
struct StdDataJSON {
	package static T parseInput(T, DeSiryulize flags, U)(U data, string name) if (isInputRange!U && isSomeChar!(ElementType!U)) {
		T output;
		auto json = toJSONValue(data);
		json.location.file = name;
		deserialize(Node(json), output, BitFlags!DeSiryulize(flags));
		return output;
	}
	package static string asString(Siryulize flags, T)(T data) {
		const json = serialize!Node(data, BitFlags!Siryulize(flags));
		return toJSON(json.value);
	}
	static struct Node {
		private JSONValue value;
		this(T)(T value) if (canStoreUnchanged!T) {
			this.value = JSONValue(value);
		}
		private this(JSONValue value) @safe pure nothrow @nogc {
			this.value = value;
		}
		this(Node[] newValues) @safe pure {
			JSONValue[] values;
			values.reserve(newValues.length);
			foreach (newValue; newValues) {
				values ~= newValue.value;
			}
			this.value = JSONValue(values);
		}
		this(Node[string] newValues) @safe pure {
			JSONValue[string] values;
			foreach (newKey, newValue; newValues) {
				values[newKey] = newValue.value;
			}
			this.value = JSONValue(values);
		}
		enum hasStringIndexing = false;
		Mark getMark() const @safe pure nothrow {
			return Mark(value.location.file, value.location.line, value.location.column);
		}
		bool hasTypeConvertible(T)() const {
			static if (is(T == typeof(null))) {
				return value.hasType!(typeof(null));
			} else static if (is(T: const(char)[])) {
				return value.hasType!string;
			} else static if (is(T : bool)) {
				return value.hasType!bool;
			} else static if (is(T == long) || is(T == ulong)) {
				return value.hasType!long;
			} else static if (is(T : real)) {
				return value.hasType!double;
			} else {
				return false;
			}
		}
		bool hasClass(Classification c) const @safe pure {
			final switch (c) {
				case Classification.scalar:
					return !value.hasType!(JSONValue[]) && !value.hasType!(JSONValue[string]);
				case Classification.sequence:
					return value.hasType!(JSONValue[]);
				case Classification.mapping:
					return value.hasType!(JSONValue[string]);
			}
		}
		T getType(T)() {
			static if (is(T: const(char)[])) {
				return value.get!string;
			} else static if (is(T : bool)) {
				return value.get!bool;
			} else static if (is(T : typeof(null))) {
				return value.get!(typeo(null));
			} else static if (is(T == real)) {
				return cast(T)value.get!double;
			} else static if (is(T == ulong) || is(T == long)) {
				return cast(T)value.get!long;
			} else {
				assert(0, "Cannot represent type");
			}
		}
		string type() const @safe {
			return value.payload.kind.text;
		}
		void opAssign(T)(T newValue) if (canStoreUnchanged!T) {
			value = JSONValue(newValue);
		}
		Node opIndex(size_t index) @safe {
			return Node(value[index]);
		}
		Node opIndex(string index) @safe {
			return Node(value[index]);
		}
		size_t length() const @safe {
			if (value.hasType!(JSONValue[])) {
				return value.get!(JSONValue[]).length;
			} else if (value.hasType!(JSONValue[string])) {
				return value.get!(JSONValue[string]).length;
			} else {
				throw new DeserializeException("Node has no length", getMark());
			}
		}
		bool opBinaryRight(string op : "in")(string key) {
			return !!(key in value);
		}
		int opApply(scope int delegate(string k, Node v) @safe dg) @safe {
			foreach (string k, JSONValue v; value.get!(JSONValue[string])) {
				const result = dg(k, Node(v));
				if (result != 0) {
					return result;
				}
			}
			return 0;
		}
		template canStoreUnchanged(T) {
			import std.traits : isFloatingPoint, isIntegral;
			enum canStoreUnchanged = isIntegral!T || is(T == string) || is(T : bool) || isFloatingPoint!T;
		}
	}
}

@safe unittest {
	import siryul.testing;
	runTests!StdDataJSON();
}
