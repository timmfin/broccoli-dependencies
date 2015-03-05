path = require('path')
fs = require('fs')
_ = require('lodash')

DependenciesCache = require('./dependencies-cache')
FileStruct = require('./file-struct')

{ resolveDirAndPath, stripBaseDirectory, extractExtension, extractBaseDirectoryAndRelativePath } = require('bender-broccoli-utils')

class BaseResolver
  constructor: (@config = {}) ->
    # A cache instance can be passed in to re-use dependency caches across different
    # build steps
    @dependencyCache = @config.dependencyCache ? new DependenciesCache

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

  processDependenciesInContent: (content, tree, relativePath, srcDir, next) ->
    throw new Error "processDependenciesInContent needs be overridden by your custom dependency resolver"


  # Resolve a path via the current filename (passed in via options.filename) and
  # among any of the passed loadPaths. Uses the base resolveDirAndPath from
  # bender-broccoli-utils, but includes defaults set on the current resolver.
  resolveDirAndPath: (inputPath, options = {}) ->
    options.extensionsToCheck ?= @extensionsToCheck inputPath, options
    options.onlyAllow ?= @allowedDependencyExtensions

    resolveDirAndPath inputPath, options

  resolvePath: (inputPath, options = {}) ->
    [dir, relPath] = @resolveDirAndPath inputPath, options
    dir + '/' + relativePath



  # Given a potential dependency path, return an array of extensions that are valid.
  # For example, if using a preprocessor, a dependency path to a Javascript file
  # (e.g. `dir/file.js`) may want to additionally check and look and see if if there is a
  # Coffeescript file (e.g. `dir/file.coffee`). Override this to cutomize what
  # are valid extensions for your dependency type.
  #
  # By default, only the extension of the passed in path is returned. However, if
  # the path doesn't have an extension, the extension from `options.filename`
  # (the parent file where this depdency path was encountered) is used.
  extensionsToCheck: (inputPath, options = {}) ->
    extension = extractExtension inputPath, { onlyAllow: @allowedDependencyExtensions }

    # If there was no valid extension on the passed path, get the extension from the
    # parent path (the file where the passed path came from)
    if extension is '' and options.filename?
      extension = extractExtension options.filename, { onlyAllow: @allowedDependencyExtensions }

    [extension]

  createDependency: (depDir, depPath, extra = {}) ->
    DependencyConstructor = @config.dependencyConstructor ? FileStruct
    extra.dependencyType = @type
    new DependencyConstructor depDir, depPath, extra


module.exports = BaseResolver

