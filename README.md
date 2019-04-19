[![Build Status (Travis)](https://img.shields.io/travis/alehander42/gara/master.svg "build status")](https://travis-ci.org/alehander42/gara)

# gara

A nim macro-based pattern matching library.

### DSL

A library that provides a `match` macro which can be used as a pattern matching construct.

A `matches` macro which returns true if a value is matched.

A `maybeMatches` macro which returns an `Option[tuple]` of the matched "variables".


```nim
var rectangles = @[Rectangle(a: 0, b: 2), Rectangle(a: 4, b: 4), Rectangle(a: 4, b: 4), Rectangle(a: 4, b: 4)]

match(rectangles):
  @[]:
    fail()
  @[_, *(a: 4, b: 4) @others]: # (a: 4, b: 4) is a shorthand for `TypeName(field: value)`, see the next examples
    check(others == a[1 .. ^1]) # we match the rest, because they all match subpattern
  _:
    fail()
```

It's still experimental, there are some bugs left and the design of the DSL might still change depending on feedback of the community. For now it's a personal project, but I'd love if other people would join as contributors. It's inspired by @andreaferretti 's [patty](https://github.com/andreaferretti/patty) and @krux02 's [ast-pattern-matching](https://github.com/krux02/ast-pattern-matching) (and more stuff, there is a credits section!)


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
* support for recognizing other types as variant
* if guards
* unification
* matches expression
* option matching

### Rationale


Goals:

* Ability to generate code with zero overhead compared to manually written if/case/for equivalents
* Expressive and flexible syntax for patterns and extensible hooks
* Nice error reporting and pretty understandable generated code

The goals are ordered by priority.

Speed is very important: the goal is to be able to use matching everywhere where you'd use a complicated `if`/`case`.
If there are cases, when we're slower:

This should be considered a bug.

or

This is a limitation of the library: which is not cool.

Currently not every feature is optimized well(there are some blockers, and some features are still experimental).


The library is supposed to be extensible: please take a look at the unpackers section. For example we already implement the option matching with a `Some` unpacker.

I have a plan about the error reporting part: basically with several hooks inside the current code we should be able to produce
good messages. My plan API is

```nim
matchDebug(a): # generates an error message describing the comparisons we had and raises it if we hit unimplemented else

# or

lastMatchError() # if we detect this call, we generate an error message: we don't do it by default to not slow down the code
```

With some discipline we can generate pretty readable code from our macro.
This would be also beneficial for the end user, as we can map his invocation with the generated code and help him
see the problem easily.

There are 3 cases:

* The user had a logical error in his patterns: easily seen with the generated code
* The user used a pattern in an unexpected way: this way he can see how its expansion differs from his expectation
* Our patterns worked incorrectly: the user can issue a bug



### Values

Just test for equality with the value. Works also if you pass an existing variable instead of 2. For now you can't just pass various expressions tho (2 + 2), as I want to reserve syntax for the patterns

```nim
let a = 2

match(a):
  2:
    echo "2"
  _:
    echo "no 2"
```

### Types

The library tests with `is`

```nim
match(a):
  Rectangle: # matches Rectangle(a: 0), Rectangle(a: 2, b: 4)
    echo "rectangle"
  _:
    echo "other"
```

### Objects

We have a shorthand syntax for objects. You can type only the fields, and then we check only them: this is a good idea because usually
you know the type of the object that you are passing, so there is rarely ambiguity.
Of course you can still add the type if you want. You can use this for tuples too.

You can pass just some of the fields!

```nim
var rectangle = Rectangle(a: 0, b: 0)

match(rectangle):
  (a: 0, b: 0): # matches Rectangle(a: 0, b: 0)
    echo "ok"
  Rectangle(a: -2): # matches Rectangle(a: -2) (a: -2, e: 4)
    echo "weird"
  _:
    echo 0
```

### Subpatterns

You can match subpatterns.

```nim
var a = A(b: B(c: 0, e: 2))
match(a):
  A(b: B(c: 0)):
    echo "ok"
  _:
    echo "fail"
```

### Capturing

We capture with `@name` for all our usecases: wsubpatterns and values.
You write `stuff @name` which shouldn't be ambigious in general(please read the answers and questions section)

```nim
match(a):
  C(e: E(f: @f) @e): # matches C(e: E(f: 0)) and creates local variables f = 0 and e = E(..)
    echo e
    echo f
  _:
    echo "fail"
```

### Variants

We recognize when you do `enumLabel(..)` and we match variants then. That's very nice if you are threating them as abstract data types.

```nim
match(a):
  Merge(original: @original, other: @other):
    echo original
  Normal(message: @message):
    echo message
  _:
    echo a
```

### Wildcards

You can use `_` as a wildcard, it always succeeds. It's also used as `otherwise`.

```nim
match(a):
  @[_]: # matches any value
    echo a
  _:
    echo "nope"
```

### seq

```nim
match(a):
  @[4, 5]: # matches @[4, 5]
    echo "ok"
  _:
    echo "no"
```

### Many elements in seq

You can match repeated properties

```nim
var rectangles = @[e, e, Rectangle(a: 0)]
match(a):
  @[_, _, *(a: @list)]: # creates a local variable list which collects the a fields in the matches elements : @[0]
    echo list
  _:
    echo @[]
```

Here we match the elements after 1 and collect their a fields. You can also just `@name` the whole subpattern: it should be always a seq.
We use `allIt` for the test, but in a case like this, we optimize it out, as it is always true(we just load values).

### Unpackers

We can have unpackers for types: you define `proc unpack(t: Type): T` for your type.
The powerful thing is, `T` can be anything that has a len and `[int]`(we will add a concept for that later, but it covers seq, tuple).
For example we do this for Rectangle

```nim
proc unpack(rectangle: Rectangle): seq[int] =
  @[rectangle.a, rectangle.b]
```

Of course we are lucky here, but you can do transformations for more complicated cases.

When you do this, you can use the unpacked values like `Type(value, value)` .
We even recognize the enum case, so you can do it for variants too.

we also have function unpackers: `proc name(t: Type): T`. This way you can have many unpackers for the same type. This is useful , especially if a builtin type already has a default unpacker, and you need a custom one.
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
  data(name: "academy"): # matches data(email) with (name: "academy")
    echo email
  tokens(@[_, _, _, _, @token]): # matches tokens(email)
    echo token
```

(I got the idea for the email example from @andreaferretti's patty)

### Support for types as variants

Sometimes a type acts like a variant, but isn't defined like one: you can teach the library to do it.
It uses internally `eKind` to get the kind field of a variant, so you just need to override it

```nim
proc eKind*(a: A): AKind =
  a.stuff
```

### If guards

```nim
match(a);
  (b: @e) and e == 4: # generates local variable e and checks e
    echo e
  _:
    echo -1
```

We can add `or` too: does it make sense?

### Unification

inspired by @andreaferretti's patty ideas

```nim
let a = @[0, 0]
match(a):
  @[@x, @x]: # creates a local variable x only if both values are equal
    echo "equal"
  _:
    echo "not"
```

We check if all the subvalues are equal: that wasn't very easy to implement

### Match expressions

In general, `match` can be used as an expression:

```nim
let a = 2

let s = match(a):
  2:
    "it's a 2"
  _:
    "it's not a 2"
```

The `matches` macro allows to match against a single expression:
it returns a boolean value which is `true` when it matches the value.

```nim
if a.matches((b: 2, c: 4)):
  echo 0

```

You can also have captures with `maybeMatches`: it returns an `Option[tuple]`.

```nim
let c = a.maybeMatches((a: @a, b: @b))
if c.isSome:
  echo c.a
  echo c.b
```


### Plan

* error reporting
* fixes

### Name

gara means a train station in bulgarian. why a train station? I am travelling with trains these days, and I like bulgarian words.

### Questions and answers

**I don't like @name : it's bizarre and surprising for users**

I like it, but I'd welcome ideas for a better syntax! Please, first check this list:

* `expr @ name` I can't see how to make it consistent with the `(field: capture)` case, the same with other binary
* `expr @ ``name`` ` I think this is more surprising, as it's used for 2 different puproses in quotes and in names

**It's not type safe**

I want to leave all the type checking to the Nim compiler. The library translates your patterns to Nim code, so the only problem should be that sometimes it might be hard to debug why something is failing: I'll try to improve that with error messages.

**It is too complicated**

I like to think it is relatively simple: I've tried to limit new syntax and to optimize it for variants, so e.g. in `name(..)` we first check if name is enum, then type, then we assume it might be an unpacker. In the beginning I even had `~enum` syntax for matching variants, but it seemed crazy.
Otherwise a lot of custom or new functionality should be doable with unpackers or with a bit upgraded unpackers, please check them out

FAITH

### Credits
[@krux02](https://github.com/krux02/) and [@andreaferretti](https://github.com/andreaferretti) are authors of the original nim pattern matching libs:

* @krux02 's [ast-pattern-matching](https://github.com/krux02/ast-pattern-matching)
* @andreaferretti 's [patty](https://github.com/andreaferretti/patty)

I took inspiration from their libraries and discussions (An early version of this dsl was even a PR to @krux02 's lib).

Thanks to [@mratsim](https://github.com/mratsim) for giving me the `@name` idea with one of his [github comments on possible nim pattern matching syntax](https://github.com/nim-lang/Nim/issues/8649#issuecomment-413318800), I initially had way more inconsistent notation in mind.

Thanks to [@narimiran](https://github.com/narimiran/) for giving design ideas and doc fixes!
