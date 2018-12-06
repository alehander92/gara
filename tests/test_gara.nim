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
      2:
        discard
      _:
        fail()

  test "Capturing":
    let a = 2

    match(a):
      2 @b:
        check(b == 2)
      _:
        fail()


  test "Object":
    let a = Rectangle(a: 2, b: 0)

    match(a):
      (a: 4, b: 1):
        fail()
      (a: 2, b: @b):
        check(b == 0)
      _:
        fail()

  test "Subpattern":
    let a = repo # look in beginning

    match(a):
      (name: "New", commits: @[]):
        fail()
      (name: @name, author: Author(name: "Example Author", email: @email), commits: @commits):
        check(name == "ExampleDB")
        check(email.raw == "example@exampledb.org")
      _:
        fail()

  test "Sequence":
    let a = @[Rectangle(a: 2, b: 4), Rectangle(a: 4, b: 4), Rectangle(a: 4, b: 4)]

    match(a):
      @[]:
        fail()
      @[_, *(a: 4, b: 4) @others]:
        check(others == a[1 .. ^1])
      _:
        fail()

    # _ is always true, (a: 4, b: 4) didn't match element 2

    # _ is alway.. a.a was 4, but a.b wasn't 4 => not a match



  test "Sequence subpattern":
    let a = @[Rectangle(a: 2, b: 4), Rectangle(a: 4, b: 0), Rectangle(a: 4, b: 4), Rectangle(a: 4, b: 4)]

    match(a):
      @[]:
        fail()
      @[_, _, *(a: @list)]:
        check(list == @[4, 4])
      _:
        fail()

  test "Variant":
    let a = ~Commit.Normal(message: "e", diff: "z")

    match(a):
      Merge(original: @original, other: @other):
        fail()
      Normal(message: @message):
        check(message == "e")
      _:
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
      data(name: "academy"):
        fail()
      tokens(@[_, _, _, _, @token]):
        check(token == "org")

  test "if":
    let b = @[4, 0]

    match(b):
      @[_, @t] and t mod 2 == 0:
        check(t == 0)
      _:
        fail()

  test "unification":
    let b = @["nim", "nim", "c++"]

    match(b):
      @[@x, @x, @x]:
        fail()
      @[@x, @x, _]:
        check(x == "nim")
      _:
        fail()

  test "option":
    let a = some[int](3)

    match(a):
      Some(@i):
        check(i == 3)
      _:
        fail()


  test "nameless tuple":
    let a = ("a", "b")

    match a:
      ("a",):
        fail() # check the arity first
      ("a", "c"):
        fail()
      ("a", @c):
        check(c == "b")
      _:
        fail()

  test "ref":
    type
      Node = ref object
        name: string
        children: seq[Node]

    let node = Node(name: "2")

    match node:
      (name: @name):
        check(name == "2")
      _:
        fail()

    let node2: Node = nil

    match node2:
      (name: "4"):
        fail()
      Node(name: "4"):
        fail()
      _:
        check(true)

  test "string":
    let a = "a"

    match a:
      "a":
        check(true)
      _:
        fail()

  test "weird integers":
    let a = 4

    match a:
      4'i8:
        check(true)
      _:
        fail()

  test "dot access":
    let a = Rectangle(b: 4)

    match a:
      (b: a.b):
        check(true)
      _:
        fail()

  test "arrays":
    let a = [1, 2, 3, 4]

    match a:
      [1, @a, 3, @b, 5]:
        fail()
      [1, @a, 3, @b]:
        check(a == 2 and b == 4)
      _:
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


  # TODO
  # test "set":
  #  let a = {'a', 'b'}

  #  match(a):
  #    {'b', @y}:
  #    check(y == 'a')
  #    _:
  #    fail()



suite "kind":
  test "dsl":
    var commit = ~Commit.Normal(message: "e", diff: "z")
    check(commit.message == "e")

    commit = ~Commit.Merge(original: commit, other: commit)
    check(commit.original.message == "e")



