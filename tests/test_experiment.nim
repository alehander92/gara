import unittest
import experiment, strformat, strutils, sequtils

type
  Rectangle = object
    a: int
    b: int


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

