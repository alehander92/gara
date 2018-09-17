# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import macros, strformat, strutils, sequtils, tables, algorithm

proc add*(x, y: int): int =
  ## Adds two files together.
  return x + y

type
  ShapeKind = enum MAtom, MSeq, MSet, MTable, MObject

  Shape = ref object
    case kind: ShapeKind:
    of MAtom:
      name: string
    of MSeq, MSet:
      element: Shape
    of MTable:
      key: Shape
      value: Shape
    of MObject:
      fields: Table[string, Shape]

  ExperimentError* = object of Exception

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


# detects *pattern and *pattern @name
proc isManyPattern(node: NimNode): bool =
  node.kind == nnkPrefix and node[0].repr == "*" #or
    #node.kind == nnkCommand and node[0].isManyPattern and node[1].kind == nnkPrefix and node[1][0].repr == "@"

var tmpCount = 0

proc load(pattern: NimNode, input: NimNode, shape: Shape, capture: int = -1): (NimNode, NimNode)
proc loadUnpacker(call: NimNode, pattern: NimNode, input: NimNode, shape: Shape, tmp: int): (NimNode, NimNode) =
  let tmpNode = ident("tmp" & $tmp)
  var (test, newCode) = load(pattern, tmpNode, shape, -1)
  let firstCode = quote:
    let `tmpNode` = `call`(`input`)
  test = quote:
    `firstCode`
    `test`
  result = (test, newCode)

# generates for *pattern and *pattern @name
proc loadManyPattern(pattern: NimNode, input: NimNode, i: int, shape: Shape, capture: int = -1): (NimNode, NimNode, int) =
  var manyPattern: NimNode
  var name: NimNode
  var test: NimNode
  var newCode = emptyStmtList()
  if pattern[1].kind != nnkCommand:
    manyPattern = pattern[1]
  else:
    manyPattern = pattern[1][0]
    name = pattern[1][1][1]
  echo "LOAD:", pattern.lisprepr
  let inputNode = quote do: `input`[`i` .. ^1]
  let (itTest, itNode) = load(manyPattern, ident("it"), shape, capture)
  if not itNode.isNil:
    for section in itNode:
      # let name = code
      # generates let name = inputNode.mapIt(code)
      if section.kind == nnkLetSection:
        for child in section:
          echo child.lisprepr
          let childName = child[0]
          let childCode = child[2]
          let assign = quote:
            let `childName` = `inputNode`.mapIt(`childCode`)
          newCode.add(assign)

  if itTest.repr == "true":
    test = itTest # optimized
  else:
    test = quote:
      `inputNode`.allIt(`itTest`)
  if not name.isNil:
    # slow, we need views for zero overhead: https://github.com/nim-lang/Nim/issues/5753  
    let assign = quote:
      let `name` = `inputNode`
    newCode.add(assign)
  result = (test, newCode, 0)

