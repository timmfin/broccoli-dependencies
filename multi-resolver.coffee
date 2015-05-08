
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

    @resolverCaches = (Object.create(null) for resolver in @resolvers)

  findDependencies: (relativePath, srcDir, options = {}) ->
    @findDependenciesHelper new FileStruct(srcDir, relativePath), options

  findDependenciesHelper: (fileStruct, options, tmpFileCache = {}, depth = 0) ->
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

      # Prevent ciruclar file deps (at least one way they might happen)
      continue if dep.relativePath is fileStruct.relativePath

      @trackDepFoundVia(dep.relativePath, fileStruct)
      existingDepNode = @dependencyCache.dependencyTreeForFile(dep.relativePath)

      # If this dependency node already exists (from earlier in this build pass, or
      # cached from a previous build)
      if existingDepNode?
        depNode = existingDepNode

      # If this is a special case where we don't want to recurse. Instead, we will
      # rely on the knowing that all files within the `dontAutoRecurseWithin`
      # prefixes will eventually get iterated over (or will be cached by the
      # calculateDepenencies filter per-file cache)
      else if options.dontAutoRecurseWithin?.length > 0 and @_doesStartWith(dep.relativePath, options.dontAutoRecurseWithin)
        depNode = new DependencyNode(dep)
        @dependencyCache.storeDependencyTree depNode

      # Otherwise, recurse and find dependencies
      else
        depNode = @findDependenciesHelper dep, options, tmpFileCache, depth + 1


      currentNode.pushChildNode depNode

      if dep.extra.dependencyType?
        @dependencyCache.ensureHasSeenDependencyType dep.extra.dependencyType
        currentNode.pushTypedChildNode(dep.extra.dependencyType, depNode)

    # Note, I'm only recursively following the deps of individual files,
    # and not re-adding all other files (and recursing) when a new whole project is
    # found.
    #
    # This only works because deps only build files that are necessary and not
    # their entire folder.

    @dependencyCache.storeDependencyTree currentNode
    currentNode

  _doesStartWith: (relativePath, excludedPathPrefixes) ->
    for excludedPathPrefix in excludedPathPrefixes
      if relativePath.indexOf(excludedPathPrefix) is 0
        return true

    false

  _findDependenciesAmongResolvers: (relativePath, srcDir, tmpFileCache, depth) ->
    targetFilePath = srcDir + '/' + relativePath

    # Skip if this file has already added to this tree of dependencies (to
    # avoid circular dependencies)
    return [] if tmpFileCache[targetFilePath]
    tmpFileCache[targetFilePath] = true

    dependenciesFromAllResolvers = []

    for Resolver, i in @resolvers
      resolver = new Resolver
        loadPaths: [srcDir].concat(@options.loadPaths)
        dependencyCache: @options.dependencyCache
        perBuildCache: @resolverCaches[i]

      if resolver.shouldProcessFile(relativePath)
        newDeps = resolver.dependenciesForFile(relativePath, srcDir, tmpFileCache, depth)

        dependenciesFromAllResolvers = dependenciesFromAllResolvers.concat newDeps

    dependenciesFromAllResolvers

  trackDepFoundVia: (depRelativePath, fromFilestruct) ->
    @allDependenciesFound[depRelativePath] ?= []
    @allDependenciesFound[depRelativePath].push(fromFilestruct)

  # Iterate over all the dependencies found and make sure that each once was also
  # "processed". This ensures that all depdnencies are actually real files (otherwise
  # throw an error that a dep was defined that doesn't really exist).
  ensureAllDependenciesFoundWereProcessed: (filesCached, options = {}) ->
    { prefixesToLimitTo } = options

    for dep, fromLocations of @allDependenciesFound
      if @filesProcessed[dep] isnt true and filesCached[dep] isnt true
        if not prefixesToLimitTo or @_doesStartWith(dep, prefixesToLimitTo)
          throw new Error "Dependency #{dep} doesn't exist (was described as a dep for #{fromLocations.map((f) -> f.relativePath).join(', ')})"



module.exports = MultiResolver
