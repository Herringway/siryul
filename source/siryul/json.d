module siryul.json;
import core.time : Duration;
private import siryul.common;
private import std.json : JSONValue, JSONType, parseJSON, toJSON;
private import std.range.primitives : ElementType, isInfinite, isInputRange, isOutputRange;
private import std.traits : isAggregateType, isAssociativeArray, isFloatingPoint, isIntegral, isPointer, isSomeChar, isSomeString, isStaticArray, Unqual;
private import std.typecons;
/++
 + JSON (JavaScript Object Notation) serialization format
 +
 + Note that only strings are supported for associative array keys in this format.
 +/
struct JSON {
	package static T parseInput(T, DeSiryulize flags, U)(U data, string filename) if (isInputRange!U && isSomeChar!(ElementType!U)) {
		T output;
		deserialize(Node(parseJSON(data), filename), output, BitFlags!DeSiryulize(flags));
		return output;
	}
	package static string asString(Siryulize flags, T)(T data) {
		const json = serialize!Node(data, BitFlags!Siryulize(flags));
		return toJSON(json.value, true);
	}
	static struct Node {
		private JSONValue value;
		string name;
		this(T)(T value, string name = "<unknown>") if (canStoreUnchanged!T) {
			this(JSONValue(value), name);
		}
		private this(JSONValue value, string name = "<unknown>") @safe pure nothrow @nogc {
			this.value = value;
			this.name = name;
		}
		this(Node[] newValues, string name = "<unknown>") @safe pure {
			JSONValue[] values;
			values.reserve(newValues.length);
			foreach (newValue; newValues) {
				values ~= newValue.value;
			}
			this(JSONValue(values), name);
		}
		this(Node[string] newValues, string name = "<unknown>") @safe pure {
			JSONValue[string] values;
			foreach (newKey, newValue; newValues) {
				values[newKey] = newValue.value;
			}
			this(JSONValue(values), name);
		}
		enum hasStringIndexing = false;
		Mark getMark() const @safe pure {
			return Mark(name);
		}
		bool hasTypeConvertible(T)() const {
			static if (is(T == typeof(null))) {
				return value.type == JSONType.null_;
			} else static if (is(T: const(char)[])) {
				return value.type == JSONType.string;
			} else static if (is(T : bool)) {
				return (value.type == JSONType.true_) || (value.type == JSONType.false_);
			} else static if (is(T == long)) {
				return value.type == JSONType.integer;
			} else static if (is(T == ulong)) {
				return value.type == JSONType.uinteger;
			} else static if (is(T : real)) {
				return value.type == JSONType.float_;
			} else {
				return false;
			}
		}
		bool hasClass(Classification c) const @safe pure {
			final switch (c) {
				case Classification.scalar:
					return (value.type != JSONType.array) && (value.type != JSONType.object);
				case Classification.sequence:
					return value.type == JSONType.array;
				case Classification.mapping:
					return value.type == JSONType.object;
			}
		}
		T getType(T)() {
			static if (is(T: const(char)[])) {
				return value.str;
			} else static if (is(T : bool)) {
				return value.boolean;
			} else static if (is(T : typeof(null))) {
				return value.type == JSONType.null_;
			} else static if (is(T == ulong)) {
				return value.uinteger;
			} else static if (is(T == long)) {
				return value.integer;
			} else static if (is(T : real)) {
				return value.floating;
			} else {
				assert(0, "Cannot represent type");
			}
		}
		string type() const @safe {
			final switch (value.type) {
				case JSONType.null_:
				case JSONType.true_:
				case JSONType.false_: return "bool";
				case JSONType.integer: return "long";
				case JSONType.uinteger: return "ulong";
				case JSONType.float_: return "real";
				case JSONType.string: return "string";
				case JSONType.array: return "Node[]";
				case JSONType.object: return "Node[string]";
			}
		}
		void opAssign(T)(T newValue) if (canStoreUnchanged!T) {
			value = JSONValue(newValue);
		}
		Node opIndex(size_t index) @safe {
			return Node(value.arrayNoRef[index], name);
		}
		Node opIndex(string index) @safe {
			return Node(value.objectNoRef[index], name);
		}
		size_t length() const @safe {
			if (value.type == JSONType.array) {
				return value.arrayNoRef.length;
			} else if (value.type == JSONType.object) {
				return value.objectNoRef.length;
			} else {
				throw new DeserializeException("Node has no length", getMark());
			}
		}
		bool opBinaryRight(string op : "in")(string key) {
			return !!(key in value);
		}
		int opApply(scope int delegate(string k, Node v) @safe dg) @safe {
			foreach (string k, JSONValue v; value.objectNoRef) {
				const result = dg(k, Node(v, name));
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
	runTests!JSON();
}
