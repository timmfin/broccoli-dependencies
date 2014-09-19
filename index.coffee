'use strict'

RSVP    = require('rsvp')
path    = require('path')
fs      = require('fs')
helpers = require('broccoli-kitchen-sink-helpers')
mkdirp  = require('mkdirp')
async   = require('async')

{ stripBaseDirectory, convertFromPrepressorExtension } = require('./utils')
Filter                 = require('broccoli-filter')
SprocketsResolver      = require('./resolvers/sprockets-dependencies')
DependencyNode         = require('./tree')
Dependency             = require('./dependency')


# Follows the dependency tree from Sprockets `//= require ...` directives, and
# copies all of those dependencies into the broccoli "working dir" if they are not
# already there.
#
# This is necessary to ensure that any `require`-ed files that need preprocessing
# (like Sass or Coffeescript) are included before the rest of the build steps.

class CopyDirectiveDependenciesFilter extends Filter

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CopyDirectiveDependenciesFilter)
      return new CopyDirectiveDependenciesFilter(inputTree, options)

    @inputTree = inputTree
    @options = options

    @extensions = []

    for Resolver in @options.resolvers
      for ext in Resolver::extensions
        @extensions.push(ext) if @extensions.indexOf(ext) is -1

    @copiedDependencies = {}

  processFile: (srcDir, destDir, relativePath) ->
    { dependenciesToCopy, depTree } = @processDependenciesToCopy(relativePath, srcDir, destDir)

    # Copy the source file, no need to modify
    outputPath = @getDestFilePath(relativePath)
    helpers.copyPreserveSync(srcDir + '/' + relativePath, destDir + '/' + outputPath)

    # If this file had `require` dependencies, then copy them into our Broccoli
    # output because we will need to compile them (and copy the compiled output) later
    if dependenciesToCopy.length > 0
      console.log "Copying all missing dependencies from #{relativePath} (#{dependenciesToCopy.length} file#{if dependenciesToCopy.length > 1 then 's' else ''} out of #{depTree.size() - 1} deps)"

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

  # TODO extract out of this filter (into something re-usable)
  findDependenciesViaResolvers: (relativePath, srcDir, tmpFileCache = {}, depth = 0) ->
    currentNode = @createTree srcDir, relativePath

    # Skip any parsing/caclulation if this tree has already been calculated
    if @options.cache.hasFile relativePath
      @options.cache.dependencyTreeForFile relativePath

    else
      dependencies = @_findDependenciesViaResolversHelper(relativePath, srcDir, tmpFileCache, depth)

      # Recursively look for dependencies in all of the new children just added
      for dep in dependencies
        newDepNode = @findDependenciesViaResolvers dep.relativePath, dep.srcDir, tmpFileCache, depth + 1
        currentNode.pushChildNode newDepNode

      @options.cache.storeDependencyTree currentNode
      currentNode

  _findDependenciesViaResolversHelper: (relativePath, srcDir, tmpFileCache, depth) ->
    targetFilePath = srcDir + '/' + relativePath

    # Skip if this file has already added to this tree of dependencies (to
    # avoid circular dependencies)
    return [] if tmpFileCache[targetFilePath]
    tmpFileCache[targetFilePath] = true

    dependenciesFromAllResolvers = []

    for Resolver in @options.resolvers
      resolver = new Resolver
        loadPaths: [srcDir].concat(@options.loadPaths)
        cache: @options.cache

      if resolver.shouldProcessFile(relativePath)
        newDeps = resolver.dependenciesForFile(relativePath, srcDir, tmpFileCache, depth)
        dependenciesFromAllResolvers = dependenciesFromAllResolvers.concat newDeps

    dependenciesFromAllResolvers

  createTree: (srcDir, relativePath) ->
    DependencyNode.createTree new Dependency(srcDir, relativePath)

  processDependenciesToCopy: (relativePath, srcDir) ->
    depTree = @findDependenciesViaResolvers relativePath, srcDir
    allAbsoluteDependencyPaths = depTree.listOfAllOriginalAbsoluteDependencies()

    # Exclude paths that already exist in the srcDir or already have been copied
    dependenciesToCopy = allAbsoluteDependencyPaths.filter (p) =>
      pathInsideSrcDir = p.indexOf(srcDir) is 0

      if not pathInsideSrcDir and not @copiedDependencies[p] and @filter?(p) isnt false
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
#     tree = CopyDirectiveDependenciesFilter tree,
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
  CopyDirectiveDependenciesFilter
  InsertDirectiveContentsFilter
}
