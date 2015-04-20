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

  prepareForAnotherBuild: ->
    @dependencyCache?.clearSecondaryCaches()

    @filesProcessed = Object.create(null)
    @allDependenciesFound = Object.create(null)

  findDependencies: (relativePath, srcDir) ->
    @findDependenciesHelper new FileStruct(srcDir, relativePath)

  findDependenciesHelper: (fileStruct, tmpFileCache = {}, depth = 0) ->
    alreadyBeenProcessed = @filesProcessed[fileStruct.relativePath] is true
    existingNode = @dependencyCache.dependencyTreeForFile fileStruct.relativePath

    # Skip any parsing/caclulation if this tree has already been calculated
    return existingNode if alreadyBeenProcessed

    @filesProcessed[fileStruct.relativePath] = true

    if existingNode?
      # Re-use current nodeReference (so nodes can be cached), but blow away all the children
      # so we can re-evaluate those
      currentNode = existingNode
      currentNode.clearChildren()
    else
      currentNode = new DependencyNode fileStruct

    # Look for dependencies in this file
    dependencies = @_findDependenciesAmongResolvers(fileStruct.relativePath, fileStruct.srcDir, tmpFileCache, depth)

    # For each dep found, add it to this current node, but don't recurse. Rather, rely
    # on the fact that all files are being iterated on and will eventually get
    # filled in.
    for dep in dependencies

      @trackDepFoundVia(dep.relativePath, fileStruct)
      existingDepNode = @dependencyCache.dependencyTreeForFile(dep.relativePath)

      # If this dependency node already exists (from earlier in this build pass, or
      # cached from a previous build)
      if existingDepNode?
        depNode = existingDepNode
      else
        depNode = new DependencyNode(new FileStruct(currentNode.srcDir, dep.relativePath))
        @dependencyCache.storeDependencyTree depNode

      currentNode.pushChildNode depNode

      if dep.extra.dependencyType?
        currentNode.pushTypedChildNode(dep.extra.dependencyType, depNode)

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

  trackDepFoundVia: (dep, fromFilestruct) ->
    console.log "trackDepFoundVia", dep, "from:", fromFilestruct.relativePath
    @allDependenciesFound[dep] ?= []
    @allDependenciesFound[dep].push(fromFilestruct)

  # Iterate over all the dependencies found and make sure that each once was also
  # "processed". This ensures that all depdnencies are actually real files (otherwise
  # throw an error that a dep was defined that doesn't really exist).
  ensureAllDependenciesFoundWereProcessed: (filesCached) ->
    for dep, fromLocations of @allDependenciesFound
      console.log "dep", dep
      console.log "fromLocations", (fromLocations ? []).map((f) -> f?.relativePath).join(', ')

      if @filesProcessed[dep] isnt true and filesCached[dep] isnt true
        throw new Error "Dependency #{dep} doesn't exist (was described as a dep for #{fromLocations.map((f) -> f.relativePath).join(', ')})"


module.exports = MultiResolver
