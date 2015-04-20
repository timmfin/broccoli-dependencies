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

  dependencyListForFile: (relativePath, options = undefined) ->
    # For now, don't try to cache calls with specific options (like ignoreSelf or formatValue)
    if @listCache[relativePath]? and options is undefined
      @listCache[relativePath]
    else
      tree = @dependencyTreeForFile(relativePath)
      @listCache[relativePath] = tree.listOfAllDependencies(options)

  allStoredPaths: ->
    # Hmm, "stored" is kinda confusing... why only the relativePaths and not the sourcePaths too?
    # (for precompiled files that change extensions)
    _.unique (tree.relativePath for file, tree of @treeCache)

  anyPathsWithPrefix: (prefix) ->
    @pathPrefixCache[prefix] ?= _.unique (file for file, tree of @treeCache when file.indexOf(prefix) is 0)

  allTreesWithPrefix: (prefix) ->
    _.unique (tree for file, tree of @treeCache when file.indexOf(prefix) is 0)

  debugPrint: (callback) ->
    console.log 'Dependencies cache\n'

    callback ?= (n) -> n.sourceRelativePath

    for file, tree of @treeCache

      # Skip the "relativePath alias" for files that have different sourceRelativePaths
      continue if tree.value.sourceRelativePath? and tree.value.sourceRelativePath != file

      tree.debugPrint(callback)
      console.log ''

  clearAll: ->
    @treeCache = {}
    @clearSecondaryCaches()

  # All the secondardy caches that are based on the treeCache (cleared between builds)
  clearSecondaryCaches: ->
    @listCache = {}
    @pathPrefixCache = {}


{ convertFromPreprocessorExtension, extractExtension, resolveDirAndPath } = require('bender-broccoli-utils')


# Ensure that dependendencies are accessesed/followed by the finalized
# extension, after any preprocessing
class PreprocessorAwareDepenenciesCache extends DependenciesCache

  constructor: (@options = {}) ->
    super

    # A bit ghetto (function instead of saved var?)
    @preprocessorsByExtensionInverted = @_invertPreprocessorsByExtensionMap(@options.preprocessorsByExtension)

    # Override @options.preprocessorsByExtension to add/remove preprocessors
    @convertFromPreprocessorExtension = convertFromPreprocessorExtension.curry
      preprocessorsByExtension: @options.preprocessorsByExtension

  storeDependencyTree: (tree) ->
    @convertPreprocessorExtensionForNode tree
    super tree

  listOfAllResolvedDependencyPaths: (relativePath, options={}) ->
    options.relative ?= false

    depTree = @dependencyTreeForFile(relativePath)

    if depTree?
      @_allResolvedDepsFromTree depTree, options
    else
      undefined

  _allResolvedDepsFromTree: (depTree, options={}) ->
    deps = []
    addedDeps = {}

    depTree.traverse (node, visitChildren, depth) ->
      visitChildren()
      return if depth is 0 and options.ignoreSelf

      ext = extractExtension(node.value.relativePath)
      extensionsToCheck = [ext]

      if node.value.relativePath != node.value.sourceRelativePath
        originalExtension = extractExtension node.value.sourceRelativePath,
          filename: node.parent?.relativePath

        extensionsToCheck.push originalExtension

      # Also look up the dep in the original directory it came from (just in
      # case it has been removed from the tree at some point)
      # loadPaths = [].concat(options.loadPaths).concat([node.value.srcDir])

      [resolvedDir, resolvedRelativePath] = resolveDirAndPath node.value.relativePath,
        loadPaths: options.loadPaths
        extensionsToCheck: extensionsToCheck

        # Relative paths are already resolved by this point
        allowRelativeLookupWithoutPrefix: false

      if options.relativePlusDirObject is true
        toAdd = { resolvedDir, resolvedRelativePath }
        key = path.join resolvedDir, resolvedRelativePath
      else if options.relative is true
        toAdd = key = resolvedRelativePath
      else
        toAdd = key = path.join resolvedDir, resolvedRelativePath

      if not addedDeps[key]?
        deps.push toAdd
        addedDeps[key] = true

    deps

  listOfAllResolvedDependencyPathsMulti: (relativePaths, options={}) ->
    disconnectedTreeSet = []
    allResolvedDeps = []

    # Gather up the "disconnected" depTrees
    for relativePath in relativePaths
      newDepTree = @dependencyTreeForFile(relativePath)
      disconnectedTreeSet = @_mergeIntoTreeSet(disconnectedTreeSet, newDepTree) if newDepTree?

    # Then resolve all the depTree's to a list of files
    allResolvedDeps = for depTree in disconnectedTreeSet
      @_allResolvedDepsFromTree(depTree, options)

    _.flatten allResolvedDeps, false


  # Helper to add to and maintain a set of disconnected trees. Really should be
  # a TreeSet type with set like methods
  _mergeIntoTreeSet: (treeSet, newTree) ->
    return unless newTree?

    if treeSet.length is 0
      return [newTree]
    else
      # First, check if the new tree is contained inside any existing tree
      # (and if so, exit... no need to add to the set)
      for existingTree in treeSet
        return treeSet if existingTree.hasDescendent(newTree)

      # Then check the opposite, if the new tree contains any existing trees
      # (and if so, remove that existing tree from the set)
      treesToRemove = []

      for existingTree in treeSet
        treesToRemove.push(existingTree) if existingTree.hasAncestor(newTree)

      return _.difference(treeSet, treesToRemove)


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


  _invertPreprocessorsByExtensionMap: (preprocessorsByExtension) ->
    result = Object.create(null)

    for origExt, subMap of preprocessorsByExtension
      for processedExt in Object.keys(subMap)
        result[processedExt] ?= Object.create(null)
        result[processedExt][origExt] = true

    result

  # Helpers

  allPossiblePreprocessorExtensionsFor: (ext) ->

    # Trim leading dot if provided
    ext = ext[1..] if ext?[0] is '.'

    if @options.preprocessorsByExtension?[ext]?
      Object.keys(@options.preprocessorsByExtension[ext]).concat([ext])
    else
      [ext]

  allPossibleCompiledExtensionsFor: (ext) ->

    # Trim leading dot if provided
    ext = ext[1..] if ext?[0] is '.'

    if @preprocessorsByExtensionInverted?[ext]?
      Object.keys(@preprocessorsByExtensionInverted[ext]).concat([ext])
    else
      [ext]

  # Try super methods with out without preprocessor conversion

  wrappedMethods = [
    'hasFile'
    'dependencyTreeForFile'
    'dependencyListForFile'
  ]

  for methodName in wrappedMethods
    do (methodName) ->
      PreprocessorAwareDepenenciesCache::[methodName] = (relativePath, otherArgs...) ->
        result = DependenciesCache::[methodName].call(this, relativePath, otherArgs...)
        return result if result

        processedPath = @convertFromPreprocessorExtension(relativePath)

        if processedPath != relativePath
          DependenciesCache::[methodName].call(this, processedPath, otherArgs...)
        else
          result







module.exports = PreprocessorAwareDepenenciesCache




