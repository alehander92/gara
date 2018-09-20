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

### Features

Matching 

* values
* types
* objects
* nested subpatterns
* capture subpatterns and values with `@name`
* variants
* wildcard
* seq
* match many elements in seq with `*`
* two kinds of custom unpackers (thanks to @krux02 for making me aware of the scala pattern matching design and apply/unapply: they work differently here though)
* support for recognizing other types as variant(to support NimNode)
* DSL for init variants with `~Variant.Kind(fields)`

### Values

Just test for equality with the value. Works also if you pass an existing variable instead of 2

```nim
let a = 2

match(a):
of 2:
  echo "2"
else:
  echo "no 2"
```

### Types

The library tests with `is`

```nim
match(a):
of Rectangle:
  echo "rectangle"
else:
  echo "other"
```

### Objects

We have a simpler syntax for objects.
You can type only the fields, and then we check only them: this is a good idea because usually
you know the type of the object that you are passing, so there is rarely ambiguity.
Of course you can still add the type if you want. You can use this for tuples too.

You can pass just some of the fields!

```nim
match(a):
of (a: 0, b: 0):
  echo "ok"
of Rectangle(a: -2):
  echo "weird"
else:
  echo 0
```

### Subpatterns

You can match subpatterns.

```nim
match(a):
of A(b: B(c: 0)):
  echo "ok"
else:
  echo "fail"
```

### Capturing

We capture with `@name` for all our usecases: wsubpatterns and values.
You write `stuff @name` which shouldn't be ambigious in general(please read the answers and questions section)

```nim
match(a):
of C(e: E(f: @f) @e):
  echo e
  echo f
else:
  echo "fail"
```

### Variants

We recognize when you do `enumLabel(..)` and we match variants then. That's very nice if you are threating them as abstract data types.

```nim
match(a):
of Merge(original: @original, other: @other):
  echo original
of Normal(message: @message):
  echo message
else:
  echo a
```

### Wildcards

You can use `_` as a wildcard, it always succeeds.

```nim
match(a):
of _:
  echo a
else:
  echo "nope"
```

### seq

```nim
match(a):
of @[4, 5]:
  echo "ok"
else:
  echo "no"
```

### Many elements in seq

You can match repeated properties

```nim
match(a):
of @[_, _, *(a: @list)]:
  echo list
else:
  echo @[]
```

Here we match the elements after 1 and collect their a fields. You can also just `@name` the whole subpattern: it should be always a seq.
We use `allIt` for the test, but in a case like this, we optimize it out, as it is always true(we just load values).

### Unpackers

We can have unpackers for types: you define `proc unpack(t: Type): T` for your type.
The powerful thing is, `T` can be anything that has a len and `[int]`(we will add a concept for that later).
For example we do this for NimNode

```nim
proc unpack(node: NimNode): NimNode =
  node
```

Of course we are lucky here, but you can do transformations for more complicated cases.

When you do this, you can use the unpacked values like `Type(value, value)` .
We even recognize the enum case, so you can do it for variants too.

we also have function unpackers: `proc name(t: Type): T`. This way you can have many unpackers for the same type.
You match passing them as calls with their expected values: `name(res)`

```nim
proc data(email: Email): tuple[name: string, domain: string] =
  let words = email.raw.split('@', 1)
  (name: words[0], domain: words[1])

proc tokens(email: Email): seq[string] =
  # slow
  result = @[]
  var token = ""
  for i, c in email.raw:
    if not c.isAlphaNumeric():
      if token.len > 0:
        result.add(token)
        token = ""
      result.add($c)
    else:
      token.add(c)
  if token.len > 0:
    result.add(token)

match(email):
of data(name: "academy"):
  echo email
of tokens(@[_, _, _, _, @token]):
  echo token
```

(I got the idea for the email example from @andreaferretti's patty)

### Support for types as variants

Sometimes a type acts like a variant, but isn't defined like one: you can teach the library to do it.
It uses internally `eKind` to get the kind field of a variant, so you just need to override it

```nim
proc eKind*(node: NimNode): NimNodeKind =
  node.kind
```

With this and unpack you can match NimNode now
```nim
macro test(node: untyped): untyped =
  let code = node[0]
  let q = ident("f")
  match code:
  of nnkCall(q, nnkIntLit @i):
    echo i.repr
  else:
    echo ""

test:
  f(2)
```

It's still not perfects, as we need a better syntax for passing ident("f") etc but we're getting there

### Matching more

We are close to adding some more features: 
  * unification (again inspired by @andreaferretti's patty ideas)
  * if guard

Unification should be relatively simple to implement, for now just making sure several subvalues are equal.

If guards would probably use `of ... and test` syntax, we might also add support for `or`, but I am not sure it's very useful


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

Currently not every feature is optimized well(there are some blockers, and some features are still experimental)

With enough discipline we can generate pretty readable code from our macro.
This would be very beneficial for the end user, as we can map his invocation with the generated code and help him
see the problem easily.

It's not always possible to directly produce nice code, so sometimes we'll delegate to other macros.
Still, maybe we can make their code also visible in debug mode, so the user still knows what happened


There are 3 cases:

* The user had a logical error in his patterns: easily seen with the generated code
* The user used a pattern in an unexpected way: this way he can see how its expansion differs from his expectation
* Our patterns worked incorrectly: the user can issue a bug

We also need to add a `matches` abstraction that one can use either with capture arg as in [timotheecour idea](https://github.com/nim-lang/Nim/issues/8649#issuecomment-413323627 ) or as something that returns options

### Plan

* if guards
* error reporting

### Questions and answers

**I don't like @name : it's bizarre and surprising for users**

I like it, but I'd welcome ideas for a better syntax! Please, first check this list:

* `expr @ name` I can't see how to make it consistent with the `(field: capture)` case, the same with other binary
* `expr @ ``name`` ` I think this is more surprising, as it's used for 2 different puproses in quotes and in names


### Credits

[@krux02](https://github.com/krux02/) and [@andreaferretti](https://github.com/andreaferretti) are authors of the original nim pattern matching libs:

* @krux02 's [ast-pattern-matching](https://github.com/krux02/ast-pattern-matching)
* @andreaferretti 's [patty](https://github.com/andreaferretti/patty)

I took inspiration from their libraries and discussions (An early version of this dsl was even a PR to @krux02 's lib).

Thanks to [@mratsim](https://github.com/mratsim) for giving me the `@name` idea with one of his [github comments on possible nim pattern matching syntax](https://github.com/nim-lang/Nim/issues/8649#issuecomment-413318800), I initially had way more inconsistent notation in mind.
