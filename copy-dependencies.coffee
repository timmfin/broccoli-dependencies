'use strict'

path      = require('path')
fs        = require('fs')
helpers   = require('broccoli-kitchen-sink-helpers')
mkdirp    = require('mkdirp')
pluralize = require('pluralize')
walkSync  = require('walk-sync')
Writer    = require('broccoli-caching-writer')

{ compact: filterFalseValues, flatten } = require('lodash')
{ stripBaseDirectory, resolveDirAndPath, extractExtension } = require('bender-broccoli-utils')

{ EmptyTree } = require('./tree')


# Follows the dependency tree created by your configured resolvers (Sass, sprockets
# directives, jade, etc), and copies all of those dependencies into the broccoli
# "working dir" if they are not already there.
#
# This is necessary to ensure that any dependent files are included before the
# rest of the build steps.

class CopyDependenciesFilter extends Writer

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CopyDependenciesFilter)
      return new CopyDependenciesFilter(inputTree, options)

    # Make sure the broccoli-caching-writer constructor is called
    Writer.call(this, inputTree, options)

    @inputTree = inputTree
    @options = options

    # Ensure that only extensions that are possible dependencies can cause a rebuild
    # (only if `@filterFromCache.include` isn't already specified)
    if @filterFromCache.include.length is 0 and @options.extensions?
      @filterFromCache.include.push ///
          .*
          \.(?: #{@options.extensions.join('|')} )
          $
        ///

    @copiedDependencies = {}

  updateCache: (srcDir, destDir) ->
    @copiedDependencies = {}

    walkSync(srcDir).map (relativePath) =>
      isDirectory = relativePath.slice(-1) == '/'
      outputPath  = @getDestFilePath(relativePath)
      destPath    = destDir + '/' + (outputPath or relativePath)

      shouldBeProcessed = @isIncludedPath(relativePath)

      # If this is a directory make sure that it exists in the destination.
      if isDirectory
        mkdirp.sync destPath
      else
        # If this is a file we want to process (getDestFilePath checks if it matches
        # any of the `@options.extensions` configured)
        if outputPath and shouldBeProcessed
          @processFile(srcDir, destDir, relativePath)

        # always copy across the source file, even if it shouldn't be processed for deps.
        helpers.copyPreserveSync(srcDir + '/' + relativePath, destPath)

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

        mkdirp.sync(path.dirname(copyDestination))
        helpers.copyPreserveSync(sourcePath, copyDestination)

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
          if resolvedDir isnt srcDir and not @copiedDependencies[resolvedRelativePath] and @options.filter?(resolvedRelativePath) isnt false
            @copiedDependencies[resolvedRelativePath] = true
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
