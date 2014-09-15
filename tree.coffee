{ extractExtension, convertFromPrepressorExtension } = require('./utils')

class Node
  constructor: (@value, options = {}) ->
    { @children, @parent } = options
    @children ?= []

  pushChildValue: (childValues...) ->
    for childValue in childValues
      @children.push new RequireTreeNode(childValue),
        parent: this

  pushChildNode: (childNodes...) ->
    for childNode in childNodes
      childNode.parent = this
      @children.push childNode

  # Push aliases (since plural and singular are same impl)
  Node::pushChildValues = Node::pushChildValue
  Node::pushChildNodes = Node::pushChildNode

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
    RequireTreeNode.visitNode @, callback

  # Helper to collect all values via postfix traversal
  allValuesViaPostfix: ->
    values = []

    @traverse (node, visitChildren) ->
      visitChildren()
      values.push node.value

    values

  # Make `allValues` an alias for `allValuesViaPostfix`
  Node::allValues = Node::allValuesViaPostfix

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
    if node.children?.length
      visitChildren = ->
        for child in node.children
          RequireTreeNode.visitNode child, callback, depth + 1

    visitChildren ?= ->

    callback node, visitChildren, depth

  # New tree helper
  @createTree: (rootValue, values = []) ->
    children = values.map (val) -> new RequireTreeNode val
    new RequireTreeNode rootValue, { children: children }


createGetter = (klass, prop, get) ->
  Object.defineProperty klass, prop, {get, configurable: yes}


class RequireTreeNode extends Node
  createGetter @::, 'relativePath', -> @value.relativePath
  createGetter @::, 'originalAbsolutePath', -> @value.originalAbsolutePath

  listOfAllOriginalAbsoluteDependencies: ->
    deps = []

    @traverse (node, visitChildren) ->
      visitChildren()
      deps.push node.originalAbsolutePath

    deps

  listOfAllFinalizedRequiredDependencies: (formatValue) ->
    formatValue ?= (v) -> v
    deps = []

    @traverse (node, visitChildren) ->
      visitChildren()
      deps.push formatValue(convertFromPrepressorExtension(node.relativePath, node.parent?.relativePath))

    deps

  allRequiredDependenciesAsHTML: (formatValue) ->
    formatValue ?= (v) -> v
    dependenciesHTMLContent = []

    @traverse (node, visitChildren) =>
      val = formatValue(node.relativePath)

      dependenciesHTMLContent.push @_preIncludeComment(node, val) if node.children.length > 0

      visitChildren()

      dependenciesHTMLContent.push @_htmlToIncludeDep(node, val)
      dependenciesHTMLContent.push @_postIncludeComment(node, val) if node.children.length > 0

    dependenciesHTMLContent.join('\n').replace(/\n\n\n/g, '\n\n').replace(/^\n/, '')

  _preIncludeComment: (node, formattedValue) ->
    extra = ''
    extra = "(total files: #{node.size()})" if node.isRoot()

    "\n<!-- From #{formattedValue} #{extra} -->"

  _postIncludeComment: (node, formattedValue) ->
    "<!-- End #{formattedValue} -->\n"

  _htmlToIncludeDep: (node, formattedValue) ->
    val = convertFromPrepressorExtension formattedValue, node.parent?.relativePath
    val = "/#{val}" unless val[0] is '/'

    ext = extractExtension val

    if ext is 'js'
      """<script src="#{val}" type="text/javascript"></script>"""
    else if ext is 'css'
      """<link href="#{val}" rel="stylesheet" type="text/css" />"""
    else
      throw new Error "Can't create HTML element for unkown file type: #{formattedValue}"




module.exports = RequireTreeNode



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
