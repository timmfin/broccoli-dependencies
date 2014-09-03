'use strict'

fs = require('fs')
path = require('path')
_ = require('lodash')
shellwords = require("shellwords")
walkSync = require('walk-sync')


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
    @fileCache = []
    @filesReturned = []

    # Set default values
    @config = _.merge
      headerPattern: HEADER_PATTERN
      directivePattern: DIRECTIVE_PATTERN
      log: true
    , @config

    if @config.log is true
      @log = console.log.bind 'console'

  log: -> # empty func by default, overidden in the constructor if @config.log is true

  extractHeader: (content) ->
    headerPattern = _.clone(@config.headerPattern)
    headerLines = []

    # Must be at the very beginning of the file
    # if match = content.match @config.headerPattern #and match?.index is 0
    if (match = headerPattern.exec(content)) and match?.index is 0
      match[0]

  getFiles: (targetFilePath) ->
    directivePattern = _.clone(@config.directivePattern)
    files = []

    # Skip if already added to dependencies
    if _.indexOf(@fileCache, targetFilePath) isnt -1
      return false
    else
      @fileCache.push(targetFilePath)

    content = fs.readFileSync targetFilePath, 'utf8'
    header = @extractHeader content

    while match = directivePattern.exec(header)
      # console.log "match", match

      [__, directive, directiveArgs] = match
      directiveArgs = shellwords.split directiveArgs

      directiveFunc = "_process_#{directive}_directive"

      if @[directiveFunc]?
        dependencyPaths = @[directiveFunc] targetFilePath, directiveArgs...
      else
        throw new Error "Unknown directive #{directive} found in #{targetFilePath}"

      for depPath in dependencyPaths
        # Skip if already added to dependencies
        if _.indexOf(@fileCache, depPath) isnt -1
          continue
        else
          # Get new dependencies
          while dependencies = @getFiles(depPath)
            files = files.concat(dependencies)

    # Add file itself
    files.push(targetFilePath)

    if files.length > 1
      @log "\n\nDeps for #{targetFilePath}"
      @log "  #{files.join('\n  ')}"

    return files

  _process_require_directive: (parentPath, requiredPath, rest...) ->
    new Error("The require directive can only take one argument") if rest?.length > 0

    filePath = @resolvePath requiredPath,
      filename: parentPath
      loadPaths: @config.loadPaths

    [filePath]


  _process_require_tree_directive: (parentPath, requiredDir) ->
    new Error("The require_tree directive can only take one argument") if rest?.length > 0

    dirPath = @resolvePath requiredDir,
      filename: parentPath
      loadPaths: @config.loadPaths
      onlyDirectory: true

    validExtensions = @_extensionsToCheck requiredDir,
      filename: parentPath

    # Gather all recursive files, exclude any that don't have a matching extension,
    # and then join with dir to create absolute paths
    walkSync(dirPath).filter (p) ->
      ext = path.extname(p).slice(1)
      ext isnt '' and ext in validExtensions
    .map (p) ->
      path.join dirPath, p

  _process_require_directory_directive: (parentPath, requiredDir) ->
    new Error("The require_directory directive can only take one argument") if rest?.length > 0

    dirPath = @resolvePath requiredDir,
      filename: parentPath
      loadPaths: @config.loadPaths
      onlyDirectory: true

    validExtensions = @_extensionsToCheck requiredDir,
      filename: parentPath

    # Gather all directory files, exclude any that don't have a matching extension,
    # and then join with dir to create absolute paths
    fs.readdirSync(dirPath).filter (p) ->
      ext = path.extname(p).slice(1)
      console.log ' d ', p, ext, ext isnt '' and ext in validExtensions
      ext isnt '' and ext in validExtensions
    .map (p) ->
      path.join dirPath, p


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



  # Resolve a path via the current filename (passed in via options.filename) and
  # among any of the passed loadPaths
  resolvePath: (inputPath, options = {}) ->
    throw new Error "Required filename option wasn't passed to resolvePath" unless options.filename?

    if options.onlyDirectory
      extensionToCheck = ''
    else
      extensionsToCheck = @_extensionsToCheck inputPath, options

    # If a relative path, we _don't_ want to look inside all of the loadPaths dirs
    # (since a relative path is always relative to the file it comes from)
    if /^\.\.?\//.test inputPath
      dirsToCheck = [path.dirname(options.filename)]
    else
      dirsToCheck = [path.dirname(options.filename)].concat(options.loadPaths ? [])

    resolvedPath = @_searchForPath inputPath, dirsToCheck, extensionsToCheck

    # Throw a useful error if no path is found. Otherwise return the first successful
    # path found by _searchForPath
    if not resolvedPath
      inputPathText = "#{inputPath}"

      if extensionsToCheck?.length > 0
        originalExtension = @_extractExtension inputPath
        inputPathText = "#{inputPath.replace(new RegExp('.' + originalExtension + '$'), '')}.#{extensionsToCheck.join('|')}"

      throw new Error "Could not find #{inputPathText} among: #{dirsToCheck}"
    else
      resolvedPath

  # See if partialPath exists inside any of dirsToCheck optionally with a number of
  # different extensions
  _searchForPath: (partialPath, dirsToCheck, extensionsToCheck = null) ->

    if not dirsToCheck? or dirsToCheck.length is 0
      throw new Error "Could not lookup #{partialPath} no search directories to check."

    originalExtension = @_extractExtension(partialPath)

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
          return pathToCheck


  _extractExtension: (inputPath) ->
    extension = path.extname(inputPath).slice(1)
    extension = '' unless extension in REQUIREABLE_EXTENSIONS
    extension

  _extractLanguageFromPath: (inputPath) ->
    # TODO, make less ghetto (don't assume `<locale>.lyaml`)
    path.basename(inputPath, ".lyaml")

  _extensionsToCheck: (inputPath, options = {}) ->
    extension = @_extractExtension(inputPath)

    # If there was no valid extension on the passed path, get the extension from the
    # parent path (the file where the passed path came from)
    if extension is '' and options.filename?
      extension = @_extractExtension(options.filename)

    if extension in ['sass', 'scss', 'css'] and not options.excludePreprocessorExtensions
      ['sass', 'scss', 'css']
    else if extension in ['coffee', 'js', 'lyaml'] and not options.excludePreprocessorExtensions
      ['coffee', 'js', 'jade', 'lyaml']
    else
      [extension]




# GHETTO TEST

# dr = new DirectiveResolver
#   loadPaths: [
#     '/Users/timmfin/.hubspot/static-archive'
#   ]

# testfile = '/Users/timmfin/dev/src/style_guide/static/js/style_guide_plus_layout.js'
# console.log "\n#{testfile}:\n#{dr.getFiles(testfile)}"

# testfile = '/Users/timmfin/dev/src/style_guide/static/js/style_guide.js'
# console.log "\n#{testfile}:\n#{dr.getFiles(testfile)}"

# testfile = '/Users/timmfin/dev/src/style_guide/static/sass/style_guide.sass'
# console.log "\n#{testfile}:\n#{dr.getFiles(testfile)}"

# testfile = "/Users/timmfin/dev/src/static-repo-utils/repo-store/cta/CtaUI/static/sass/app.sass"
# console.log "\n#{testfile}:\n#{dr.getFiles(testfile)}"


module.exports = DirectiveResolver

