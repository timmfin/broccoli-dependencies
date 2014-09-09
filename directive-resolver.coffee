'use strict'

fs = require('fs')
path = require('path')
_ = require('lodash')
shellwords = require("shellwords")
walkSync = require('walk-sync')
util = require('util')

{ stripBaseDirectory, extractExtension, extractBaseDirectoryAndRelativePath } = require('./utils')
{ createTree } = require('./tree')
DirectiveResult = require('./directive-result')
DirectiveDependenciesCache = require('./dependencies-cache')

HEADER_PATTERN = ///
  ^ (
    (?:[\s]*) (
      (\/\* (?:.*?) \*\/) |
      (\#\#\# (?:.*?) \#\#\#) |
      (\/\/ .* \n?)+ |
      (\# .* \n?)+
    )
  )+
///gm

DIRECTIVE_PATTERN = ///
  ^
  \W* =   # the comment chars then an equal sign
  \s*
  (\w+)   # the directive command
  \s*
  (.*?)   # the arguments (maybe quoted, potentialy more than one?)

  (\*/)?  # just in case the line ends with a CSS comment (*/)
  $
///gm

REQUIREABLE_EXTENSIONS = [
  'sass'
  'scss'
  'css'

  'coffee'
  'jade'
  'js'

  'lyaml'
]


class DirectiveResolver
  constructor: (@config = {}) ->

    # Set default values
    @config = _.merge
      headerPattern: HEADER_PATTERN
      directivePattern: DIRECTIVE_PATTERN
      log: false
    , @config

    # A cache instance can be passed in to re-use dependency caches across different
    # build steps
    @sharedCache = @config.cache ? new DirectiveDependenciesCache

    if @config.log is true
      @log = console.log.bind 'console'

  log: -> # empty func by default, overidden in the constructor if @config.log is true

  extractHeader: (content) ->
    headerPattern = _.clone(@config.headerPattern)

    # Must be at the very beginning of the file
    # if match = content.match @config.headerPattern #and match?.index is 0
    if (match = headerPattern.exec(content)) and match?.index is 0
      match[0]

  getDependencyTreeFromDirectives: (relativePath, srcDir, tmpFileCache = [], depth = 0) ->
    targetFilePath = srcDir + '/' + relativePath

    # Skip any parsing/caclulation if this tree has already been calculated
    if @sharedCache.hasFile targetFilePath
      return @sharedCache.dependencyTreeForFile targetFilePath

    # Skip if this file has already added to this tree of dependencies
    # (really this should have already been checked and never reached here)
    if _.indexOf(tmpFileCache, targetFilePath) isnt -1
      return
    else
      tmpFileCache.push(targetFilePath)

    directivePattern = _.clone(@config.directivePattern) # clone regex for safety
    content = fs.readFileSync targetFilePath, 'utf8'
    tree = createTree
      relativePath: relativePath
      originalAbsolutePath: targetFilePath

    # Extract out all the directives from the header (directives can only appear
    # at the top of the file)
    header = @extractHeader content
    directiveResults = []

    while match = directivePattern.exec(header)
      [__, directive, directiveArgs] = match
      directiveArgs = shellwords.split directiveArgs

      directiveFunc = "_process_#{directive}_directive"

      if @[directiveFunc]?
        directiveResults = directiveResults.concat @[directiveFunc](targetFilePath, directiveArgs...)
      else
        throw new Error "Unknown directive #{directive} found in #{targetFilePath}"


    # For each path from the directives, recurse to get all of its dependencies
    # (unless that path had already been included).
    for directiveResult in directiveResults
      { resolvedDir: resolvedDirectiveDir, relativePath: relativeDirectivePath, fullDirectivePath } = directiveResult

      if _.indexOf(tmpFileCache, fullDirectivePath) isnt -1
        continue
      else
        depTree = @getDependencyTreeFromDirectives(relativeDirectivePath, resolvedDirectiveDir, tmpFileCache, depth + 1)

        # Ensure a tree was returned before appending
        tree.pushChildNode depTree if depTree?

    @sharedCache.storeDependencyTreeForFile relativePath, tree

    if depth is 0 and tree.size() > 1
      tree.debugPrint (v) -> v.relativePath

    return tree

  _process_require_directive: (parentPath, requiredPath, rest...) ->
    new Error("The require directive can only take one argument") if rest?.length > 0

    [resolvedDir, relativePath] = @resolveDirAndPath requiredPath,
      filename: parentPath
      loadPaths: @config.loadPaths

    [
      new DirectiveResult resolvedDir, relativePath,
        from: "require #{requiredPath}"
    ]

  _process_require_tree_directive: (parentPath, requiredDir) ->
    new Error("The require_tree directive can only take one argument") if rest?.length > 0

    [resolvedDir, relativePath] = @resolveDirAndPath requiredDir,
      filename: parentPath
      loadPaths: @config.loadPaths
      onlyDirectory: true

    dirPath = path.join resolvedDir, relativePath

    # Even though just a dir, call check extensions so that we look at the parent file
    # (the file the require came from) to see what kind of files we should filter
    # the directory for
    validExtensions = @_extensionsToCheck requiredDir,
      filename: parentPath

    # Gather all recursive files, exclude any that don't have a matching extension,
    # and then join with dir to create absolute paths
    walkSync(dirPath).filter (p) ->
      ext = path.extname(p).slice(1)
      ext isnt '' and ext in validExtensions
    .map (p) ->
      new DirectiveResult resolvedDir, relativePath + '/' + p,
        from: "require_tree #{requiredDir}"

  _process_require_directory_directive: (parentPath, requiredDir) ->
    new Error("The require_directory directive can only take one argument") if rest?.length > 0

    [resolvedDir, relativePath] = @resolveDirAndPath requiredDir,
      filename: parentPath
      loadPaths: @config.loadPaths
      onlyDirectory: true

    dirPath = path.join resolvedDir, relativePath

    # Even though just a dir, call check extensions so that we look at the parent file
    # (the file the require came from) to see what kind of files we should filter
    # the directory for
    validExtensions = @_extensionsToCheck requiredDir,
      filename: parentPath

    # Gather all directory files, exclude any that don't have a matching extension,
    # and then join with dir to create absolute paths
    fs.readdirSync(dirPath).filter (p) ->
      ext = path.extname(p).slice(1)
      ext isnt '' and ext in validExtensions
    .map (p) ->
      new DirectiveResult resolvedDir, relativePath + '/' + p,
        from: "require_directory #{requiredDir}"


  # TODO extract lang stuff to another filter (separate or that extends this one?)

  _prepare_require_lang_path: (parentPath, requiredPath, directive) ->
    if requiredPath.indexOf('*') is -1
      throw new Error "Cannot use #{directive} without including the language wildcard ('*')"
    else
      language = @_extractLanguageFromPath parentPath
      requiredPath = requiredPath.replace '*', language

  _process_require_lang_directive: (parentPath, requiredPath) ->
    requiredPath = @_prepare_require_lang_path parentPath, requiredPath, 'require_lang'
    @_process_require_directive.call this, parentPath, requiredPath

  _process_require_lang_tree_directive: (parentPath, requiredPath) ->
    requiredPath = @_prepare_require_lang_path parentPath, requiredPath, 'require_lang_tree'
    @_process_require_tree_directive.call this, parentPath, requiredPath

  _process_require_lang_directory_directive: (parentPath, requiredPath) ->
    requiredPath = @_prepare_require_lang_path parentPath, requiredPath, 'require_lang_directory'
    @_process_require_directory_directive.call this, parentPath, requiredPath

  _process_locales_to_render_directive: (parentPath, requiredLocales...) ->
    # TODO
    []



  # Resolve a path via the current filename (passed in via options.filename) and
  # among any of the passed loadPaths
  resolveDirAndPath: (inputPath, options = {}) ->
    throw new Error "Required filename option wasn't passed to resolvePath" unless options.filename?

    if options.onlyDirectory
      extensionToCheck = ''
    else
      extensionsToCheck = @_extensionsToCheck inputPath, options

    # If a relative path, we _don't_ want to look inside all of the loadPaths dirs
    # (since a relative path is always relative to the file it comes from).
    #
    # Also doing some mangle-ing to convert the directive's relative path into
    # a path that is relative to the srcDir
    if /^\.|^\.\.|^\.\.\//.test inputPath
      absolutizedPath = path.join path.dirname(options.filename), inputPath
      [resolvedBaseDir, newRelativePath] = extractBaseDirectoryAndRelativePath absolutizedPath, @config.loadPaths
      [resolvedDir, relativePath] = @_searchForPath newRelativePath, [resolvedBaseDir], extensionsToCheck
    else
      dirsToCheck = options.loadPaths ? []
      [resolvedDir, relativePath] = @_searchForPath inputPath, dirsToCheck, extensionsToCheck

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
  _searchForPath: (partialPath, dirsToCheck, extensionsToCheck = null) ->

    if not dirsToCheck? or dirsToCheck.length is 0
      throw new Error "Could not lookup #{partialPath} no search directories to check."

    originalExtension = extractExtension(partialPath, { onlyAllow: REQUIREABLE_EXTENSIONS })

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

  _extractLanguageFromPath: (inputPath) ->
    # TODO, make less ghetto (don't assume `<locale>.lyaml`)
    path.basename(inputPath, ".lyaml")

  _extensionsToCheck: (inputPath, options = {}) ->
    extension = extractExtension(inputPath, { onlyAllow: REQUIREABLE_EXTENSIONS })

    # If there was no valid extension on the passed path, get the extension from the
    # parent path (the file where the passed path came from)
    if extension is '' and options.filename?
      extension = extractExtension(options.filename, { onlyAllow: REQUIREABLE_EXTENSIONS })

    if extension in ['sass', 'scss', 'css'] and not options.excludePreprocessorExtensions
      ['sass', 'scss', 'css']
    else if extension in ['coffee', 'js', 'lyaml'] and not options.excludePreprocessorExtensions
      ['coffee', 'js', 'jade', 'lyaml', 'handlebars']
    else
      [extension]


# So extenions can be required
DirectiveResolver.REQUIREABLE_EXTENSIONS = REQUIREABLE_EXTENSIONS


# GHETTO TEST

# dr = new DirectiveResolver
#   loadPaths: [
#     '/Users/timmfin/.hubspot/static-archive'
#   ]

# testfile = '/Users/timmfin/dev/src/style_guide/static/js/style_guide_plus_layout.js'
# console.log "\n#{testfile}:\n#{dr.getDependencyTreeFromDirectives(testfile)}"

# testfile = '/Users/timmfin/dev/src/style_guide/static/js/style_guide.js'
# console.log "\n#{testfile}:\n#{dr.getDependencyTreeFromDirectives(testfile)}"

# testfile = '/Users/timmfin/dev/src/style_guide/static/sass/style_guide.sass'
# console.log "\n#{testfile}:\n#{dr.getDependencyTreeFromDirectives(testfile)}"

# testfile = "/Users/timmfin/dev/src/static-repo-utils/repo-store/cta/CtaUI/static/sass/app.sass"
# console.log "\n#{testfile}:\n#{dr.getDependencyTreeFromDirectives(testfile)}"


module.exports = DirectiveResolver

