# nim-experiment

# DON'T USE, NOT READY
README and project in progress


An experiment in building a nim macro-based pattern matching library.

### DSL

A macro `match` generates an if construct for now.

```nim

test "Object":
  let a = Rectangle(a: 2, b: 0)

  match(a):
  of (a: 4, b: 1):
    fail()
  of (a: 2, b: @b):
    check(b == 0)
  else:
    fail()
```

### Goals

* Ability to generate code with zero overhead compared to manually written if/case/for equivalents
* Expressive and flexible syntax for patterns
* Nice error reporting based on understandable generated code

The goals are ordered by priority. 

Speed is very important: the goal is to be able to use matching everywhere where you'd use a complicated `if`/`case`.
If there are cases, when we're slower:

This should be considered a bug.

or

This is a limitation of the library: which is not cool.


With enough discipline we can generate pretty readable code from our macro.
This would be very beneficial for the end user, as we can map his invocation with the generated code and help him
see the problem easily.

There are 3 cases:

* The user had a logical error in his patterns: easily seen with the generated code
* The user used a pattern in an unexpected way: this way he can see how its expansion differs from his expectation
* Our patterns worked incorrectly: the user can issue a bug

### Plan

* capturing
* subpatterns
* a `matches` abstraction that one can use either with capture arg as in [timotheecour idea](https://github.com/nim-lang/Nim/issues/8649#issuecomment-413323627 ) or as something that returns options
* custom unpackers

### Questions and answers

**I don't like @name : it's bizarre and surprising for users**

I like it, but I'd welcome ideas for a better syntax! Please, first check this list:

* `expr @ name` I can't see how to make it consistent with the `(field: capture)` case, the same with other binary
* `expr @ ``name`` ` I think this is more surprising, as it's used for 2 different puproses in quotes and in names


### Credits

[@krux02](https://github.com/krux02/) and [@andreaferretti](https://github.com/andreaferretti) are authors of the original nim pattern matching libs:

* @krux02 's [ast-pattern-matching](https://github.com/krux02/ast-pattern-matching)
* @andreaferretti 's [patty](https://github.com/andreaferretti/patty)

I took inspiration from their DSL-s and discussions with them (An early version of this dsl was even a PR to @krux02 's lib).

Thanks to [@mratsim](https://github.com/mratsim) for giving me the `@name` idea with one of his [github comments on possible nim pattern matching syntax](https://github.com/nim-lang/Nim/issues/8649#issuecomment-413318800), I initially had way more inconsistent notation in mind.
