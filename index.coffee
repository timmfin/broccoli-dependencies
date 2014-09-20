'use strict'

RSVP      = require('rsvp')
path      = require('path')
fs        = require('fs')
helpers   = require('broccoli-kitchen-sink-helpers')
mkdirp    = require('mkdirp')
async     = require('async')
pluralize = require('pluralize')

{ stripBaseDirectory, convertFromPrepressorExtension } = require('./utils')
Filter                 = require('broccoli-filter')
SprocketsResolver      = require('./resolvers/sprockets-dependencies')
MultiResolver          = require('./multi-resolver')


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
      console.log "Copying all missing dependencies from #{relativePath} (#{dependenciesToCopy.length} #{pluralize('file', dependenciesToCopy)} out of #{numDepsInTree} deps)"

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

    else if numDepsInTree > 0
      console.log "Found #{numDepsInTree} #{pluralize('deps', numDepsInTree)} for #{relativePath}, but #{if numDepsInTree is 1 then 'it' else 'all'} already #{if numDepsInTree is 1 then 'exists' else 'exist'} in the broccoli tree"

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


# Mimic Sprocket-style `//= require ...` directives to concatenate JS/CSS via broccoli.
#
# You can pass in an existing `DependenciesCache` instance if you already have
# done a pass at calculating dependencies. For example:
#
#     sharedDependencyCache = new DependenciesCache
#
#     tree = CopyDependenciesFilter tree,
#       cache: sharedDependencyCache
#       loadPaths: externalLoadPaths
#
#     tree = compileSass tree,
#       sassDir: '.'
#       cssDir: '.'
#       importPath: externalLoadPaths
#
#     tree = compileCoffeescript tree
#
#     tree = InsertDirectiveContentsFilter tree,
#       cache: sharedDependencyCache
#       loadPaths: externalLoadPaths

class InsertDirectiveContentsFilter extends Filter

  extensions: SprocketsResolver.REQUIREABLE_EXTENSIONS

  constructor: (inputTree, options = {}) ->
    if not (this instanceof InsertDirectiveContentsFilter)
      return new InsertDirectiveContentsFilter(inputTree, options)

    @inputTree = inputTree
    @options = options

    throw new Error "No cache instance passed in InsertDirectiveContentsFilter's options, that is expected (for now?)" unless @options.cache?

  # Take all the dependencies laid down in the `DependenciesCache` and insert
  # the content of each into the top of the file. Eg. the concatenation step, but done
  # after any other precompilers.
  processFile: (srcDir, destDir, relativePath) ->
    fileContents = origFileContents = fs.readFileSync(srcDir + '/' + relativePath, { encoding: 'utf8' })

    # Assumes that a pre-filled dependency cache instance was passed into this filter
    depTree = @options.cache.dependencyTreeForFile relativePath
    allRelativeDependencyPaths = depTree?.listOfAllDependencies() ? []
    allRelativeDependencyPaths.pop()  # remove the self dependency

    if not depTree? or allRelativeDependencyPaths.length is 0
      helpers.copyPreserveSync srcDir + '/' + relativePath, destDir + '/' + relativePath
    else
      # Remove the directive header if it still exists (might be a bit better if
      # only the directive lines in the header were removed)
      header = SprocketsResolver.extractHeader(fileContents)
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

          if newContents isnt origFileContents
            console.log "Concatenating directive deps into #{relativePath}"
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
  CopyDependenciesFilter
  InsertDirectiveContentsFilter
}
