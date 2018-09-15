# nim-experiment



An experiment in building a nim macro-based pattern matching library.

### DSL

A macro `match` generates an if construct for now.

```
nim

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

Thanks to @mratsim for giving me the `@name` idea with one of his github comments on possible nim pattern matching syntax, I initially had way more inconsistent notation in mind.
