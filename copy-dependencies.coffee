'use strict'

fs             = require('fs')
RSVP           = require('RSVP')
async          = require('async')
mkdirp         = require('mkdirp')
helpers        = require('broccoli-kitchen-sink-helpers')
walkSync       = require('walk-sync')
pluralize      = require('pluralize')
mapSeries      = require('promise-map-series')
symlinkOrCopy  = require('symlink-or-copy')
CachingWriter  = require('broccoli-caching-writer')
NoopTreeJoiner = require('broccoli-noop-join-trees')

{ dirname } = require('path')
{ compact: filterFalseValues, flatten, merge, reduce } = require('lodash')
{ stripBaseDirectory, resolveDirAndPath, extractExtension, Stopwatch } = require('bender-broccoli-utils')

{ EmptyTree } = require('./tree')


# Follows the dependency graph created earlier and copies all of those dependency
# projects into the broccoli "working dir" if they are not already there.
#
# This is necessary to ensure that any dependent files are included before the
# rest of the build steps.

class CopyDependenciesFilter extends CachingWriter

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CopyDependenciesFilter)
      return new CopyDependenciesFilter(inputTree, options)

    # CoreObject (used inside CachingWriter) doesn't like being called directly
    CachingWriter.prototype.init.call this, [inputTree], {}

    @options = options
    { @project, @benderContext } = @options


  rebuild: ->
    @stopwatch = Stopwatch().start()

    result = super()
    result.then => @callPostBuildCallbackIfNecessary()
    result

  build: () ->
    srcDir = this.inputPaths[0]
    destDir = this.outputPath

    @allRelativePathsToCopy = Object.create(null)
    @sourceFilesToCopy = Object.create(null)
    @allDirectoriesToCreate = new Set
    @setOfExistingFiles = new Set

    @numFilesProcessed = 0
    @numFilesWalked = 0

    processStopwatch = null
    @stopwatch.lap()

    walkedArray = walkSync(srcDir)

    # Save all of the files in the input dir for later usage
    for relativePath in walkedArray
      isDirectory = relativePath.slice(-1) == '/'
      @setOfExistingFiles.add(relativePath) unless isDirectory

    @stopwatch.lap()

    walkedArray.map (relativePath) =>
      isDirectory = relativePath.slice(-1) == '/'
      outputPath  = @getDestFilePath(relativePath)

      if isDirectory
        @onVisitedDirectory(srcDir, relativePath, destDir)
      else
        @numFilesWalked += 1

        # If this is a file we want to process (getDestFilePath checks if it matches
        # any of the `@options.extensions` configured)
        if outputPath
          @numFilesProcessed += 1
          processStopwatch = Stopwatch().start() unless processStopwatch
          @processFile(srcDir, destDir, relativePath)
          # console.log "   copy deps processFile lap: #{stopwatch.lap().prettyOutLastLap({ color: true })}"

        @onVisitedFileInInputTree(srcDir, relativePath, shouldBeProcessed, destDir, outputPath)

    @stopwatch.lap()


    # Batch up the copies and dir creation to the end (but still keeping sync
    # because I measured and it doesn't make a difference)

    for dirToCreate in @allDirectoriesToCreate.toArray()
      mkdirp.sync dirToCreate

    copyStopwatch = Stopwatch().start()

    for src, dest of merge({}, @sourceFilesToCopy, @allResolvedPathsToCopy)
      symlinkOrCopy.sync src, dest

    @stopwatch.lap()


  # Hooks so that CopyProjectDependenciesFilter can change copy/symlink behavior

  onVisitedDirectory: (srcDir, relativePath, destDir) ->
    # By default, if this is a directory make sure that it exists in the destination.
    @allDirectoriesToCreate.add destDir + '/' + relativePath

  onVisitedFileInInputTree: (srcDir, relativePath, wasProcessed, destDir, outputPath) ->
    # By default, always copy across the source file, even if it wasn't processed for deps.
    destPath    = destDir + '/' + (outputPath or relativePath)
    @sourceFilesToCopy[srcDir + '/' + relativePath] = destPath

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
        continue if @setOfExistingFiles.has(depPath)

        @perBuildCache.depPathsAlreadyProcessed[depPath] = true

        resolvedDeps = @_cachedResolve(depPath, srcDir + '/' + relativePath)

        filteredResolvedDeps = for [resolvedDir, resolvedRelativePath] in resolvedDeps
          if resolvedDir isnt srcDir and not @allRelativePathsToCopy[resolvedRelativePath] # and @options.filterDep?(resolvedRelativePath) isnt false
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

  loadPathsFor: (depName, depVersion) ->
    loadPaths = []

    # First load paths com from the explicit map we have of dependency name & version
    # to ouput dir
    pathForDep = @options.loadPathsByProjectAndVersion()?[depName]?[depVersion]
    loadPaths = [pathForDep] if pathForDep?

    # And then any other extra directories
    loadPaths = loadPaths.concat(@options.extraLoadPaths) if @options.extraLoadPaths?

    loadPaths

  totalNumLoadPaths: ->
    numDirPaths = reduce @options.loadPathsByProjectAndVersion(), (sum, versionMap, key) ->
      sum + Object.keys(versionMap).length
    , 0

    numDirPaths + @options.extraLoadPaths?.length

  # Call the optionally attach postBuild callback with some useful data (list of files
  # in the intputTree and list of all deps)
  callPostBuildCallbackIfNecessary: ->
    if @options.postBuild?
      allRelativeSourceFiles = @setOfExistingFiles?.toArray() ? []
      allRelativeDepFiles = (file for file, value of @allRelativePathsToCopy when value is true)

      @options.postBuild(allRelativeSourceFiles, allRelativeDepFiles)

module.exports = CopyDependenciesFilter
