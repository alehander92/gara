import unittest
import gara, strformat, strutils, sequtils, options

type
  Rectangle = object
    a: int
    b: int

  Repo = ref object
    name: string
    author: Author
    commits: seq[Commit]

  Author = object
    name: string
    email: Email

  Email = object
    raw: string

  # just an example: nice for match
  CommitType = enum Normal, Merge, First, Fix
  
  Commit = ref object
    case t: CommitType:
    of Normal:
      diff: string # simplified
    of Merge:
      original: Commit
      other: Commit
    of First:
      code: string
    of Fix:
      fix: string
    message: string

let repo = Repo(name: "ExampleDB", author: Author(name: "Example Author", email: Email(raw: "example@exampledb.org")), commits: @[
              Commit(t: First, message: "First", code: "e:0"),
              Commit(t: Normal, message: "Normal", diff: "+e:2\n-e:0")])

suite "match":
  test "Simple check":
    let a = 2

    match(a):
    of 2:
      discard
    else:
      fail()

  test "Capturing":
    let a = 2

    match(a):
    of 2 @b:
      check(b == 2)
    else:
      fail()
    

  test "Object":
    let a = Rectangle(a: 2, b: 0)

    match(a):
    of (a: 4, b: 1):
      fail()
    of (a: 2, b: @b):
      check(b == 0)
    else:
      fail()

  test "Subpattern":
    let a = repo # look in beginning

    match(a):
    of (name: "New", commits: @[]):
      fail()
    of (name: @name, author: Author(name: "Example Author", email: @email), commits: @commits):
      check(name == "ExampleDB")
      check(email.raw == "example@exampledb.org")
    else:
      fail()

  test "Sequence":
    let a = @[Rectangle(a: 2, b: 4), Rectangle(a: 4, b: 4), Rectangle(a: 4, b: 4)]

    match(a):
    of @[]:
      fail()
    of @[_, *(a: 4, b: 4) @others]:
      check(others == a[1 .. ^1])
    else:
      fail()

  test "Sequence subpattern":
    let a = @[Rectangle(a: 2, b: 4), Rectangle(a: 4, b: 0), Rectangle(a: 4, b: 4), Rectangle(a: 4, b: 4)]

    match(a):
    of @[]:
      fail()
    of @[_, _, *(a: @list)]:
      check(list == @[4, 4])
    else:
      fail()

  test "Variant":
    let a = ~Commit.Normal(message: "e", diff: "z")

    match(a):
    of Merge(original: @original, other: @other):
      fail()
    of Normal(message: @message):
      check(message == "e")
    else:
      fail()

  test "Custom unpackers":
    let email = repo.author.email

    proc data(email: Email): tuple[name: string, domain: string] =
      let words = email.raw.split('@', 1)
      (name: words[0], domain: words[1])

    proc tokens(email: Email): seq[string] =
      # work for js slow
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
      fail()
    of tokens(@[_, _, _, _, @token]):
      check(token == "org")

  test "if":
    let b = @[4, 0]

    match(b):
    of @[_, @t] and t mod 2 == 0:
      check(t == 0)
    else:
      fail()

  test "unification":
    let b = @["nim", "nim", "c++"]

    match(b):
    of @[@x, @x, @x]:
      fail()
    of @[@x, @x, _]:
      check(x == "nim")
    else:
      fail()

  test "option":
    let a = some[int](3)

    match(a):
    of Some(@i):
      check(i == 3)
    else:
      fail()

suite "matches":
  test "bool":
    let a = Rectangle(a: 0, b: 0)

    if a.matches((b: 0)):
      check(true)
    else:
      fail()

  test "option":
    let a = Rectangle(a: 0, b: 0)

    let c = a.maybeMatches((a: @a, b: @b))
    check(c.isSome)
    let g = c.get
    check(g.a == 0)
    check(g.b == 0)


suite "kind":
  test "dsl":
    var commit = ~Commit.Normal(message: "e", diff: "z")
    check(commit.message == "e")

    commit = ~Commit.Merge(original: commit, other: commit)
    check(commit.original.message == "e")



