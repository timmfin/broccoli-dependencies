'use strict'

path = require('path')
walkSync  = require('walk-sync')
NoOpFilter = require('broccoli-noop-filter')
{ Stopwatch } = require('bender-broccoli-utils')

MultiResolver = require('./multi-resolver')


# A no-op filter used to run through a tree a build dependencies according to
# passed in resolvers config.

class CalculateDependenciesFilter extends NoOpFilter

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CalculateDependenciesFilter)
      return new CalculateDependenciesFilter(inputTree, options)

    super

    @inputTree = inputTree
    @options = options

    @multiResolver = new MultiResolver options
    @extensions = @multiResolver.allResolverExtensions()

  rebuild: ->
    console.log "In rebuild"

    # Ensure that we re-build dependency trees for every re-build (and other
    # per-run caches)
    #
    # TODO skip calculating dependencies and re-use previously cached trees
    # if available and nothing has changed (useful?)
    @multiResolver.dependencyCache?.clearAll()

    @previousTopLevelDir = @currentTopLevelDir = null
    @depTreesInTopLevelDir = 0
    stopwatch = new Stopwatch().start()

    NoOpFilter.prototype.rebuild.call(this).then (outputDir) =>
      @logNumTreesForDirIfNeeded(@currentTopLevelDir, @depTreesInTopLevelDir)

      console.log "Took #{stopwatch.stop().prettyOut()} to calculate dependencies"
      outputDir

  processFile: (srcDir, relativePath) ->
    depTree = @buildDepTreeFor(relativePath, srcDir)

    @depTreesInTopLevelDir += 1
    topLevelDirForThisPath = relativePath.split(path.sep)[0]

    if @currentTopLevelDir isnt topLevelDirForThisPath
      @previousTopLevelDir = @currentTopLevelDir
      @currentTopLevelDir = topLevelDirForThisPath

      @logNumTreesForDirIfNeeded(@previousTopLevelDir, @depTreesInTopLevelDir)
      @depTreesInTopLevelDir = 0

  logNumTreesForDirIfNeeded: (dir, num) ->
    if dir and num > 0
      console.log "Built #{num} dependency trees inside #{dir}"

  canProcessFile: (relativePath) ->
    @hasRelevantExtension(relativePath) and @isIncludedPath(relativePath)

  isIncludedPath: (relativePath) ->
    return true if not @options.includedDirs?

    for includedDir in @options.includedDirs
      return true if relativePath.indexOf(includedDir) is 0

    false

  buildDepTreeFor: (relativePath, srcDir) ->
    depTree = @multiResolver.findDependencies(relativePath, srcDir)

  hasRelevantExtension: (relativePath) ->
    for ext in @extensions
      if relativePath.slice(-ext.length - 1) == '.' + ext
        return true

    false


module.exports = CalculateDependenciesFilter
