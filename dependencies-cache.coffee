_ = require('lodash')
path = require('path')

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

    if tree.value.sourceRelativePath? and tree.relativePath isnt tree.value.sourceRelativePath
      @treeCache[tree.value.sourceRelativePath] = tree

  dependencyListForFile: (relativePath) ->
    if @listCache[relativePath]?
      @listCache[relativePath]
    else
      tree = @dependencyTreeForFile(relativePath)
      @listCache[relativePath] = tree.listOfAllDependencies()

  allStoredPaths: ->
    # Hmm, "stored" is kinda confusing... why only the relativePaths and not the sourcePaths too?
    # (for precompiled files that change extensions)
    _.unique (tree.relativePath for file, tree of @treeCache)

  anyPathsWithPrefix: (prefix) ->
    _.unique (file for file, tree of @treeCache when file.indexOf(prefix) is 0)

  debugPrint: (callback) ->
    console.log 'Dependencies cache\n'

    for file, tree of @treeCache
      tree.debugPrint(callback)
      console.log ''

  clearAll: ->
    @treeCache = {}
    @listCache = {}


{ convertFromPreprocessorExtension, extractExtension, resolveDirAndPath } = require('bender-broccoli-utils')


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

  listOfAllResolvedDependencyPaths: (relativePath, options={}) ->
    options.relative ?= false

    depTree = @dependencyTreeForFile(relativePath)
    return undefined unless depTree?

    deps = []
    addedDeps = {}

    depTree.traverse (node, visitChildren) ->
      visitChildren()
      ext = extractExtension(node.value.relativePath)
      extensionsToCheck = [ext]

      if node.value.relativePath != node.value.sourceRelativePath
        originalExtension = extractExtension node.value.sourceRelativePath,
          filename: node.parent?.relativePath

        extensionsToCheck.push originalExtension

      # Also look up the dep in the original directory it came from (just in
      # case it has been removed from the tree at some point)
      # loadPaths = [].concat(options.loadPaths).concat([node.value.srcDir])

      [resolvedDir, resolvedPath] = resolveDirAndPath node.value.relativePath,
        loadPaths: options.loadPaths
        extensionsToCheck: extensionsToCheck

        # Relative paths are already resolved by this point
        allowRelativeLookupWithoutPrefix: false

      if options.relative is true
        resolvedPath = resolvedPath
      else
        resolvedPath = path.join resolvedDir, resolvedPath

      if not addedDeps[resolvedPath]?
        deps.push resolvedPath
        addedDeps[resolvedPath] = true

    deps


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


  # Try super methods with out without preprocessor conversion

  wrappedMethods = [
    'hasFile'
    'dependencyTreeForFile'
    'dependencyListForFile'
  ]

  for methodName in wrappedMethods
    do (methodName) ->
      PreprocessorAwareDepenenciesCache::[methodName] = (relativePath) ->
        result = DependenciesCache::[methodName].call(this, relativePath)
        return result if result

        processedPath = @convertFromPreprocessorExtension(relativePath)

        if processedPath != relativePath
          DependenciesCache::[methodName].call(this, processedPath)
        else
          result






module.exports = PreprocessorAwareDepenenciesCache




