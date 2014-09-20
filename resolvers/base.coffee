path = require('path')
fs = require('fs')
_ = require('lodash')

DependenciesCache = require('../dependencies-cache')
FileStruct = require('../file-struct')

{ stripBaseDirectory, extractExtension, extractBaseDirectoryAndRelativePath, convertFromPrepressorExtension } = require('../utils')

class BaseResolver
  constructor: (@config = {}) ->
    # A cache instance can be passed in to re-use dependency caches across different
    # build steps
    @sharedCache = @config.cache ? new DependenciesCache

    if @config.log is true
      @log = console.log.bind 'console'

    if not @extensions?
      throw new Error "This resolver doesn't define which file extensions to iterate over (an `extensions` property)"

  log: -> # empty func by default, overidden in the constructor if @config.log is true

  # Given a path and existing dependency tree (and cache it so we only check for
  # dependencies once).
  dependenciesForFile: (relativePath, srcDir, tmpFileCache, depth) ->

    content = fs.readFileSync srcDir + '/' + relativePath, 'utf8'

    # Let sub-classes do the rest of the work
    dependencyObjects = @processDependenciesInContent content, relativePath, srcDir

    # Remove duplicate dependencies
    _.uniq dependencyObjects, (dep) ->
      dep.relativePath


  # By default, looks at the resolvers extensions to decide if a file can be processed
  shouldProcessFile: (relativePath) ->
    for extension in @extensions
      if relativePath.slice(relativePath.length - extension.length - 1) is ".#{extension}"
        return true

  modifyDependencyNode: (treeNode) ->
    # Optionally customize or modify the treeNode for this dependency tree

  processDependenciesInContent: (content, tree, relativePath, srcDir, next) ->
    throw new Error "processDependenciesInContent needs be overridden by your custom dependency resolver"


  # Resolve a path via the current filename (passed in via options.filename) and
  # among any of the passed loadPaths
  resolveDirAndPath: (inputPath, options = {}) ->
    throw new Error "Required filename option wasn't passed to resolvePath" unless options.filename?

    if options.onlyDirectory
      extensionsToCheck = ['']
    else
      extensionsToCheck = @extensionsToCheck inputPath, options
      extensionsToCheck.push('') if options.allowDirectory is true

    dirsToCheck = options.loadPaths ? []

    # Some mangle-ing to convert a relative path into a path that is
    # relative to the srcDir (which should have been included in options.loadPaths)
    if /^\.|^\.\.|^\.\.\//.test inputPath
      absolutizedPath = path.join path.dirname(options.filename), inputPath
      [resolvedBaseDir, newRelativePath] = extractBaseDirectoryAndRelativePath absolutizedPath, @config.loadPaths
      inputPath = newRelativePath

    [resolvedDir, relativePath] = @searchForPath inputPath, dirsToCheck, extensionsToCheck

    # Throw a useful error if no path is found. Otherwise return the first successful
    # path found by _searchForPath
    if not resolvedDir?
      inputPathText = "#{inputPath}"

      if extensionsToCheck?.length > 0
        originalExtension = extractExtension inputPath
        inputPathText = "#{inputPath.replace(new RegExp('\\.' + originalExtension + '$'), '')}.#{extensionsToCheck.join('|')}"

      errorMessage = "Could not find #{inputPathText} among: #{dirsToCheck}"
      errorMessage += " (while processing #{options.filename})" if options.filename?
      throw new Error errorMessage
    else
      [resolvedDir, relativePath]

  # See if partialPath exists inside any of dirsToCheck optionally with a number of
  # different extensions. If/when found, return an array like: [resolvedDir, relativePathFromDir]
  searchForPath: (partialPath, dirsToCheck, extensionsToCheck = null) ->

    if not dirsToCheck? or dirsToCheck.length is 0
      throw new Error "Could not lookup #{partialPath} no search directories to check."

    originalExtension = extractExtension(partialPath)

    if originalExtension is ''
      replaceExtensionRegex = /$/
    else
      replaceExtensionRegex = new RegExp "\\.#{originalExtension}$"

    extensionsToCheck = [originalExtension] unless extensionsToCheck?

    for dirToCheck in dirsToCheck
      for extensionToCheck in extensionsToCheck
        pathToCheck = path.join dirToCheck, partialPath

        if extensionToCheck isnt ''
          pathToCheck = pathToCheck.replace(replaceExtensionRegex, ".#{extensionToCheck}")

        # @log "    checking for #{pathToCheck}"
        if fs.existsSync(pathToCheck)
          partialPath = partialPath.replace(replaceExtensionRegex, ".#{extensionToCheck}") unless extensionToCheck is ''
          return [dirToCheck, partialPath]

    # If not found return empty array (so that destructuring returns undefined
    # instead of error)
    []


  # Given a potential dependency path, return an array of extensions that are valid.
  # For example, if using a preprocessor, a depenency path to a Javascript file
  # (e.g. `dir/file.js`) may want to additionally check and look and see if if there is a
  # Coffeescript file (e.g. `dir/file.coffee`). Override this to cutomize what
  # are valid extensions for your dependency type.
  #
  # By default, only the extension of the passed in path is returned. However, if
  # the path doesn't have an extension, the extension from `options.filename`
  # (the parent file where this depdency path was encountered) is used.
  extensionsToCheck: (inputPath, options = {}) ->
    extension = extractExtension(inputPath)

    # If there was no valid extension on the passed path, get the extension from the
    # parent path (the file where the passed path came from)
    if extension is '' and options.filename?
      extension = extractExtension(options.filename)

    [extension]

  createDependency: (depDir, depPath, extra = {}) ->
    DependencyConstructor = @config.dependencyConstructor ? FileStruct
    extra.dependencyType = @type
    new DependencyConstructor depDir, depPath, extra


module.exports = BaseResolver

