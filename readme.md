# Siryul - Serialization made simple
[![Coverage Status](https://coveralls.io/repos/Herringway/siryul/badge.svg?branch=main&service=github)](https://coveralls.io/github/Herringway/siryul?branch=main)
## Supported formats
* YAML
* JSON

## Supported platforms
* All known

## Example Usage

```D
import siryul;

struct Data {
	uint a;
	Nullable!uint b;
	string c;
	@Optional bool d;
}

writeln(Data(1, Nullable!uint.init, "Hello world!", true).toString!YAML());
//%YAML 1.1
//---
//a: 1
//b: null
//c: Hello world!
//d: true
```

```D
import siryul;

struct Data {
	uint a;
	Nullable!uint b;
	string c;
	@Optional bool d;
}

//With a document like...

//%YAML 1.1
//---
//a: 1
//b: null
//c: Hello world!

Data data = fromFile!(Data, YAML)("doc.yml");
```
