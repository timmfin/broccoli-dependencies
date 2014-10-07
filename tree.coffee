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
      console.log "#{indent}#{if depth is 0 then 'root: ' else ''}#{formatValue(node.value)}"
      visitChildren()

  # Helper for traverse
  @visitNode: (node, callback, depth = 0) ->
    children = node.children

    if children?.length
      visitChildren = =>
        for child in children
          @visitNode child, callback, depth + 1

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

  sizeForType: (type) ->
    count = 0

    @traverseByType type, (node, visitChildren) ->
      count++
      visitChildren()

    count

  traverseByType: (type, callback) ->
    if type?
      @constructor.visitNodeForType @, type, callback
    else
      @traverse callback

  debugPrintForType: (type, formatValue) ->
    formatValue = ((v) -> v) unless formatValue?

    @traverseByType type, (node, visitChildren, depth) ->
      indent = ('  ' for [0...depth]).join('')
      console.log "#{indent}#{if depth is 0 then 'root: ' else ''}#{formatValue(node.value)}"
      visitChildren()

  @visitNodeForType: (node, type, callback, depth = 0) ->
    children = node.childrenByType?[type]

    if children?.length
      visitChildren = =>
        for child in children
          @visitNodeForType child, type, callback, depth + 1

    visitChildren ?= ->

    callback node, visitChildren, depth


# Extends and customizes TreeNode for depdnency-specific info
class DependencyNode extends TypedChildrenNode
  createGetter @::, 'relativePath', -> @value.relativePath
  createGetter @::, 'srcDir', -> @value.srcDir
  createGetter @::, 'originalAbsolutePath', -> @value.originalAbsolutePath

  listOfAllOriginalAbsoluteDependencies: ->
    deps = []

    @traverse (node, visitChildren) ->
      visitChildren()
      deps.push node.originalAbsolutePath

    deps

  listOfAllDependenciesForType: (type, formatValue) ->
    formatValue ?= (v) -> v
    deps = []

    @traverseByType type, (node, visitChildren) ->
      visitChildren()
      deps.push formatValue(node.relativePath)

    deps






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
