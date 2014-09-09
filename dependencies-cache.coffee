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

  storeDependencyTreeForFile: (relativePath, tree) ->
    @treeCache[relativePath] = tree

  dependencyListForFile: (relativePath) ->
    if @listCache[relativePath]?
      @listCache[relativePath]
    else
      tree = @treeCache[relativePath]
      @listCache[relativePath] = tree.listOfAllFinalizedRequiredDependencies()

  dependencyCountForFile: (relativePath) ->
    if @sizeCache[relativePath]?
      @sizeCache[relativePath]
    else
      tree = @treeCache[relativePath]
      @sizeCache[relativePath] = tree.size()

  debugPrint: ->
    console.log 'Directive dependencies cache\n'

    for file, tree of @treeCache
      tree.debugPrint()
      console.log ''


module.exports = DirectiveDependenciesCache




