# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import macros, strformat, strutils, sequtils, tables, algorithm

proc add*(x, y: int): int =
  ## Adds two files together.
  return x + y

type
  ShapeKind* = enum MAtom, MSeq, MSet, MTable, MObject

  Shape* = ref object
    case kind*: ShapeKind:
    of MAtom:
      name*: string
    of MSeq, MSet:
      element*: Shape
    of MTable:
      key*: Shape
      value*: Shape
    of MObject:
      fields*: Table[string, Shape]

proc text(shape: Shape, depth: int): string =
  let indent = repeat("  ",  depth)
  let base = case shape.kind:
    of MAtom:
      &"{shape.name}"
    else:
      &"shape"
  result = &"{indent}{base}"

proc `$`*(shape: Shape): string =
  text(shape, 0)

proc `==`*(l: Shape, r: Shape): bool =
  if l.kind != r.kind:
    return false
  case l.kind:
  of MAtom:
    l.name == r.name
  else:
    false

template emptyStmtList: NimNode =
  nnkStmtList.newTree()

proc atomTest(a: NimNode, input: NimNode, capture: int = -1): (NimNode, NimNode) =
  result[0] = quote do: `input` == `a`
  result[1] = emptyStmtList()
  if capture > -1:
    let tmp = ident("tmp" & $capture)
    let tmpInit = quote:
      let `tmp` = `input`
    result[1].add(tmpInit)

proc loadShape(input: NimNode): Shape =
  let t = input.getType
  case t.kind:
  of nnkSym:
    Shape(kind: MAtom, name: t.repr)
  else:
    Shape(kind: MSeq, element: nil)



var tmpCount = 0

# FAITH
proc load(pattern: NimNode, input: NimNode, shape: Shape, capture: int = -1): (NimNode, NimNode) =
  echo &"PATTERN {pattern.lisprepr}"
  var test: NimNode
  var newCode: NimNode
  case pattern.kind:
  of nnkIntLit:
    (test, newCode) = atomTest(pattern, input, capture)
  of nnkCommand:
    if pattern[1].kind != nnkPrefix or pattern[1][0].repr != "@":
      error "pattern not supported"
    elif pattern[1][1].kind != nnkIdent:
      error "pattern expects @name"
    tmpCount += 1
    let tmp = tmpCount
    (test, newCode) = load(pattern[0], input, shape, tmp)
    let newName = pattern[1][1]
    let tmpNode = ident("tmp" & $tmp)
    let newInit = quote do:
      let `newName` = `tmpNode`
    newCode.add(newInit)
  
  of nnkPar:
    # (a: c, b: d) a pattern that matches objects or tuples
    # generates:
    #
    #
    # input.a.matches(c) and input.b.matches(d) # test
    #
    # capturing code # code
    # code
    #
    var simple = true
    test = nil
    newCode = emptyStmtList()
    for i, element in pattern:
      if i == 0:
        simple = element.kind != nnkExprColonExpr
      else:
        if element.kind == nnkExprColonExpr:
          if simple:
            error "pattern unexpected :"
        else:
          if not simple:
            error "pattern expected :"
      if not simple:
        let left = element[0]
        let newInput = quote do: `input`.`left`
        let (elementTest, elementCode) = load(element[1], newInput, shape, capture)
        if test.isNil:
          test = elementTest
        else:
          test = quote do: `test` and `elementTest`
        newCode.add(elementCode)
      else:
        error "pattern not supported"
  of nnkPrefix:
    # @object or ~object
    # @name generates a capturing name, @list a seq match and ~object a variant match

    case pattern[0].repr:
    of "@":
      case pattern[1].kind:
      of nnkIdent:
        # @name a capturing name, it always returns true and only generates a capture
        # generates:
        #
        #
        # true # test
        #
        # capturing code # code
        # let name = input
        #
      
        let name = pattern[1]
        test = quote do: true
        newCode = quote:
          let `name` = `input`
      of nnkBracket:
        # @list a sequence match
        error "pattern not supported"
      else:
        error "pattern not supported"
    of "~":
      # ~kind(object) a variant
      error "pattern not supported"
    else:
      error "pattern not supported"
  else:
    error "pattern not supported"
  (test, newCode)

proc matchBranch(branch: NimNode, input: NimNode, shape: Shape, capture: int = -1): NimNode =
  case branch.kind:
  of nnkOfBranch:
    let pattern = branch[0]
    let code = branch[1]
    var (test, newCode) = load(pattern, input, shape, capture)
    newCode.add(code)
    result = nnkElIfBranch.newTree(test, newCode)
    echo &"PATTERN {result.repr}"
  of nnkElse:
    result = nnkElse.newTree(branch[0])
  else:
    error "expected of or else"

macro match*(input: typed, branches: varargs[untyped]): untyped =
  if branches.len == 0:
    error "invalid match"
  else:
    let t = input.getType
    let shape = loadShape(input)
    echo &"MATCH: {shape}"

    result = nnkIfStmt.newTree()
    for branch in branches:
      let b = matchBranch(branch, input, shape)
      if not b.isNil:
        result.add(b)

    echo &"MATCH:\n {result.repr}"

    let test = quote do: a == 2
    let code = quote do: echo a

    let i = nnkIfStmt.newTree(nnkElifBranch.newTree(test, code))

    echo i.lisprepr




