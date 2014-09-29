'use strict'

path      = require('path')
fs        = require('fs')
helpers   = require('broccoli-kitchen-sink-helpers')
mkdirp    = require('mkdirp')
pluralize = require('pluralize')
Filter    = require('broccoli-filter')
{ stripBaseDirectory } = require('bender-broccoli-utils')

MultiResolver = require('./multi-resolver')


# Follows the dependency tree from Sprockets `//= require ...` directives, and
# copies all of those dependencies into the broccoli "working dir" if they are not
# already there.
#
# This is necessary to ensure that any `require`-ed files that need preprocessing
# (like Sass or Coffeescript) are included before the rest of the build steps.

class CopyDependenciesFilter extends Filter

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CopyDependenciesFilter)
      return new CopyDependenciesFilter(inputTree, options)

    @inputTree = inputTree
    @options = options

    @multiResolver = new MultiResolver options
    @extensions = @multiResolver.allResolverExtensions()

    @copiedDependencies = {}

  processFile: (srcDir, destDir, relativePath) ->
    { dependenciesToCopy, depTree } = @processDependenciesToCopy(relativePath, srcDir, destDir)

    # Copy the source file, no need to modify
    outputPath = @getDestFilePath(relativePath)
    helpers.copyPreserveSync(srcDir + '/' + relativePath, destDir + '/' + outputPath)

    # If this file had `require` dependencies, then copy them into our Broccoli
    # output because we will need to compile them (and copy the compiled output) later
    numDepsInTree = depTree.size() - 1

    if dependenciesToCopy.length > 0
      console.log "Copying all missing dependencies from #{relativePath} (#{dependenciesToCopy.length} #{pluralize('file', dependenciesToCopy.length)} out of #{numDepsInTree} deps)"

      # Copy all the files needed, and create an array of all their relative paths (for later usage)
      relativeCopiedPaths = for depPath in dependenciesToCopy
        relativeDepPath = stripBaseDirectory depPath, @options.loadPaths
        copyDestination = destDir + '/' + relativeDepPath

        mkdirp.sync(path.dirname(copyDestination))
        helpers.copyPreserveSync(depPath, copyDestination)

        relativeDepPath

      # Let broccoli-filter know to cache all of these files
      outputfilesToCache = [outputPath].concat(relativeCopiedPaths)

      cacheInfo =
        outputFiles: outputfilesToCache

    # else if numDepsInTree > 0
    #   console.log "Found #{numDepsInTree} #{pluralize('deps', numDepsInTree)} for #{relativePath}, but #{if numDepsInTree is 1 then 'it' else 'all'} already #{if numDepsInTree is 1 then 'exists' else 'exist'} in the broccoli tree"

  processDependenciesToCopy: (relativePath, srcDir) ->
    depTree = @multiResolver.findDependencies(relativePath, srcDir)
    allAbsoluteDependencyPaths = depTree.listOfAllOriginalAbsoluteDependencies()

    # Exclude paths that already exist in the srcDir or already have been copied
    dependenciesToCopy = allAbsoluteDependencyPaths.filter (p) =>
      pathInsideSrcDir = p.indexOf(srcDir) is 0

      if not pathInsideSrcDir and not @copiedDependencies[p] and @options.filter?(p) isnt false
        @copiedDependencies[p] = true
        true
      else
        false

    # Return all dependencies of this file _and_ only the files that we needed to copy
    {
      dependenciesToCopy
      depTree
    }


module.exports = CopyDependenciesFilter
