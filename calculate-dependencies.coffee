'use strict'

walkSync  = require('walk-sync')
{ Stopwatch } = require('bender-broccoli-utils')

MultiResolver = require('./multi-resolver')


# A no-op filter used to run through a tree a build dependencies according to
# passed in resolvers config.

class CalculateDependenciesFilter

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CalculateDependenciesFilter)
      return new CalculateDependenciesFilter(inputTree, options)

    @inputTree = inputTree
    @options = options

    @multiResolver = new MultiResolver options
    @extensions = @multiResolver.allResolverExtensions()

  read: (readTree) ->
    readTree(@inputTree).then (srcDir) =>
      stopwatch = new Stopwatch().start()

      # Ensure that we re-build dependency trees for every re-build (and other
      # per-run caches)
      #
      # TODO skip calculating dependencies and re-use previously cached trees
      # if available and nothing has changed (useful?)
      @multiResolver.dependencyCache?.clearAll()

      previousTopLevelDir = depTreesInTopLevelDir = currentTopLevelDir = null

      walkSync(srcDir).map (relativePath) =>
        isDirectory = relativePath.slice(-1) == '/'
        isTopLevelDirectory = isDirectory and relativePath.indexOf('/') is relativePath.length - 1
        hasRelevantExtension = @hasRelevantExtension(relativePath)
        shouldBeProcessed = @isIncludedPath(relativePath)

        # If this is a file we want to process calculate the tree
        if not isDirectory and hasRelevantExtension and shouldBeProcessed
          depTree = @buildDepTreeFor(relativePath, srcDir)
          depTreesInTopLevelDir++
          # console.log "Calculated depTree for #{relativePath}"

        else if isTopLevelDirectory
          # Reset top-level dir counter
          previousTopLevelDir = currentTopLevelDir

          if previousTopLevelDir and depTreesInTopLevelDir > 0
            console.log "Built #{depTreesInTopLevelDir} dependency trees inside #{previousTopLevelDir}"

          depTreesInTopLevelDir = 0
          currentTopLevelDir = relativePath

      console.log "Took #{stopwatch.stop().prettyOut()} to calculate dependencies"

      # Always return the input, since this is a no-op filter
      srcDir

  cleanup: ->
    # None needed


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
