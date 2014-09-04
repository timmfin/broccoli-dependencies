{ extractExtension, convertFromPrepressorExtension } = require('./utils')

class Node
  constructor: (@value, options = {}) ->
    { @children } = options
    @children ?= []

  pushChildValue: (childValue) ->
    @children.push new RequireTreeNode(childValue)

  pushChildNode: (childNode) ->
    @children.push childNode

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
  createGetter @, 'filepath', -> @value

  listOfAllRequiredDependencies: (formatValue) ->
    formatValue ?= (v) -> v

    @allValues().map (depPath) =>
      formatValue depPath

  allRequiredDependenciesAsHTML: (formatValue) ->
    formatValue ?= (v) -> v
    dependenciesHTMLContent = []

    @traverse (node, visitChildren) =>
      val = formatValue(node.value)

      dependenciesHTMLContent.push @preIncludeComment(node, val) if node.children.length > 0

      visitChildren()

      dependenciesHTMLContent.push @htmlToIncludeDep(node, val)
      dependenciesHTMLContent.push @postIncludeComment(node, val) if node.children.length > 0

    dependenciesHTMLContent.join('\n').replace(/\n\n\n/g, '\n\n').replace(/^\n/, '')

  preIncludeComment: (node, formattedValue) ->
    "\n<!-- From #{formattedValue} -->"

  postIncludeComment: (node, formattedValue) ->
    "<!-- End #{formattedValue} -->\n"

  htmlToIncludeDep: (node, formattedValue) ->
    val = convertFromPrepressorExtension formattedValue, node.parent?.value
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

#   nodesFromArray = (arr) ->
#     arr.map (val) ->
#       new RequireTreeNode val

#   root = new RequireTreeNode 'root'
#   root.children = nodesFromArray [1...5]

#   root.children[0].children = nodesFromArray [6]
#   root.children[2].children = nodesFromArray [7...10]
#   root.children[2].children[1].children = nodesFromArray [11...13]
#   root.children[3].children = nodesFromArray [14...15]

#   console.log "root"
#   console.log util.inspect root, { depth: 10 }
#   root.debugPrint()

#   console.log "root.allValuesViaPrefix()", root.allValuesViaPrefix()
#   console.log "root.allValuesViaPostfix()", root.allValuesViaPostfix()
#   console.log "root.allValues()", root.allValues()

# test()