# FAITH
proc load(pattern: NimNode, input: NimNode, shape: Shape, capture: int = -1): (NimNode, NimNode) =
  echo &"PATTERN {pattern.lisprepr}"
  var test: NimNode
  var newCode: NimNode
  case pattern.kind:
  of nnkIntLit, nnkStrLit:
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
        # @list a sequence match: it matches its elements
        # generates:
        #
        #
        # if input.len >= a and elements # test
        # 
        # capturing code # code
        #

        if pattern[1].len == 0:
          test = quote do: `input` == `pattern`
          newCode = emptyStmtList()
        else:
          var min = 0
          var t: NimNode
          newCode = emptyStmtList()
          for i, element in pattern[1]:
            let elementNode = quote do: `input`[`i`]
            var elementTest: NimNode
            var elementCode: NimNode
            if not element.isManyPattern():
              (elementTest, elementCode) = load(element, elementNode, shape, capture)
              min += 1
            else:
              if i != pattern[1].len - 1:
                error "pattern expected * last"
              var elementMin = 0
              # Thank God!
              (elementTest, elementCode, elementMin) = loadManyPattern(element, input, i, shape, capture)
              # min is different for * and +
              # we generate sequtils allIt
              min += elementMin
            if t.isNil:
              t = elementTest
            else:
              t = quote do: `t` and `elementTest`
            newCode.add(elementCode)
          let minTest =  quote do: `input`.len >= `min`
          test = quote do: `minTest` and `t`
            
      else:
        error "pattern not supported"
    of "~":
      # ~kind(object) a variant, generates field matches and uses eKind for now
      let kind = pattern[1][0]
      test = quote:
        `input`.eKind == `kind`
      newCode = emptyStmtList()
      var children = nnkPar.newTree()
      for i, field in pattern[1]:
        if i > 0:
          children.add(field)
      let (childrenTest, childrenCode) = load(children, input, shape, capture)
      test = quote do: `test` and `childrenTest`
      newCode.add(childrenCode)
    else:
      error "pattern not supported"
  of nnkObjConstr:
    # call(args), it calls the function and checks if it matches args
    # generates
    #
    #
    # unpacker(call, pattern) # test
    #
    # captured code # code
    #
    #
    let typ = pattern[0]
    let call = typ
    let condition = quote:
      `typ` is type

    var args = nnkPar.newTree()
    for i, arg in pattern:
      if i > 0:
        args.add(arg)
    tmpCount += 1
    var tmp = tmpCount
    var (leftTest, leftCode) = loadUnpacker(call, args, input, shape, tmpCount)

    # Type(fields), it checks if the type is matched and then it checks the fields
    # generates
    #
    #
    # input is Type and fields match # test
    #
    # no code
    #
    # 
    var rightTest = quote do: `input` is `typ`
    var fields = nnkPar.newTree()
    for i, field in pattern:
      if i > 0:
        fields.add(field)
    let (fieldTest, fieldCode) = load(fields, input, shape, capture)
    test = quote do: `test` and `fieldTest`
    var rightCode = fieldCode
    while rightCode.kind == nnkStmtList and rightCode.len == 1:
      rightCode = rightCode[0]
    if rightCode.len == 0:
      rightCode = quote:
        discard
    # :)
    test = quote:
      when not `condition`: `leftTest` else: `rightTest`
    newCode = quote:
      when not `condition`: `leftCode` else: `rightCode`
    newCode = nnkStmtList.newTree(newCode)
  of nnkCall:
    # call(args), it calls the function and checks if it matches args
    # generates
    #
    #
    # unpacker(call, args) # test
    #
    #
    let call = pattern[0]
    var args = pattern[1]
    tmpCount += 1
    var tmp = tmpCount
    (test, newCode) = loadUnpacker(call, args, input, shape, tmp)
  of nnkIdent:
    case pattern.repr:
    of "_":
      # wildcard: it matches everything
      # generates
      #
      #
      # true # test
      #
      # no code
      #
      test = quote do: true
      newCode = emptyStmtList()
    else:
      error "pattern not supported"
  else:
    error "pattern not supported"
  (test, newCode)

proc matchBranch(branch: NimNode, input: NimNode, shape: Shape, capture: int = -1): (NimNode, bool) =
  case branch.kind:
  of nnkOfBranch:
    let pattern = branch[0]
    let code = branch[1]
    var (test, newCode) = load(pattern, input, shape, capture)
    newCode.add(code)
    result = (nnkElIfBranch.newTree(test, newCode), false)
    echo &"PATTERN {result.repr}"
  of nnkElse:
    result = (nnkElse.newTree(branch[0]), true)
  else:
    error "expected of or else"

proc loadKindField(t: NimNode): NimNode =
  var u = t
  if u.kind == nnkBracketExpr and u[0].repr == "typeDesc":
    u = u[1].getType
  if u.kind == nnkBracketExpr and u[0].repr == "ref":
    u = u[1].getType
  for field in u[2]:
    if field.kind == nnkRecCase:
      return field[0]
  u

macro eKind*(a: typed): untyped =
  let kindField = loadKindField(a.getType)
  result = quote:
    `a`.`kindField`

macro initVariant*(variant: typed, kind: typed, fields: untyped): untyped =
  let kindField = loadKindField(variant.getType)
  result = quote:
    `variant`(`kindField`: `kind`)
  for field in fields:
    result.add(field)

macro `~`*(node: untyped): untyped =
  var fields: seq[NimNode]
  for i, field in node:
    if i > 0:
      fields.add(field)
  let a = node[0][0]
  let b = node[0][1]
  result = quote:
    initVariant(`a`, `b`, `fields`)

macro match*(input: typed, branches: varargs[untyped]): untyped =
  if branches.len == 0:
    error "invalid match"
  else:
    let t = input.getType
    let shape = loadShape(input)
    echo &"MATCH: {shape}"

    result = nnkIfStmt.newTree()
    var hasElse = false
    for branch in branches:
      let (b, isElse) = matchBranch(branch, input, shape)
      if isElse:
        hasElse = true
      if not b.isNil:
        result.add(b)
    if not hasElse:
      var exception = quote:
        raise newException(ExperimentError, "nothing matched in pattern expression")
      exception = nnkElse.newTree(exception)
      result.add(exception)
    echo &"MATCH:\n {result.repr}"

    let test = quote do: a == 2
    let code = quote do: echo a

    let i = nnkIfStmt.newTree(nnkElifBranch.newTree(test, code))

    echo i.lisprepr



export sequtils

