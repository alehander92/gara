import unittest
import experiment, strformat, strutils, sequtils

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
    email: string

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

let repo = Repo(name: "NewDB", author: Author(name: "John John", email: "john@newdb.org"), commits: @[
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

    #
    # if a == 2:
    #   discard
    # else:
    #   fail

  test "Capturing":
    let a = 2

    match(a):
    of 2 @b:
      check(b == 2)
    else:
      fail()
    
    #
    # if a == 2:
    #   let tmp1 = a
    #   let b = tmp1
    #   check(b == 2)
    # else:
    #   fail()

  test "Object":
    let a = Rectangle(a: 2, b: 0)

    match(a):
    of (a: 4, b: 1):
      fail()
    of (a: 2, b: @b):
      check(b == 0)
    else:
      fail()

    #
    # if a.a == 4 and a.b == 1:
    #   fail()
    # elif a.a == 2 and true:
    #   let tmp1 = a.b
    #   let b = tmp1
    #   check(b == 0)

  test "Subpattern":
    let a = repo # look in beginning

    match(a):
    of (name: "New", commits: @[]):
      fail()
    of (name: @name, author: Author(name: "John John", email: @email), commits: @commits):
      check(name == "NewDB")
      check(email == "john@newdb.org")
    else:
      fail()

    # 
    # if a.name == "New" and a.commits == @[]:
    #   fail()
    # elif true and a.author is Author and a.author.name == "John John" and true and true:
    #   let tmp1 = a.name
    #   let name = tmp1
    #   let tmp2 = a.author.email
    #   let email = tmp2
    #   let tmp3 = a.commits
    #   let commits = tmp3
    #   check(name == "NewDB")
    #   check(email == "john@newdb.org")
    # else:
    #   fail()

  test "Sequence":
    let a = @[Rectangle(a: 2, b: 4), Rectangle(a: 4, b: 4), Rectangle(a: 4, b: 4)]

    match(a):
    of @[]:
      fail()
    of @[_, *(a: 4, b: 4) @others]:
      check(others == a[1 .. ^1])
    else:
      fail()

    # 
    # if a == @[]:
    #   fail()
    # elif a.len >= 1 and true and a[1 .. ^1].allIt(it.a == 4 and it.b == 4):
    #   let tmp1 = a[1 .. ^1]
    #   let others = tmp1
    #   check(others == a[1 .. ^1])
    # else:
    #   fail()
  
  test "Sequence subpattern":
    let a = @[Rectangle(a: 2, b: 4), Rectangle(a: 4, b: 0), Rectangle(a: 4, b: 4), Rectangle(a: 4, b: 4)]

    match(a):
    of @[]:
      fail()
    of @[_, _, *(a: @list)]:
      check(list == @[4, 4])
    else:
      fail()

    #
    # if a == @[]:
    #   fail()
    # elif a.len >= 1 and true and true: # notice: optimized
    #   let list = a[1 .. ^1].mapIt(it.a)
    #   check(list == @[4, 4])
    # else:
    #   fail()
