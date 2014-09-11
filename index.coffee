'use strict'

RSVP    = require('rsvp')
path    = require('path')
fs      = require('fs')
helpers = require('broccoli-kitchen-sink-helpers')
mkdirp  = require('mkdirp')
async   = require('async')

{ stripBaseDirectory, convertFromPrepressorExtension } = require('./utils')
Filter                 = require('broccoli-filter')
DirectiveResolver      = require('./directive-resolver')


class CopyDirectiveDependenciesFilter extends Filter

  extensions: DirectiveResolver.REQUIREABLE_EXTENSIONS

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CopyDirectiveDependenciesFilter)
      return new CopyDirectiveDependenciesFilter(inputTree, options)

    @inputTree = inputTree
    @options = options

    @copiedDependencies = {}

  processFile: (srcDir, destDir, relativePath) ->
    { dependenciesToCopy, depTree } = @processDependenciesToCopy(relativePath, srcDir, destDir)

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
    if depTree.size() > 1

      # Copy all the files needed, and create an array of all their relative paths (for later usage)
      relativeCopiedPaths = for depPath in dependenciesToCopy
        relativeDepPath = stripLoadPathDirs depPath
        copyDestination = destDir + '/' + relativeDepPath

        mkdirp.sync(path.dirname(copyDestination))
        helpers.copyPreserveSync(depPath, copyDestination)

        relativeDepPath

      # Let broccoli-filter know to cache all of these files
      outputfilesToCache = [outputPath].concat(relativeCopiedPaths)

      cacheInfo =
        outputFiles: outputfilesToCache


  processDependenciesToCopy: (relativePath, srcDir) ->
    directiveResolver = new DirectiveResolver
      loadPaths: [srcDir].concat(@options.loadPaths)
      cache: @options.cache

    depTree = directiveResolver.getDependencyTreeFromDirectives(relativePath, srcDir)
    allAbsoluteDependencyPaths = depTree.listOfAllOriginalAbsoluteDependencies()

    # Exclude paths that already exist in the srcDir or already have been copied
    dependenciesToCopy = allAbsoluteDependencyPaths.filter (p) =>
      if p.indexOf(srcDir) isnt 0 and not @copiedDependencies[p]
        @copiedDependencies[p] = true
        true
      else
        false

    # Return all dependencies of this file _and_ only the files that we needed to copy
    {
      dependenciesToCopy
      depTree
    }




class InsertDirectiveContentsFilter extends Filter

  extensions: DirectiveResolver.REQUIREABLE_EXTENSIONS

  constructor: (inputTree, options = {}) ->
    if not (this instanceof InsertDirectiveContentsFilter)
      return new InsertDirectiveContentsFilter(inputTree, options)

    @inputTree = inputTree
    @options = options

    throw new Error "No cache instance passed in InsertDirectiveContentsFilter's options, that is expected (for now?)" unless @options.cache?

  # Take all the dependencies laid down in `*.required-dependencies.txt` and insert
  # the content of each into the top of the file. Eg. the concatenation step, but done
  # after any other precompilers.
  processFile: (srcDir, destDir, relativePath) ->
    console.log "processing", relativePath
    fileContents = origFileContents = fs.readFileSync(srcDir + '/' + relativePath, { encoding: 'utf8' })

    # Since we (should be) passing in a cache used during CopyDirectiveDependenciesFilter,
    # the `getDependencyTreeFromDirectives(...)` is a no-op that just returns an
    # existing tree in the cache
    directiveResolver = new DirectiveResolver
      loadPaths: [srcDir].concat(@options.loadPaths)
      cache: @options.cache

    depTree = directiveResolver.getDependencyTreeFromDirectives(relativePath, srcDir)
    allRelativeDependencyPaths = depTree.listOfAllFinalizedRequiredDependencies()
    allRelativeDependencyPaths.pop()  # remove the self dependency

    console.log "allRelativeDependencyPaths", allRelativeDependencyPaths

    # Remove the directive header if it still exists (might be a bit better if
    # only the directive lines in the header were removed)
    header = directiveResolver.extractHeader(fileContents)
    fileContents = fileContents.slice(header.length) if fileContents.indexOf(header) is 0
    # console.log "\nfileContents", fileContents

    deferred = RSVP.defer()

    async.map allRelativeDependencyPaths, (filepath, callback) ->
      fs.readFile srcDir + '/' + filepath, { encoding: 'utf8' }, callback
    , (err, contentsOfAllDependencies) ->
      if err
        deferred.reject err
      else
        newContents = contentsOfAllDependencies.join('\n') + fileContents
        console.log "contentsOfAllDependencies length", contentsOfAllDependencies.join('\n').length
        console.log "newContents.length", newContents.length
        # console.log "\nnewContents", newContents

        if newContents isnt origFileContents
          console.log "writing #{destDir + '/' + relativePath}"
          fs.writeFile destDir + '/' + relativePath, newContents, { encoding: 'utf8' }, (err) ->
            if err
              deferred.reject err
            else
              deferred.resolve()
        else
          helpers.copyPreserveSync srcDir + '/' + relativePath, destDir + '/' + relativePath
          deferred.resolve()

    deferred.promise



module.exports = {
  CopyDirectiveDependenciesFilter
  InsertDirectiveContentsFilter
}
