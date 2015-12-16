
{ extractExtension } = require('bender-broccoli-utils')


# A basic implementation of a tree
class TreeNode
  constructor: (@value, options = {}) ->
    { @children, @parent } = options
    @children ?= []

    for child in @children
      @children.parent = this

  pushChildValue: (childValues...) ->
    for childValue in childValues
      @children.push new @constrcutor(childValue),
        parent: this

  pushChildNode: (childNodes...) ->
    for childNode in childNodes
      childNode.parent = this
      @children.push childNode

  clearChildren: ->
    @children = []

  # Push aliases (since plural and singular are same impl)
  TreeNode::pushChildValues = TreeNode::pushChildValue
  TreeNode::pushChildNodes = TreeNode::pushChildNode

  isRoot: ->
    not @parent?

  size: ->
    count = 0

    @traverse (node, visitChildren) ->
      count++
      visitChildren()

    count


  # Traverse the tree starting with this node. Example:
  #
  #  node.traverse (node, visitChildren) ->
  #    console.log "Bla: #{node.value}"
  #    visitChildren()
  #
  # So depending on the order you call `visitChildren` you
  # can traverse the tree via prefix or postfix traversal.
  traverse: (callback) ->
    @constructor.visitNode @, callback

  # Helper to collect all values via postfix traversal
  allValuesViaPostfix: ->
    values = []

    @traverse (node, visitChildren) ->
      visitChildren()
      values.push node.value

    values

  # Make `allValues` an alias for `allValuesViaPostfix`
  TreeNode::allValues = TreeNode::allValuesViaPostfix

  allValuesViaPrefix: ->
    values = []

    @traverse (node, visitChildren) ->
      values.push node.value
      visitChildren()

    values

  debugPrint: (formatValue) ->
    formatValue = ((v) -> v) unless formatValue?

    @traverse (node, visitChildren, depth) ->
      indent = ('  ' for [0...depth]).join('')
      formattedValue = formatValue(node.value, depth)

      if formattedValue isnt false
        console.log "#{indent}#{if depth is 0 then 'root: ' else ''}#{formattedValue}"
        visitChildren()

  hasDescendent: (otherTree) ->
    result = false

    @traverse (node, visitChildren) ->
      if node is otherTree
        result = true
      else
        visitChildren()

    result

  hasAncestor: (otherTree) ->
    otherTree.hasDescendent(this)

  # Helper for traverse
  @visitNode: (node, callback, depth = 0, visitedNodesSet = new Set) ->
    visitedNodesSet.add node
    children = node.children

    if children?.length
      visitChildren = =>
        for child in children
          if not visitedNodesSet.has(child)
            result = @visitNode child, callback, depth + 1, visitedNodesSet

            # Allow returning false to exit early
            return if result is false

    visitChildren ?= ->

    callback node, visitChildren, depth


  # New tree helper
  @createTree: (rootValue, values = []) ->
    children = values.map (val) -> new @ val
    new @ rootValue, { children: children }


createGetter = (klass, prop, get) ->
  Object.defineProperty klass, prop, {get, configurable: yes}


class TypedChildrenNode extends TreeNode

  pushTypedChildNode: (type, childNode) ->
    @childrenByType ?= {}
    @childrenByType[type] ?= []
    @childrenByType[type].push childNode

  childTypes: ->
    Object.keys(@childrenByType ? {})

  childrenForType: (type) ->
    @childrenByType?[type] ? []

  clearChildren: ->
    super()
    @childrenByType = []

  sizeForType: (type) ->
    count = 0

    @traverseByType type, (node, visitChildren) ->
      count++
      visitChildren()

    count

  traverseByType: (type, callback) ->
    if type?
      @constructor.visitNodeForTypes @, type, callback
    else
      @traverse callback

  debugPrintForType: (type, formatValue) ->
    formatValue = ((v) -> v) unless formatValue?

    @traverseByType type, (node, visitChildren, depth) ->
      indent = ('  ' for [0...depth]).join('')
      console.log "#{indent}#{if depth is 0 then 'root: ' else ''}#{formatValue(node.value)}"
      visitChildren()

  @visitNodeForTypes: (node, types, callback, depth = 0, visitedNodesSet = new Set) ->

    types = [types] if types? and not Array.isArray(types)

    visitedNodesSet.add node
    allChildren = []

    for type in types
      childrenForType = node.childrenByType?[type]
      allChildren = allChildren.concat(childrenForType) if childrenForType?

    if allChildren?.length
      visitChildren = =>
        for child in allChildren
          if not visitedNodesSet.has(child)
            result = @visitNodeForTypes child, types, callback, depth + 1, visitedNodesSet

            # Allow returning false to exit early
            return if result is false

    visitChildren ?= ->

    callback node, visitChildren, depth


# Extends and customizes TreeNode for dependency-specific info
class DependencyNode extends TypedChildrenNode
  createGetter @::, 'relativePath', -> @value.relativePath
  createGetter @::, 'srcDir', -> @value.srcDir
  createGetter @::, 'originalAbsolutePath', -> @value.originalAbsolutePath

  listOfAllOriginalAbsoluteDependencies: ->
    deps = []
    addedDeps = {}

    @traverse (node, visitChildren) ->
      visitChildren()

      if not addedDeps[node.originalAbsolutePath]?
        deps.push node.originalAbsolutePath
        addedDeps[node.originalAbsolutePath] = true

    deps

  listOfAllDependencies: (options) ->
    @listOfAllDependenciesForType undefined, options

  listOfAllDependenciesForType: (type, options = {}) ->
    formatValue = options.formatValue ? (v) -> v.relativePath
    deps = []
    addedDeps = {}

    @traverseByType type, (node, visitChildren, depth) ->
      visitChildren()

      shouldIgnoreSelf = options.ignoreSelf and depth is 0
      shouldIgnorePrefix = options.ignorePrefix and node.value.relativePath.indexOf(options.ignorePrefix) is 0

      if not shouldIgnoreSelf and not shouldIgnorePrefix
        if options.filter? and options.filter(node.value, node, depth) is false
          return false

        val = formatValue(node.value)

        if not addedDeps[val]?
          deps.push val
          addedDeps[val] = true

    deps

  @.EmptyTree = Object.freeze(new @())






module.exports = DependencyNode



# GHETTO TESTING
# test = ->
#   util = require('util')

#   root = new RequireTreeNode 'root'
#   root.pushChildValues [1...5]

#   root.children[0].pushChildValues [6]
#   root.children[2].pushChildValues [7...10]
#   root.children[2].children[1].pushChildValues [11...13]
#   root.children[3].pushChildValues [14...15]

#   console.log "root"
#   console.log util.inspect root, { depth: 10 }
#   root.debugPrint()

#   console.log "root.allValuesViaPrefix()", root.allValuesViaPrefix()
#   console.log "root.allValuesViaPostfix()", root.allValuesViaPostfix()
#   console.log "root.allValues()", root.allValues()

# test()
