DependenciesCache = require('./dependencies-cache')
FileStruct = require('./file-struct')
DependencyNode = require('./tree')


class MultiResolver
  constructor: (@options = {}) ->
    @resolvers = @options.resolvers
    @dependencyCache = @options.dependencyCache ? new DependenciesCache

  allResolverExtensions: ->
    allExtensions = []

    for Resolver in @resolvers
      for ext in Resolver::extensions
        allExtensions.push(ext) if allExtensions.indexOf(ext) is -1

    allExtensions

  findDependencies: (relativePath, srcDir) ->
    @findDependenciesHelper new FileStruct(srcDir, relativePath)

  findDependenciesHelper: (fileStruct, tmpFileCache = {}, depth = 0) ->
    currentNode = new DependencyNode fileStruct

    # Skip any parsing/caclulation if this tree has already been calculated
    if @dependencyCache.hasFile fileStruct.relativePath

      # Why is this code here, it isn't doing anything, right?
      existingTree = @dependencyCache.dependencyTreeForFile fileStruct.relativePath

    else
      dependencies = @_findDependenciesAmongResolvers(fileStruct.relativePath, fileStruct.srcDir, tmpFileCache, depth)

      # Recursively look for dependencies in all of the new children just added
      for dep in dependencies
        newDepNode = @findDependenciesHelper dep, tmpFileCache, depth + 1
        currentNode.pushChildNode newDepNode

        if dep.extra.dependencyType?
          currentNode.pushTypedChildNode(dep.extra.dependencyType, newDepNode)

      # Note, I'm only recursively following the deps of individual files,
      # and not re-adding all other files (and recursing) when a new whole project is
      # found.
      #
      # This only works because deps only build files that are necessary and not
      # their entire folder.

      @dependencyCache.storeDependencyTree currentNode
      currentNode

  _findDependenciesAmongResolvers: (relativePath, srcDir, tmpFileCache, depth) ->
    targetFilePath = srcDir + '/' + relativePath

    # Skip if this file has already added to this tree of dependencies (to
    # avoid circular dependencies)
    return [] if tmpFileCache[targetFilePath]
    tmpFileCache[targetFilePath] = true

    dependenciesFromAllResolvers = []

    for Resolver in @resolvers
      resolver = new Resolver
        loadPaths: [srcDir].concat(@options.loadPaths)
        dependencyCache: @options.dependencyCache

      if resolver.shouldProcessFile(relativePath)
        newDeps = resolver.dependenciesForFile(relativePath, srcDir, tmpFileCache, depth)

        dependenciesFromAllResolvers = dependenciesFromAllResolvers.concat newDeps

    dependenciesFromAllResolvers



module.exports = MultiResolver
