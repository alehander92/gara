import macros, strformat, strutils, sequtils, tables, algorithm, sets, options, typetraits

type
  ExperimentError* = object of Exception

  TypeKind* = enum TNormal, TEnum, TType, TRef

var assignNames {.compileTime.} = @[initSet[string]()]

var maybeVariables {.compileTime.}: seq[string] = @[]

proc genAssign*(name: NimNode, a: NimNode): NimNode =
  let text = name.repr
  if assignNames.len == 0 or assignNames.allIt(text notin it):
    result = quote:
      let `name` = `a`; true
    if assignNames.len == 0:
      assignNames.add(initSet[string]())
    # echo assignNames[^1]
    var e = assignNames[^1]
    e.incl(text)
    assignNames[^1] = e
  else:
    result = quote:
      `name` == `a`
  if not text.startsWith("tmp"): #TODO
    maybeVariables.add(text)

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

# detects *pattern and *pattern @name
proc isManyPattern(node: NimNode): bool =
  node.kind == nnkPrefix and node[0].repr == "*" #or
    #node.kind == nnkCommand and node[0].isManyPattern and node[1].kind == nnkPrefix and node[1][0].repr == "@"

var tmpCount {.compileTime.} = 0

proc load(pattern: NimNode, input: NimNode, capture: int = -1): (NimNode, NimNode)
proc loadUnpacker(call: NimNode, pattern: NimNode, input: NimNode, tmp: int): (NimNode, NimNode) =
  let tmpNode = ident("tmp" & $tmp)
  var (test, newCode) = load(pattern, tmpNode, -1)
  let firstCode = quote:
    let `tmpNode` = `call`(`input`)
  test = quote:
    `firstCode`
    `test`
  result = (test, newCode)

# generates for *pattern and *pattern @name
proc loadManyPattern(pattern: NimNode, input: NimNode, i: int, capture: int = -1): (NimNode, NimNode, int) =
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
  var (itTest, itNode) = load(manyPattern, ident("it"), capture)


  var newItTest = itTest

  if not itTest.isNil:
    for i, section in itTest:
      var l: NimNode = nil
      if section.kind == nnkInfix and section[2].kind == nnkLetSection:
        l = section[2]
      elif section.kind == nnkStmtList and section[0].kind == nnkLetSection:
        l = section[0]
      elif section.kind == nnkLetSection:
        l = section

      if not l.isNil:
        for child in l:
          let childName = child[0]
          let childCode = child[2]
          let b = quote do: `inputNode`.mapIt(`childCode`)
          # we forget childName
          var a = assignNames[^1]
          a.excl(childName.repr)
          assignNames[^1] = a
          let assign = genAssign(childName, b)
          newCode.add(assign)

      if section.kind == nnkInfix and section[2].kind == nnkLetSection:
        newItTest[i] = section[0]
      elif section.kind == nnkStmtList and section[0].kind == nnkLetSection:
        newItTest[i] = nnkStmtList.newTree()
        for j, child in section:
          if j > 0:
            newItTest[i].add(child)

  itTest = newItTest

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

proc loadList(pattern: NimNode, input: NimNode, capture: int = -1, isArray: bool = false): (NimNode, NimNode) =
  # sequence or array match: it matches its elements
  # generates:
  #
  #
  # if input.len >= a and elements # test
  #
  # capturing code # code
  #
  var test: NimNode
  var newCode: NimNode
  let elements = if pattern.kind == nnkBracket: pattern else: pattern[1]

  if elements.len == 0:
    test = quote do: `input` == `pattern`
    newCode = emptyStmtList()
  else:
    var min = 0
    var t: NimNode
    newCode = emptyStmtList()
    for i, element in elements:
      let elementNode = quote do: `input`[`i`]
      var elementTest: NimNode
      var elementCode: NimNode
      if not element.isManyPattern():
        (elementTest, elementCode) = load(element, elementNode, capture)
        min += 1
      else:
        if i != elements.len - 1:
          error "pattern expected * last"
        var elementMin = 0
        # Thank God!
        (elementTest, elementCode, elementMin) = loadManyPattern(element, input, i, capture)
        # min is different for * and +
        # we generate sequtils allIt
        min += elementMin
      if t.isNil:
        t = elementTest
      else:
        t = quote do: `t` and `elementTest`
      newCode.add(elementCode)
    let minTest =  quote do: `input`.len >= `min`
    if not isArray:
      test = quote do: `minTest` and `t`
    else:
      test = quote:
        when `minTest`:
          `t`
        else:
          false
      newCode = quote:
        when `minTest`:
          `newCode`

  result = (test, newCode)

