'use strict'

Promise = require('rsvp').Promise
path = require('path')
fs = require('fs')
helpers = require('broccoli-kitchen-sink-helpers')
mkdirp = require('mkdirp')

Filter = require('broccoli-filter')
DirectiveResolver = require('./directive-resolver')


class CopyDirectiveDependenciesFilter extends Filter

  extensions: DirectiveResolver.REQUIREABLE_EXTENSIONS

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CopyDirectiveDependenciesFilter)
      return new CopyDirectiveDependenciesFilter(inputTree, options)

    @inputTree = inputTree
    @options = options

    @copiedDependencies = {}

  processFile: (srcDir, destDir, relativePath) ->
    return Promise.resolve(@processDependenciesToCopy(relativePath, srcDir, destDir))
      .then (dependenciesToCopy) =>

        # Copy the source file, no need to modify
        outputPath = @getDestFilePath(relativePath)
        helpers.copyPreserveSync(srcDir + '/' + relativePath, destDir + '/' + outputPath)

        if dependenciesToCopy.length > 0
          relativeCopiedPaths = for depPath in dependenciesToCopy
            relativeDepPath = @stripLoadPath depPath
            copyDestination = destDir + '/' + relativeDepPath

            # console.log "copy to: #{destDir + '/' + relativeDepPath}"
            mkdirp.sync(path.dirname(copyDestination))
            helpers.copyPreserveSync(depPath, copyDestination)

            relativeDepPath

          cacheInfo =
            outputFiles: [@getDestFilePath(relativePath)].concat(relativeCopiedPaths)


  processDependenciesToCopy: (relativePath, srcDir) ->
    currentPath = path.join srcDir, relativePath

    directiveResolver = new DirectiveResolver
      loadPaths: [srcDir].concat(@options.loadPaths)

    dependencyPaths = directiveResolver.getDependenciesFromDirectives(currentPath)

    # Exclude paths that already exist in the srcDir or already have been copied
    pathsToCopy = dependencyPaths.filter (p) =>
      if p.indexOf(srcDir) isnt 0 and not @copiedDependencies[p]
        @copiedDependencies[p] = true
        true
      else
        false

    # console.log("pathsToCopy", pathsToCopy) if pathsToCopy.length
    pathsToCopy

  stripLoadPath: (depPath) ->
    for loadPath in @options.loadPaths
      if depPath.indexOf(loadPath) is 0
        return depPath.replace loadPath, ''

    throw new Error "#{depPath} isn't in any of #{@options.loadPaths.join(', ')}"



class InsertDirectiveDependenciesFilter


module.exports = {
  CopyDirectiveDependenciesFilter
  InsertDirectiveDependenciesFilter
}
