
class DependenciesCache
  constructor: ->
    @clearAll()

  hasFile: (relativePath) ->
    !!@treeCache[relativePath]

  dependencyTreeForFile: (relativePath) ->
    @treeCache[relativePath]

  storeDependencyTree: (tree) ->
    # Cache under both the source extension and processed extension
    @treeCache[tree.relativePath] = tree

    if tree.sourceRelativePath? and tree.relativePath isnt tree.sourceRelativePath
      @treeCache[tree.sourceRelativePath] = tree

  dependencyListForFile: (relativePath) ->
    if @listCache[relativePath]?
      @listCache[relativePath]
    else
      tree = @treeCache[relativePath]
      @listCache[relativePath] = tree.listOfAllDependencies()

  debugPrint: (callback) ->
    console.log 'Dependencies cache\n'

    for file, tree of @treeCache
      tree.debugPrint(callback)
      console.log ''

  clearAll: ->
    @treeCache = {}
    @listCache = {}


{ convertFromPreprocessorExtension } = require('bender-broccoli-utils')


# Ensure that dependendencies are accessesed/followed by the finalized
# extension, after any preprocessing
class PreprocessorAwareDepenenciesCache extends DependenciesCache

  constructor: (@options = {}) ->
    super

    # Override @options.preprocessorsByExtension to add/remove preprocessors
    @convertFromPreprocessorExtension = convertFromPreprocessorExtension.curry
      preprocessorsByExtension: @options.preprocessorsByExtension

  storeDependencyTree: (tree) ->
    @convertPreprocessorExtensionForNode tree
    super tree

  # Recurse a tree from the passed in node, changing the extention as we go.
  # Will stop recursing as soon as it hits a part of the tree that has already
  # been converted (sourceRelativePath is set).
  convertPreprocessorExtensionForNode: (node) ->
    if not node.value.sourceRelativePath?
      parentRelativePath = node.parent?.relativePath

      node.value.sourceRelativePath = node.value.relativePath
      node.value.relativePath = @convertFromPreprocessorExtension node.value.sourceRelativePath,
        parentFilename: parentRelativePath

      for child in node.children
        @convertPreprocessorExtensionForNode child






module.exports = PreprocessorAwareDepenenciesCache