# FAITH
proc load(pattern: NimNode, input: NimNode, capture: int = -1): (NimNode, NimNode) =
  var test: NimNode
  var newCode: NimNode

  case pattern.kind:
  of nnkIntLit, nnkInt8Lit,
    nnkInt16Lit, nnkInt32Lit, nnkInt64Lit, nnkUIntLit, nnkUInt8Lit,
    nnkUInt16Lit, nnkUInt32Lit, nnkUInt64Lit, nnkFloatLit,
    nnkFloat32Lit, nnkFloat64Lit, nnkFloat128Lit, nnkStrLit, nnkRStrLit,
    nnkTripleStrLit, nnkNilLit, nnkDotExpr:
    (test, newCode) = atomTest(pattern, input, capture)
  of nnkCommand:
    if pattern[1].kind != nnkPrefix or pattern[1][0].repr != "@":
      error "pattern not supported"
    elif pattern[1][1].kind != nnkIdent:
      error "pattern expects @name"
    tmpCount += 1
    let tmp = tmpCount
    (test, newCode) = load(pattern[0], input, tmp)
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
    test = quote do: not `input`.isNil2

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
        let (elementTest, elementCode) = load(element[1], newInput, capture)
        #if test.isNil:
        #   test = elementTest
        #else:
        test = quote do: `test` and `elementTest`
        newCode.add(elementCode)
      else:
        let newInput = quote do: `input`[`i`]
        let (elementTest, elementCode) = load(element, newInput, capture)
        #if test.isNil:
        #  test = elementTest
        #else:
        test = quote do: `test` and `elementTest`
        # newCode.add(elementCode)

  of nnkBracket:
    (test, newCode) = loadList(pattern, input, capture, isArray=true)

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
        (test, newCode) = loadList(pattern, input, capture)
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
      let (childrenTest, childrenCode) = load(children, input, capture)
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
    var (test0, code0) = loadUnpacker(call, args, input, tmpCount)
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
    let (fieldTest, fieldCode) = load(fields, input, capture)
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
    let (childrenTest, childrenCode) = load(children, input, capture)
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
      (test0, newCode0) = loadUnpacker(call, args, input, tmp)
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
      let (argTest, argCode) = load(pattern[j + 1], argInput, capture)
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
      var (a, b) = load(pattern[1], input, capture)
      let condition = pattern[2]
      test = quote:
        `a` and `condition`
      newCode = emptyStmtList()
    of "or":
      var (l0, l1) = load(pattern[1], input, capture)
      var (r0, r1) = load(pattern[2], input, capture)
      test = quote:
        `l0` or `r0`
      newCode = emptyStmtList()
    else:
      error "pattern not supported"
  of nnkTupleConstr:
    # (pattern,)
    #
    # generates
    #
    # input is tuple and input.type.arity == 1 and ..
    #

    let child = pattern[0]
    let newInput = quote do: `input`[0]
    let (childTest, childCode) = load(child, newInput, capture)

    test = quote:
      `input` is tuple and `input`.type.arity == 1 and `childTest`

    newCode = childCode
  else:
    error "pattern not supported"
  (test, newCode)

proc loadNodes(branch: NimNode): (NimNode, NimNode) =
  case branch.kind:
  of nnkCall:
    if branch.len == 2:
      result = (branch[0], branch[1])
    else:
      result[0] = nnkCall.newTree()
      for i, child in branch:
        if i < branch.len - 1:
          result[0].add(child)
      result[1] = branch[^1]
  of nnkCommand, nnkPrefix:
    result = (branch.kind.newTree(branch[0], branch[1]), branch[2])
  of nnkInfix:
    result = (branch.kind.newTree(branch[0], branch[1], branch[2]), branch[3])
  else:
    result = (nil, nil)

proc matchBranch(branch: NimNode, input: NimNode, capture: int = -1): (NimNode, bool) =
  case branch.kind:
  of nnkCall, nnkCommand, nnkPrefix, nnkInfix:
    # echo branch.treerepr
    let (pattern, code) = loadNodes(branch)
    if pattern.kind == nnkIdent and pattern.repr == "_":
      result = (nnkElse.newTree(branch[1]), true)
    else:
      # echo pattern.treerepr
      # echo code.treerepr
      assignNames = @[]
      var (test, newCode) = load(pattern, input, capture)
      if newCode.kind == nnkWhenStmt:
        let whenTest = newCode[0][0]
        newCode = quote:
          when `whenTest`:
            `code`
      else:
        newCode = code
      result = (nnkElIfBranch.newTree(test, newCode), false)
  else:
    # echo branch.treerepr
    error "expected pattern"
  # echo result[0].repr
  # echo "#"

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

proc isNil2*[T: not ref](t: T): bool =
  false

proc isNil2*[T: ref](t: T): bool =
  t.isNil


# Faith Lord!
proc Some*[T](a: Option[T]): T =
  a.get

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

macro matches*(input: untyped, pattern: untyped): untyped =
  let (test, newCode) = load(pattern, input, -1)
  result = test


macro maybeMatches*(input: untyped, pattern: untyped): untyped =
  maybeVariables = @[]
  let (test, newCode) = load(pattern, input, -1)
  result = emptyStmtList()
  let tupleInit = nnkPar.newTree()
  for name in maybeVariables:
    tupleInit.add(nnkExprColonExpr.newTree(ident(name), ident(name)))
  maybeVariables = @[]
  result = quote:
    block:
      let r = `test`
      var tmp: Option[(`tupleInit`).type]
      if r:
        tmp = some(`tupleInit`)
      else:
        tmp = none[(`tupleInit`).type]()
      tmp
  # echo result.repr

macro match*(input: typed, branches: varargs[untyped]): untyped =
  if branches.len == 0:
    error "invalid match"
  else:
    let t = input.getType

    result = nnkIfStmt.newTree()
    var hasElse = false
    for branch in branches[0]:
      let (b, isElse) = matchBranch(branch, input)
      if isElse:
        hasElse = true
      if not b.isNil:
        result.add(b)
    if not hasElse:
      var exception = quote:
        raise newException(ExperimentError, "nothing matched in pattern expression")
      exception = nnkElse.newTree(exception)
      result.add(exception)
    # echo result.repr
    # echo "##"


export sequtils, options, typetraits


