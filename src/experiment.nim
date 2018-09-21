# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import macros, strformat, strutils, sequtils, tables, algorithm, sets

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

var assignNames {.compileTime.} = @[initSet[string]()]

proc genAssign*(name: NimNode, a: NimNode): NimNode =
  let text = name.repr
  if assignNames.len == 0 or assignNames.allIt(text notin it):
    result = quote:
      let `name` = `a`; true
    if assignNames.len == 0:
      assignNames.add(initSet[string]())
    echo assignNames[^1]
    var e = assignNames[^1]
    e.incl(text)
    assignNames[^1] = e
  else:
    result = quote:
      `name` == `a`

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
    let tmpInit = genAssign(tmp, input)
    result[1].add(tmpInit)
    let testInit = tmpInit
    let r = result[0]
    result[0] = quote:
      `r` and `testInit`

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

var tmpCount {.compileTime.} = 0

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
  #echo "LOAD:", pattern.lisprepr
  let inputNode = quote do: `input`[`i` .. ^1]
  let (itTest, itNode) = load(manyPattern, ident("it"), shape, capture)

  if not itTest.isNil:
    for section in itTest:
      echo section.lisprepr
      # let name = code
      # generates let name = inputNode.mapIt(code)
      if section.kind == nnkLetSection:
        for child in section:
          let childName = child[0]
          let childCode = child[2]
          let b = quote do: `inputNode`.mapIt(`childCode`)
          # we forget childName
          var a = assignNames[^1]
          a.excl(childName.repr)
          assignNames[^1] = a
          let assign = genAssign(childName, b)
          newCode.add(assign)
            

  if itTest.repr == "true":
    test = itTest # optimized
  else:
    test = quote:
      `inputNode`.allIt(`itTest`)
  if newCode.len != 0:
    test = quote:
      `test` and `newCode`
  if not name.isNil:
    # slow, we need views for zero overhead: https://github.com/nim-lang/Nim/issues/5753  
    let assign = genAssign(name, inputNode)
    test = quote:
      `test` and `assign`
  result = (test, newCode, 0)

# FAITH
proc load(pattern: NimNode, input: NimNode, shape: Shape, capture: int = -1): (NimNode, NimNode) =
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
    let newInit = genAssign(newName, input)
    newCode.add(newInit)
    let testInit = quote:
      `newInit`
    test = quote do: `test` and `testInit`
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
        test = genAssign(name, input)

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
    # - number
    of "-":
      test = quote do: `input` == `pattern`
      newCode = emptyStmtList()
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
    let condition2 = quote:
      `typ` is enum
    
    let condition1 = quote:
      `typ` is type

    var args = nnkPar.newTree()
    for i, arg in pattern:
      if i > 0:
        args.add(arg)
    tmpCount += 1
    var tmp = tmpCount
      
    var branchNames = initSet[string]()
    # we only let new variables here, and then add them at the end, so you don't stop letting them in other
    assignNames.add(initSet[string]())
    var (test0, code0) = loadUnpacker(call, args, input, shape, tmpCount)
    branchNames.incl(assignNames.pop())

    # Type(fields), it checks if the type is matched and then it checks the fields
    # generates
    #
    #
    # input is Type and fields match # test
    #
    # no code
    #
    # 
    var test1 = quote do: `input` is `typ`
    var fields = nnkPar.newTree()
    for i, field in pattern:
      if i > 0:
        fields.add(field)
    assignNames.add(initSet[string]())
    let (fieldTest, fieldCode) = load(fields, input, shape, capture)
    branchNames.incl(assignNames.pop())
    test1 = quote do: `test1` and `fieldTest`
    var code1 = fieldCode
    while code1.kind == nnkStmtList and code1.len == 1:
      code1 = code1[0]
    if code1.len == 0:
      code1 = quote:
        discard

    # enum
    let kind = pattern[0]
    var test2 = quote:
      `input`.eKind == `kind`
    var code2 = emptyStmtList()
    var children = nnkPar.newTree()
    newCode = emptyStmtList()
    for i, field in pattern:
      if i > 0:
        children.add(field)
    assignNames.add(initSet[string]())
    let (childrenTest, childrenCode) = load(children, input, shape, capture)
    branchNames.incl(assignNames.pop())
    test2 = quote do: `test2` and `childrenTest`
    code2.add(childrenCode)
    
    if assignNames.len == 0:
      assignNames.add(initSet[string]())
    var e = assignNames[^1]
    e.incl(branchNames)
    assignNames[^1] = e
    
    # :)
    test = quote:
      when `condition2`: 
        `test2`
      elif `condition1`:
        `test1`
      else:
        `test0`
    
    newCode = quote:
      when `condition2`:
        `code2`
      elif `condition1`:
        `code1`
      else:
        `code0`
    newCode = nnkStmtList.newTree(newCode)
  of nnkCall:
    
    # call(args), if call is an object, calls unpack(object) if it exists otherwise calls the function and checks if it matches args
    # generates
    #
    #
    # unpack(call) check args or unpacker(call, args) # test
    #
    #
    let call = pattern[0]
    
    let condition = quote:
      not compiles(unpack(`input`))

    var test0: NimNode
    var newCode0: NimNode
    tmpCount += 1
    var tmp = tmpCount
    if pattern.len > 1:
      var args = pattern[1]
      (test0, newCode0) = loadUnpacker(call, args, input, shape, tmp)
    else:
      test0 = quote do: false
      newCode0 = quote:
        discard

    let length = newLit(pattern.len - 1)
    var tmpNode = ident("tmp" & $tmp)
    var header = quote:
      let `tmpNode` = unpack(`input`)
    
    var test1 = quote do:`tmpNode`.len == `length`
    var newCode1 = emptyStmtList()

    for j in 0 ..< pattern.len - 1:
      let argInput = quote do: `tmpNode`[`j`]
      let (argTest, argCode) = load(pattern[j + 1], argInput, shape, capture)
      test1 = quote do: `test1` and `argTest`
      newCode1.add(argCode)
      
    for i, code in @[newCode0, newCode1]:
      var c = code
      while c.kind == nnkStmtList and c.len == 1:
        c = c[0]
      if c.kind == nnkStmtList and c.len == 0:
        c = quote:
          discard
      if i == 0:
        newCode0 = c
      else:
        newCode1 = c

    test1 = quote:
      `header`
      (when `call` is enum: `input`.eKind == `call` else: `input` is `call`) and `test1`

    test = quote:
      when `condition`:
        `test0`
      else:
        `test1`
    
    newCode = quote:
      when `condition`:
        `newCode0`
      else:
        `newCode1`

    newCode = nnkStmtList.newTree(newCode)

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
      test = quote:
        when `pattern` is enum:
          `input`.eKind == `pattern`
        elif `pattern` is type:
          `input` is `pattern`
        else:
          `input` == `pattern`
      newCode = emptyStmtList()
  of nnkInfix:
    let operator = pattern[0].repr
    case operator:
    of "and":
      var (a, b) = load(pattern[1], input, shape, capture)
      let condition = pattern[2]
      test = quote:
        `a` and `condition`
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
    assignNames = @[]
    var (test, newCode) = load(pattern, input, shape, capture)
    newCode = code #.add(code)
    result = (nnkElIfBranch.newTree(test, newCode), false)
  of nnkElse:
    result = (nnkElse.newTree(branch[0]), true)
  else:
    error "expected of or else"
  echo result[0].repr
  echo "#"

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
    echo result.repr
    echo "##"


export sequtils

