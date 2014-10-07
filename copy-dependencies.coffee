'use strict'

path      = require('path')
fs        = require('fs')
helpers   = require('broccoli-kitchen-sink-helpers')
mkdirp    = require('mkdirp')
pluralize = require('pluralize')
walkSync  = require('walk-sync')
Writer    = require('broccoli-caching-writer')
{ stripBaseDirectory } = require('bender-broccoli-utils')

MultiResolver = require('./multi-resolver')


# Follows the dependency tree from Sprockets `//= require ...` directives, and
# copies all of those dependencies into the broccoli "working dir" if they are not
# already there.
#
# This is necessary to ensure that any `require`-ed files that need preprocessing
# (like Sass or Coffeescript) are included before the rest of the build steps.

class CopyDependenciesFilter extends Writer

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CopyDependenciesFilter)
      return new CopyDependenciesFilter(inputTree, options)

    # Make sure the broccoli-caching-writer constructor is called
    Writer.call(this, inputTree, options)

    @inputTree = inputTree
    @options = options

    @multiResolver = new MultiResolver options
    @extensions = @multiResolver.allResolverExtensions()

    # Ensure that only extensions that are possible dependencies can cause a rebuild
    # (only if `@filterFromCache.include` isn't already specified)
    if @filterFromCache.include.length is 0
      @filterFromCache.include.push ///
          .*
          \.(?: #{@extensions.join('|')} )
          $
        ///

    @copiedDependencies = {}

  updateCache: (srcDir, destDir) ->
    # Ensure that we re-build dependency trees for every re-build (and other
    # per-run caches)
    @multiResolver.dependencyCache?.clearAll()
    @copiedDependencies = {}

    walkSync(srcDir).map (relativePath) =>
      outputPath = @getDestFilePath(relativePath)
      destPath = destDir + '/' + (outputPath or relativePath)

      # If this is a file we want to process (getDestFilePath checks if it matches
      # any of the @extensions that came from @multiResolver)
      if outputPath
        @processFile(srcDir, destDir, relativePath)

      # If this is a directory, make sure that it exists in the destination. Otherwise
      # always copy across the source file, even if it shouldn't be processed for deps.
      if relativePath.slice(-1) == '/'
        mkdirp.sync destPath
      else
        helpers.copyPreserveSync(srcDir + '/' + relativePath, destPath)

  processFile: (srcDir, destDir, relativePath) ->
    { dependenciesToCopy, depTree } = @processDependenciesToCopy(relativePath, srcDir, destDir)

    # If this file had dependencies, copy them into our Broccoli output because
    # we will need to compile them (and copy the compiled output) later
    numDepsInTree = depTree.size() - 1

    if dependenciesToCopy.length > 0
      console.log "Copying all missing dependencies from #{relativePath} (#{dependenciesToCopy.length} #{pluralize('file', dependenciesToCopy.length)} out of #{numDepsInTree} deps)"

      # Copy all the files needed, and create an array of all their relative paths (for later usage)
      for depPath in dependenciesToCopy
        relativeDepPath = stripBaseDirectory depPath, @options.loadPaths
        copyDestination = destDir + '/' + relativeDepPath

        mkdirp.sync(path.dirname(copyDestination))
        helpers.copyPreserveSync(depPath, copyDestination)

        relativeDepPath

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

  getDestFilePath: (relativePath) ->
    for ext in @extensions
      if relativePath.slice(-ext.length - 1) == '.' + ext
        return relativePath

    # Return undefined to ignore relativePath
    return undefined



module.exports = CopyDependenciesFilter
