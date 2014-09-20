'use strict'

fs = require('fs')
path = require('path')
_ = require('lodash')
shellwords = require("shellwords")
walkSync = require('walk-sync')
util = require('util')

BaseResovler = require('./base')
DependencyNode = require('../tree')


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

# File types that might have dirctives inside of them
POTENTIAL_DIRECTIVE_EXTENSIONS = [
  'sass'
  'scss'
  'css'

  'coffee'
  'js'
]

# File types that can be referenced from a directive
REQUIREABLE_EXTENSIONS = POTENTIAL_DIRECTIVE_EXTENSIONS.concat [
  'jade'
  'lyaml'
]


class SprocketsResolver extends BaseResovler
  type: 'sprockets'
  extensions: POTENTIAL_DIRECTIVE_EXTENSIONS

  constructor: (config = {}) ->
    super(config)

    # Set default values
    @config = _.merge
      headerPattern: HEADER_PATTERN
      directivePattern: DIRECTIVE_PATTERN
      log: false
    , @config

  @extractHeader: (content, customHeaderPattern = null) ->
    headerPattern = _.clone(customHeaderPattern ? HEADER_PATTERN)

    # Must be at the very beginning of the file
    # if match = content.match @config.headerPattern #and match?.index is 0
    if (match = headerPattern.exec(content)) and match?.index is 0
      match[0]

  extractHeader: (content) ->
    @constructor.extractHeader(@config.headerPattern)


  # Ensure that dependendencies are accessesed/followed by the finalized
  # extension, after any preprocessing
  modifyDependencyNode: (treeNode) ->
    parentRelativePath = treeNode.parent?.relativePath

    treeNode.value.sourceRelativePath = treeNode.value.relativePath
    treeNode.value.relativePath = convertFromPrepressorExtension treeNode.value.sourceRelativePath,
      parentFilename: parentRelativePath

  processDependenciesInContent: (content, relativePath, srcDir) ->
    targetFilePath = srcDir + '/' + relativePath

    # Extract out all the directives from the header (directives can only appear
    # at the top of the file)
    header = @constructor.extractHeader content
    directiveResults = []

    directivePattern = _.clone(@config.directivePattern) # clone regex for safety

    while match = directivePattern.exec(header)
      [__, directive, directiveArgs] = match
      directiveArgs = shellwords.split directiveArgs

      directiveFunc = "_process_#{directive}_directive"

      if @[directiveFunc]?
        directiveResults = directiveResults.concat @[directiveFunc](targetFilePath, directiveArgs...)
      else
        throw new Error "Unknown directive #{directive} found in #{targetFilePath}"

    directiveResults


  _process_require_directive: (parentPath, requiredPath, rest...) ->
    new Error("The require directive can only take one argument") if rest?.length > 0

    [resolvedDir, relativePath] = @resolveDirAndPath requiredPath,
      filename: parentPath
      loadPaths: @config.loadPaths
      allowDirectory: true

    # If the resolvedPath is a directory, look for an index.js|css file inside
    # of that directory
    if fs.statSync(resolvedDir + '/' + relativePath).isDirectory()
      indexRelativePath = relativePath + '/' + 'index'
      [resolvedDir, relativePath] = @resolveDirAndPath indexRelativePath,
        filename: parentPath
        loadPaths: [resolvedDir]

    [
      @createDependency resolvedDir, relativePath,
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
    .map (p) =>
      @createDependency resolvedDir, relativePath + '/' + p,
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
    validExtensions = @extensionsToCheck requiredDir,
      filename: parentPath

    # Gather all directory files, exclude any that don't have a matching extension,
    # and then join with dir to create absolute paths
    fs.readdirSync(dirPath).filter (p) ->
      ext = path.extname(p).slice(1)
      ext isnt '' and ext in validExtensions
    .map (p) =>
      @createDependency resolvedDir, relativePath + '/' + p,
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



  _extractLanguageFromPath: (inputPath) ->
    # TODO, make less ghetto (don't assume `<locale>.lyaml`)
    path.basename(inputPath, ".lyaml")

  extensionsToCheck: (inputPath, options = {}) ->
    [extension] = super inputPath, options

    # Also include any potential preprocesser extensions
    if extension in ['sass', 'scss', 'css']
      ['sass', 'scss', 'css']
    else if extension in ['coffee', 'js', 'lyaml', 'handlebars']
      ['coffee', 'js', 'jade', 'lyaml', 'handlebars']
    else
      [extension]


# So extenions can be required
SprocketsResolver.REQUIREABLE_EXTENSIONS = REQUIREABLE_EXTENSIONS




class RequireTreeNode extends DependencyNode
  allRequiredDependenciesAsHTML: (options = {}) ->
    formatValue = options.formatValue ? (v) -> v

    if not options.expandedDebugMode
      @_htmlToIncludeDep(this, @relativePath)
    else
      console.log "Generating expanded HTML for #{@relativePath}"
      dependenciesHTMLContent = []

      @traverse (node, visitChildren) =>
        val = formatValue(node.relativePath)

        dependenciesHTMLContent.push @_preIncludeComment(node, val) if node.children.length > 0

        visitChildren()

        dependenciesHTMLContent.push @_htmlToIncludeDep(node, val)
        dependenciesHTMLContent.push @_postIncludeComment(node, val) if node.children.length > 0

      dependenciesHTMLContent.join('\n').replace(/\n\n\n/g, '\n\n').replace(/^\n/, '')

  _preIncludeComment: (node, formattedValue) ->
    extra = ''
    extra = "(total files: #{node.size()})" if node.isRoot()

    "\n<!-- From #{formattedValue} #{extra} -->"

  _postIncludeComment: (node, formattedValue) ->
    "<!-- End #{formattedValue} -->\n"

  _htmlToIncludeDep: (node, formattedValue) ->
    val = formattedValue
    val = "/#{val}" unless val[0] is '/'

    ext = extractExtension val

    if ext is 'js'
      """<script src="#{val}" type="text/javascript"></script>"""
    else if ext is 'css'
      """<link href="#{val}" rel="stylesheet" type="text/css" />"""
    else
      throw new Error "Can't create HTML element for unkown file type: #{formattedValue}"





# GHETTO TEST

# dr = new SprocketsResolver
#   loadPaths: [
#     '/Users/timmfin/.hubspot/static-archive'
#   ]

# testfile = '/Users/timmfin/dev/src/style_guide/static/js/style_guide_plus_layout.js'
# console.log "\n#{testfile}:\n#{dr.getDependencyTree(testfile)}"

# testfile = '/Users/timmfin/dev/src/style_guide/static/js/style_guide.js'
# console.log "\n#{testfile}:\n#{dr.getDependencyTree(testfile)}"

# testfile = '/Users/timmfin/dev/src/style_guide/static/sass/style_guide.sass'
# console.log "\n#{testfile}:\n#{dr.getDependencyTree(testfile)}"

# testfile = "/Users/timmfin/dev/src/static-repo-utils/repo-store/cta/CtaUI/static/sass/app.sass"
# console.log "\n#{testfile}:\n#{dr.getDependencyTree(testfile)}"


module.exports = SprocketsResolver
