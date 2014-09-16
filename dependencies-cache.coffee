debugCtr = 1

class DirectiveDependenciesCache
  constructor: ->
    @treeCache = {}
    @listCache = {}
    @sizeCache = {}

    @debugInstance = debugCtr++

  hasFile: (relativePath) ->
    !!@treeCache[relativePath]

  dependencyTreeForFile: (relativePath) ->
    @treeCache[relativePath]

  storeDependencyTree: (tree) ->
    # Cache under both the source extension and processed extension
    @treeCache[tree.relativePath] = tree
    @treeCache[tree.sourceRelativePath] = tree if tree.relativePath isnt tree.sourceRelativePath

  dependencyListForFile: (relativePath) ->
    if @listCache[relativePath]?
      @listCache[relativePath]
    else
      tree = @treeCache[relativePath]
      @listCache[relativePath] = tree.listOfAllFinalizedRequiredDependencies()

  debugPrint: (callback) ->
    console.log 'Directive dependencies cache\n'

    for file, tree of @treeCache
      tree.debugPrint(callback)
      console.log ''


module.exports = DirectiveDependenciesCache




