'use strict'

Promise = require('rsvp').Promise
path = require('path')
fs = require('fs')
helpers = require('broccoli-kitchen-sink-helpers')
mkdirp = require('mkdirp')

{ stripBaseDirectory } = require('./utils')
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
      .then (dependenciesOutput) =>
        { allDependencyPaths, dependenciesToCopy, depTree } = dependenciesOutput

        # Copy the source file, no need to modify
        outputPath = @getDestFilePath(relativePath)
        helpers.copyPreserveSync(srcDir + '/' + relativePath, destDir + '/' + outputPath)

        stripLoadPathDirs = (p) =>
          stripBaseDirectory p, @options.loadPaths

        stripSrcAndLoadPathDirs = (p) =>
          stripBaseDirectory p, [srcDir].concat(@options.loadPaths)

        # If this file had `require` dependencies, then copy them into our Broccoli
        # output because we will need to compile them (and copy the compiled output) later
        #
        # Note `... > 1` and not `... > 0` because the file itself is always included
        # as a dependenency
        if allDependencyPaths.length > 1

          # Copy all the files needed, and create an array of all their relative paths (for later usage)
          relativeCopiedPaths = for depPath in dependenciesToCopy
            relativeDepPath = stripLoadPathDirs depPath
            copyDestination = destDir + '/' + relativeDepPath

            # console.log "copying: #{depPath}  ->  #{copyDestination}"
            mkdirp.sync(path.dirname(copyDestination))
            helpers.copyPreserveSync(depPath, copyDestination)

            relativeDepPath

          # Also, write out a text file and HTML file which contains a list of all of the
          # dependencies for later usage. Needed because Coffeescript/Sass strip out comments
          # and so that we can do `?hsDebug=true`-style expanded output for bundles
          dependenciesListPath = "#{relativePath}.required-dependencies.txt"
          dependenciesListContent = depTree.listOfAllRequiredDependencies(stripSrcAndLoadPathDirs).join '\n'

          dependenciesHTMLPath = "#{relativePath}.required-dependencies.html"
          dependenciesHTMLContent = depTree.allRequiredDependenciesAsHTML(stripSrcAndLoadPathDirs)

          fs.writeFileSync(destDir + '/' + dependenciesListPath, dependenciesListContent, { encoding: 'utf8' })
          fs.writeFileSync(destDir + '/' + dependenciesHTMLPath, dependenciesHTMLContent, { encoding: 'utf8' })

          # Let broccoli-filter know to cache all of these files
          outputfilesToCache = [outputPath].concat(relativeCopiedPaths)
                                           .concat([dependenciesListPath, dependenciesHTMLPath])

          cacheInfo =
            outputFiles: outputfilesToCache


  processDependenciesToCopy: (relativePath, srcDir) ->
    currentPath = path.join srcDir, relativePath

    directiveResolver = new DirectiveResolver
      loadPaths: [srcDir].concat(@options.loadPaths)
      log: true

    depTree = directiveResolver.getDependencyTreeFromDirectives(currentPath)
    allDependencyPaths = depTree.allValues()

    # Exclude paths that already exist in the srcDir or already have been copied
    dependenciesToCopy = allDependencyPaths.filter (p) =>
      if p.indexOf(srcDir) isnt 0 and not @copiedDependencies[p]
        @copiedDependencies[p] = true
        true
      else
        false

    # Return all dependencies of this file _and_ only the files that we needed to copy
    {
      allDependencyPaths
      dependenciesToCopy
      depTree
    }




class InsertDirectiveDependenciesFilter


module.exports = {
  CopyDirectiveDependenciesFilter
  InsertDirectiveDependenciesFilter
}
