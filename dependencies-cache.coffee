
class DependenciesCache
  constructor: ->
    @treeCache = {}
    @listCache = {}

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


{ convertFromPrepressorExtension } = require('./utils')

# Ensure that dependendencies are accessesed/followed by the finalized
# extension, after any preprocessing
class PreprocessorAwareDepenenciesCache extends DependenciesCache
  storeDependencyTree: (tree) ->
    if not tree.value.sourceRelativePath?
      parentRelativePath = tree.parent?.relativePath

      tree.value.sourceRelativePath = tree.value.relativePath
      tree.value.relativePath = convertFromPrepressorExtension tree.value.sourceRelativePath,
        parentFilename: parentRelativePath

    super tree





module.exports = PreprocessorAwareDepenenciesCache




