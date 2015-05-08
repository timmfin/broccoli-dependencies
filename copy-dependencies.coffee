'use strict'

fs            = require('fs')
Set           = require('Set')
RSVP          = require('RSVP')
async         = require('async')
mkdirp        = require('mkdirp')
helpers       = require('broccoli-kitchen-sink-helpers')
pluralize     = require('pluralize')
walkSync      = require('walk-sync')
symlinkOrCopy = require('symlink-or-copy')
CachingWriter = require('broccoli-caching-writer')

{ dirname } = require('path')
{ compact: filterFalseValues, flatten, merge, reduce } = require('lodash')
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

    @options = options

    { @project, @dependencyCache, @benderContext } = @options

    # Ensure that only extensions that are possible dependencies can cause a rebuild
    # (only if `@filterFromCache.include` isn't already specified)
    if @filterFromCache.include.length is 0 and @options.extensions?
      @filterFromCache.include.push ///
          .*
          \.(?: #{@options.extensions.join('|')} )
          $
        ///

  rebuild: ->
    # Fresh cache for every build (cache used for generating hash, so can't only
    # be cleared in updateCache)
    @perBuildCache = Object.create(null)
    @perBuildCache.resolveCache = Object.create(null)
    @perBuildCache.depPathsAlreadyProcessed = Object.create(null)
    @perBuildCache.setOfExistingFiles = new Set

    @stopwatch = Stopwatch().start()

    super()

  updateCache: (srcDirs, destDir) ->
    srcDir = srcDirs[0]

    @allRelativePathsToCopy = Object.create(null)
    @allResolvedPathsToCopy = Object.create(null)
    @otherFilesToCopy = Object.create(null)
    @allDirectoriesToCreate = new Set

    @numFilesProcessed = 0
    @numFilesWalked = 0

    stopwatch = Stopwatch().start()
    processStopwatch = null

    walkedMap = walkSync(srcDir)

    walkedMap.map (relativePath) =>
      isDirectory = relativePath.slice(-1) == '/'
      outputPath  = @getDestFilePath(relativePath)
      destPath    = destDir + '/' + (outputPath or relativePath)

      shouldBeProcessed = @isIncludedPath(relativePath)

      # If this is a directory make sure that it exists in the destination.
      if isDirectory
        @allDirectoriesToCreate.add(destPath)
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


    # Batch up the copies and dir creation to the end (but still keeping sync
    # because I measured and it doesn't make a difference)

    for dirToCreate in @allDirectoriesToCreate.toArray()
      mkdirp.sync dirToCreate

    copyStopwatch = Stopwatch().start()

    for src, dest of merge({}, @otherFilesToCopy, @allResolvedPathsToCopy)
      symlinkOrCopy.sync src, dest

    numFilesCopied = Object.keys(@allRelativePathsToCopy).length

    # console.log """
    #   CopyDepsFilter time: #{@stopwatch.stop().prettyOut()}
    #     - Time before updateCache #{@stopwatch.prettyOutLastLap()}
    #     - Time to copy #{copyStopwatch.stop().prettyOut()}
    #     - #{numFilesCopied} files copied (#{(@stopwatch.milliseconds()/numFilesCopied).toFixed(2)} ms/file)
    #     - #{@numFilesProcessed} files processed (#{(@stopwatch.milliseconds()/@numFilesProcessed).toFixed(2)} ms/file)
    #     - #{@numFilesWalked} files walked (#{(@stopwatch.milliseconds()/@numFilesWalked).toFixed(2)} ms/file)

    # """

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
      # console.log "Copying all external dependencies from #{relativePath} (#{dependenciesToCopy.length} #{pluralize('file', dependenciesToCopy.length)} out of #{numDepsInTree} deps)"

      # Copy all the files needed, and create an array of all their relative paths (for later usage)
      for { resolvedDir, resolvedRelativePath } in dependenciesToCopy
        sourcePath = resolvedDir + '/' + resolvedRelativePath
        copyDestination = destDir + '/' + resolvedRelativePath

        @allDirectoriesToCreate.add(dirname(copyDestination))
        @allResolvedPathsToCopy[sourcePath] = copyDestination

        resolvedRelativePath

    # else if numDepsInTree > 0
    #   console.log "Found #{numDepsInTree} #{pluralize('deps', numDepsInTree)} for #{relativePath}, but #{if numDepsInTree is 1 then 'it' else 'all'} already #{if numDepsInTree is 1 then 'exists' else 'exist'} in the broccoli tree"

  processDependenciesToCopy: (relativePath, srcDir) ->

    depTree = @dependencyCache.dependencyTreeForFile(relativePath)

    if not depTree?
      {
        dependenciesToCopy: []
        depTree: EmptyTree
      }
    else
      allExternalDependencyPaths = @_listOfExternalDepsFromTree(depTree)

      # Exclude paths that already exist in the srcDir or already have been copied
      dependenciesToCopyAsObjs = for depPath in allExternalDependencyPaths
        continue if @perBuildCache.depPathsAlreadyProcessed[depPath]

        @perBuildCache.depPathsAlreadyProcessed[depPath] = true
        resolvedDeps = @_cachedResolve(depPath, srcDir + '/' + relativePath)

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

  _cachedResolve: (depPath) ->
    return @perBuildCache.resolveCache[depPath] if @perBuildCache.resolveCache[depPath]?

    @resolveStopwatch = Stopwatch().start() unless @resolveStopwatch?

    [depName, depVersion] = @benderContext.extractProjectAndVersionFromPath(depPath)
    extension = extractExtension(depPath)

    resolvedDeps = @perBuildCache.resolveCache[depPath] = resolveDirAndPath depPath,
      # filename: srcPath + '/' + depPath   # I don't think this is needed
      extensionsToCheck: @dependencyCache.allPossibleCompiledExtensionsFor(extension)
      allowMultipleResultsFromSameDirectory: true
      allowRelativeLookupWithoutPrefix: false

      # We know the exact loadPaths to look in since every dependency built
      # is output to a single directory (and dep build output is mutually exclusive)
      loadPaths: @loadPathsFor(depName, depVersion)

    @resolveStopwatch.lap()

    resolvedDeps

  getDestFilePath: (relativePath) ->
    if @options.extensions?.length > 0
      for ext in @options.extensions
        if relativePath.slice(-ext.length - 1) == '.' + ext
          return relativePath

      # Return undefined to ignore relativePath
      undefined
    else
      relativePath

  loadPathsFor: (depName, depVersion) ->
    [@options.loadPathsByProjectAndVersion()[depName][depVersion]].concat(@options.extraLoadPaths)

  totalNumLoadPaths: ->
    numDirPaths = reduce @options.loadPathsByProjectAndVersion(), (sum, versionMap, key) ->
      sum + Object.keys(versionMap).length
    , 0

    numDirPaths + @options.extraLoadPaths?.length

module.exports = CopyDependenciesFilter
