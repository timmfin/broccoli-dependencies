symlinkOrCopy  = require('symlink-or-copy')
CopyDependenciesFilter = require('./copy-dependencies')

class CopyProjectDependenciesFilter extends CopyDependenciesFilter

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CopyDependenciesFilter)
      return new CopyProjectDependenciesFilter(inputTree, options)

    super

  _listOfExternalDepsFromTree: (depTree) ->
    depTree.listOfAllDependenciesForType @typesToCopy,
      ignoreSelf: true
      ignorePrefix: @project.pathPrefix()  # Only get dependencies _outside_ of the current project
      formatValue: (v) ->
        v.sourceRelativePath

  # Hacky way to modify the hash for caching-writer
  keyForTree: (fullPath, initialRelativePath) ->
    # Wrap the whole recursive call chain of keyForTree in perf laps
    isTopLevelCall = initialRelativePath is undefined
    @stopwatch.lap() if isTopLevelCall

    key = super(fullPath, initialRelativePath)

    @stopwatch.lap() if isTopLevelCall

    # initialRelativePath is undefined the first time keysForTree is called, so
    # use that as a hook to add in more cache "keys" (another key for every file
    # dep from outside the project)

    if initialRelativePath is undefined
      allOutsideDepsAsRelativePaths = @dependencyCache.dependencyListForAllTreesWithPrefix(@project.pathPrefix(), { ignorePrefix: @project.pathPrefix() })

      allOutsideDepsAsTuples = []
      for relativeDepPath in allOutsideDepsAsRelativePaths.sort()
        allOutsideDepsAsTuples = allOutsideDepsAsTuples.concat @_cachedResolve(relativeDepPath)

      outsideDepChildrenKeys = for [depSourceDir, depRelativePath] in allOutsideDepsAsTuples
        super(depSourceDir + '/' + depRelativePath, depRelativePath)

      key.children = key.children.concat(outsideDepChildrenKeys)

      # Also, a lap for looking up cache key for external deps
      @stopwatch.lap()


    key


  # Override symlink/copy behavior since we can optimize since we know this is a project

  # Symlink all top-level directories in the input path (allows us to not need
  # to symlink _any_ files in `onVisitedFileInInputTree()`)
  onVisitedDirectory: (srcDir, relativePath, destDir) ->
    relativePathMinusSlash = relativePath.slice(0, relativePath.length - 1)
    isTopLevelDirectory = relativePathMinusSlash.split('/').length is 1

    if isTopLevelDirectory
      symlinkOrCopy.sync srcDir + '/' + relativePathMinusSlash, destDir + '/' + relativePathMinusSlash

  onVisitedFileInInputTree: (srcDir, relativePath, wasProcessed, destDir, outputPath) ->
    # Do nothing
    #
    # We don't need to symlink files that are processed, since we've already
    # symlinked all of the top-level directories in from the inputPath


module.exports = CopyProjectDependenciesFilter
