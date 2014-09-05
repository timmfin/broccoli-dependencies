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

        # console.log "copying: #{depPath}  ->  #{copyDestination}"
        mkdirp.sync(path.dirname(copyDestination))
        helpers.copyPreserveSync(depPath, copyDestination)

        relativeDepPath

      # Also, write out a text file and HTML file which contains a list of all of the
      # dependencies for later usage. Needed because Coffeescript/Sass strip out comments
      # and so that we can do `?hsDebug=true`-style expanded output for bundles
      # outputPath = convertFromPrepressorExtension relativePath
      dependenciesListPath = "#{outputPath}.required-dependencies.txt"
      dependenciesListContent = depTree.listOfAllRequiredDependencies(stripSrcAndLoadPathDirs).join '\n'

      dependenciesHTMLPath = "#{outputPath}.required-dependencies.html"
      dependenciesHTMLContent = depTree.allRequiredDependenciesAsHTML(stripSrcAndLoadPathDirs)

      fs.writeFileSync(destDir + '/' + dependenciesListPath, dependenciesListContent, { encoding: 'utf8' })
      fs.writeFileSync(destDir + '/' + dependenciesHTMLPath, dependenciesHTMLContent, { encoding: 'utf8' })

      # Let broccoli-filter know to cache all of these files
      outputfilesToCache = [outputPath].concat(relativeCopiedPaths)
                                       # .concat([dependenciesListPath, dependenciesHTMLPath])

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




class InsertDirectiveContentsFilter extends Filter

  # Only operate on all of the `*.required-dependencies.txt` files that were
  # laid down by CopyDirectiveDependenciesFilter
  extensions: ['required-dependencies.txt']

  constructor: (inputTree, options = {}) ->
    if not (this instanceof InsertDirectiveContentsFilter)
      return new InsertDirectiveContentsFilter(inputTree, options)

    @inputTree = inputTree
    @options = options

  # Take all the dependencies laid down in `*.required-dependencies.txt` and insert
  # the content of each into the top of the file. Eg. the concatenation step, but done
  # after any other precompilers.
  processFile: (srcDir, destDir, relativePath) ->
    console.log "processing", relativePath
    origFilepath = relativePath.replace '.required-dependencies.txt', ''
    fileContents = origFileContents = fs.readFileSync(srcDir + '/' + origFilepath, { encoding: 'utf8' })

    listOfDependencies = fs.readFileSync(srcDir + '/' + relativePath, { encoding: 'utf8' }).split('\n')
    listOfDependencies.pop()  # remove the self dependency
    console.log "listOfDependencies", listOfDependencies

    directiveResolver = new DirectiveResolver
      loadPaths: [srcDir].concat(@options.loadPaths)
      cache: @options.cache

    header = directiveResolver.extractHeader(fileContents)

    # console.log "\nfileContents", fileContents
    # console.log "\nheader", require('util').inspect(header)
    # console.log "\nfileContents.indexOf(header)", fileContents.indexOf(header)

    # Remove the directive header if it still exists (might be a bit better if
    # only the directive lines in the header were removed)
    fileContents = fileContents.slice header.length if fileContents.indexOf(header) is 0
    # console.log "\nfileContents", fileContents

    deferred = RSVP.defer()

    async.map listOfDependencies, (filepath, callback) ->
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
          console.log "writing #{destDir + '/' + origFilepath}"
          fs.writeFile destDir + '/' + origFilepath, newContents, { encoding: 'utf8' }, (err) ->
            if err
              deferred.reject err
            else
              deferred.resolve
                inputFiles: [origFilepath, relativePath]
                outputFiles: [origFilepath]
        else
          deferred.resolve
            inputFiles: [origFilepath, relativePath]
            outputFiles: []

    deferred.promise



module.exports = {
  CopyDirectiveDependenciesFilter
  InsertDirectiveContentsFilter
}
