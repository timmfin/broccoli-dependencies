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

    if @options.includedDirs? and not Array.isArray(@options.includedDirs)
      @options.includedDirs = [@options.includedDirs]

    if @options.excludedDirs? and not Array.isArray(@options.excludedDirs)
      @options.excludedDirs = [@options.excludedDirs]

  rebuild: ->

    # Ensure that we re-build list and prefix caches, even though we are
    # saving/re-using the tree cache
    @multiResolver.prepareForAnotherBuild()

    @previousTopLevelDir = @currentTopLevelDir = null
    @depTreesInTopLevelDir = 0
    @cachedFiles = Object.create(null)
    @stopwatch = new Stopwatch().start()

    NoOpFilter.prototype.rebuild.call(this).then (outputDir) =>
      @stopwatch.lap()  # Make sure to finish lap for last top level dir

      @logNumTreesForDirIfNeeded(@currentTopLevelDir, @depTreesInTopLevelDir)

      console.log "Calculated all file dependencies in #{@stopwatch.stop().prettyOut({ color: true })}"

      @multiResolver.ensureAllDependenciesFoundWereProcessed @cachedFiles,
        prefixesToLimitTo: @options.dontAutoRecurseWithin

      outputDir

  processFile: (srcDir, relativePath) ->
    @depTreesInTopLevelDir += 1
    topLevelDirForThisPath = relativePath.split(path.sep)[0]

    if @currentTopLevelDir isnt topLevelDirForThisPath
      @stopwatch.lap()  # Lap for all the files processed on the last top level dir

      @previousTopLevelDir = @currentTopLevelDir
      @currentTopLevelDir = topLevelDirForThisPath

      @logNumTreesForDirIfNeeded(@previousTopLevelDir, @depTreesInTopLevelDir)
      @depTreesInTopLevelDir = 0

    depTree = @buildDepTreeFor(relativePath, srcDir)

  onCachedFile: (srcDir, relativePath) ->
    @cachedFiles[relativePath] = true

  logNumTreesForDirIfNeeded: (dir, num) ->
    if dir and num > 0
      console.log "Built #{num} dependency trees inside #{dir} (in #{@stopwatch.prettyOutLastLap({ color: true })})"

  canProcessFile: (relativePath) ->
    @hasRelevantExtension(relativePath) and @isIncludedPath(relativePath) and not @isExcludedPath(relativePath)

  isIncludedPath: (relativePath) ->
    return true if not @options.includedDirs?

    for includedDir in @options.includedDirs
      return true if relativePath.indexOf(includedDir) is 0

    false

  isExcludedPath: (relativePath) ->
    return true if not @options.excludedDirs?

    for excludeDir in @options.excludedDirs
      return true if relativePath.indexOf(excludeDir) is 0

    false

  buildDepTreeFor: (relativePath, srcDir) ->
    depTree = @multiResolver.findDependencies relativePath, srcDir,
      dontAutoRecurseWithin: @options.dontAutoRecurseWithin

  hasRelevantExtension: (relativePath) ->
    for ext in @extensions
      if relativePath.slice(-ext.length - 1) == '.' + ext
        return true

    false


module.exports = CalculateDependenciesFilter
