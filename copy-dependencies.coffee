'use strict'

fs            = require('fs')
path          = require('path')
RSVP          = require('RSVP')
async         = require('async')
mkdirp        = require('mkdirp')
helpers       = require('broccoli-kitchen-sink-helpers')
pluralize     = require('pluralize')
walkSync      = require('walk-sync')
copyPreserve  = require('copy-dereference')
CachingWriter = require('broccoli-caching-writer')

{ compact: filterFalseValues, flatten, merge } = require('lodash')
{ stripBaseDirectory, resolveDirAndPath, extractExtension, Stopwatch } = require('bender-broccoli-utils')

{ EmptyTree } = require('./tree')


# Follows the dependency tree created by your configured resolvers (Sass, sprockets
# directives, jade, etc), and copies all of those dependencies into the broccoli
# "working dir" if they are not already there.
#
# This is necessary to ensure that any dependent files are included before the
# rest of the build steps.

class CopyDependenciesFilter extends CachingWriter

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CopyDependenciesFilter)
      return new CopyDependenciesFilter(inputTree, options)

    # CoreObject (used inside CachingWriter) doesn't like being called directly
    CachingWriter.prototype.init.call this, [inputTree], { filterFromCache: options.filterFromCache }

    @inputTree = inputTree
    @options = options

    { @dependencyCache } = @options

    # Ensure that only extensions that are possible dependencies can cause a rebuild
    # (only if `@filterFromCache.include` isn't already specified)
    if @filterFromCache.include.length is 0 and @options.extensions?
      @filterFromCache.include.push ///
          .*
          \.(?: #{@options.extensions.join('|')} )
          $
        ///


  # Max IO operations to allow in parallel (for async.mapLimit)
  MAX_PARALLEL: 100

  updateCache: (srcDirs, destDir) ->
    srcDir = srcDirs[0]

    @allRelativePathsToCopy = Object.create(null)
    @allResolvedPathsToCopy = Object.create(null)
    @otherFilesToCopy = Object.create(null)
    @allDirectoriesToCreate = Object.create(null)

    @numFilesProcessed = 0
    @numFilesWalked = 0

    stopwatch = Stopwatch().start()
    processStopwatch = null

    walkedMap = walkSync(srcDir)
    console.log "CopyDepsFilter walkSynctime: #{stopwatch.prettyOutSplit()}"

    walkedMap.map (relativePath) =>
      isDirectory = relativePath.slice(-1) == '/'
      outputPath  = @getDestFilePath(relativePath)
      destPath    = destDir + '/' + (outputPath or relativePath)

      shouldBeProcessed = @isIncludedPath(relativePath)

      # If this is a directory make sure that it exists in the destination.
      if isDirectory
        mkdirp.sync destPath
      else
        @numFilesWalked += 1

        # If this is a file we want to process (getDestFilePath checks if it matches
        # any of the `@options.extensions` configured)
        if outputPath and shouldBeProcessed
          @numFilesProcessed += 1
          processStopwatch = Stopwatch().start() unless processStopwatch
          @processFile(srcDir, destDir, relativePath)
          # console.log "   copy deps processFile lap: #{stopwatch.lap().prettyOutLastLap()}"

        # always copy across the source file, even if it shouldn't be processed for deps.
        @otherFilesToCopy[srcDir + '/' + relativePath] = destPath
        # copyPreserve.sync(srcDir + '/' + relativePath, destPath)


    # Actually do all the copies and dir creation asynchronously
    srcDestTuples = for src, dest of merge({}, @otherFilesToCopy, @allResolvedPathsToCopy)
      [src, dest]

    new RSVP.Promise (resolve, reject) =>

      # Using async, mainly so we don't need to allocate so many promises
      async.mapLimit Object.keys(@allDirectoriesToCreate), @MAX_PARALLEL, mkdirp, (err, results) =>
        reject(err) if err?

        copyPreserveWithTuple = ([src, dest], callback) ->
          copyPreserve src, dest, callback

        # async.mapSeries srcDestTuples, copyPreserveWithTuple, (err, results) =>
        async.mapLimit srcDestTuples, @MAX_PARALLEL, copyPreserveWithTuple, (err, results) =>
          reject(err) if err?

          numFilesCopied = Object.keys(@allRelativePathsToCopy).length

          console.log """
            CopyDepsFilter time: #{stopwatch.stop().prettyOut()}
              - #{numFilesCopied} files copied (#{(stopwatch.milliseconds()/numFilesCopied).toFixed(2)} ms/file)
              - #{@numFilesProcessed} files processed (#{(stopwatch.milliseconds()/@numFilesProcessed).toFixed(2)} ms/file)
              - #{@numFilesWalked} files walked (#{(stopwatch.milliseconds()/@numFilesWalked).toFixed(2)} ms/file)

          """

          resolve()





  isIncludedPath: (relativePath) ->
    return true if not @options.includedDirs?

    for includedDir in @options.includedDirs
      return true if relativePath.indexOf(includedDir) is 0

    false

  processFile: (srcDir, destDir, relativePath) ->
    { dependenciesToCopy, depTree } = @processDependenciesToCopy(relativePath, srcDir, destDir)

    # If this file had dependencies, copy them into our Broccoli output because
    # we will need to compile them (and copy the compiled output) later
    numDepsInTree = depTree.size() - 1

    if dependenciesToCopy.length > 0
      console.log "Copying all external dependencies from #{relativePath} (#{dependenciesToCopy.length} #{pluralize('file', dependenciesToCopy.length)} out of #{numDepsInTree} deps)"

      # Copy all the files needed, and create an array of all their relative paths (for later usage)
      for { resolvedDir, resolvedRelativePath } in dependenciesToCopy
        sourcePath = resolvedDir + '/' + resolvedRelativePath
        copyDestination = destDir + '/' + resolvedRelativePath

        @allDirectoriesToCreate[path.dirname(copyDestination)] = true
        @allResolvedPathsToCopy[sourcePath] = copyDestination

        # mkdirp.sync(path.dirname(copyDestination))
        # copyPreserve.sync(sourcePath, copyDestination)

        resolvedRelativePath

    # else if numDepsInTree > 0
    #   console.log "Found #{numDepsInTree} #{pluralize('deps', numDepsInTree)} for #{relativePath}, but #{if numDepsInTree is 1 then 'it' else 'all'} already #{if numDepsInTree is 1 then 'exists' else 'exist'} in the broccoli tree"

  processDependenciesToCopy: (relativePath, srcDir) ->
    baseDirs = [srcDir].concat(@passedLoadPaths())

    # TODO fail early if @passedLoadPaths is empty?

    depTree = @dependencyCache.dependencyTreeForFile(relativePath)

    if not depTree?
      {
        dependenciesToCopy: []
        depTree: EmptyTree
      }
    else
      allDependencyPaths = depTree.listOfAllDependencies
        ignoreSelf: true
        formatValue: (v) ->
          v.sourceRelativePath

      # Exclude paths that already exist in the srcDir or already have been copied
      dependenciesToCopyAsObjs = for p in allDependencyPaths
        extension = extractExtension(p)

        resolvedDeps = resolveDirAndPath p,
          filename: srcDir + '/' + relativePath
          loadPaths: baseDirs
          extensionsToCheck: @dependencyCache.allPossibleCompiledExtensionsFor(extension)
          allowMultipleResultsFromSameDirectory: true

        filteredResolvedDeps = for [resolvedDir, resolvedRelativePath] in resolvedDeps
          if resolvedDir isnt srcDir and not @allRelativePathsToCopy[resolvedRelativePath] and @options.filter?(resolvedRelativePath) isnt false
            @allRelativePathsToCopy[resolvedRelativePath] = true
            { resolvedDir, resolvedRelativePath }
          else
            undefined

        filteredResolvedDeps

      # Return all dependencies of this file _and_ only the files that we needed to copy
      {
        dependenciesToCopy: filterFalseValues(flatten(dependenciesToCopyAsObjs))
        depTree
      }

  getDestFilePath: (relativePath) ->
    if @options.extensions?.length > 0
      for ext in @options.extensions
        if relativePath.slice(-ext.length - 1) == '.' + ext
          return relativePath

      # Return undefined to ignore relativePath
      undefined
    else
      relativePath

  passedLoadPaths: ->
    # options.loadPaths might be a function (HACK?)
    @options.loadPaths?() ? @options.loadPaths ? []


module.exports = CopyDependenciesFilter
