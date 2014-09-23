'use strict'

path = require('path')

BaseResovler = require('./base')


class SassDependenciesResolver extends BaseResovler
  type: 'sass'

  extensions: [
    'sass'
    'scss'
  ]

  compassFrameworks: [
    'compass'
    'breakpoint'
    'animation'
  ]

  processDependenciesInContent: (content, relativePath, srcDir) ->
    depKeywordRegex = ///
      ^ \s*

      @import       # the import keyword
      \s*
      (['"])?       # optional quotes
      (.*)          # import path
      \1            # optional end quotes

      \s* ;? \s*$   # optional ending semicolon (and whitespace)
    ///gm

    depPaths = []
    depObjects = []
    absolutePath = srcDir + '/' + relativePath

    while match = depKeywordRegex.exec(content)
      importedPath = match[2]

      if @_isFrameworkPath importedPath
        # Skipping
      else
        depPaths.push importedPath


    for relativeDepPath in depPaths

      # Also search in '_<filename>' (Sass partials)
      basename = path.basename relativeDepPath
      alsoTryPartial = basename[0] isnt '_'

      try
        [resolvedDepDir, relativeDepPath] = @resolveDirAndPath relativeDepPath,
          filename: absolutePath
          loadPaths: @config.loadPaths
      catch e
        if alsoTryPartial
          prefixedRelativeDepPath = relativeDepPath.slice(0, -1 * basename.length) + '_' + basename

          [resolvedDepDir, relativeDepPath] = @resolveDirAndPath prefixedRelativeDepPath,
            filename: absolutePath
            loadPaths: @config.loadPaths
        else
          throw e

      if relativeDepPath?
        depObjects.push @createDependency(resolvedDepDir, relativeDepPath)
      else
        throw new Error "Couldn't find #{relativeDepPath} in any of these directories: #{baseDirs.join(', ')}"

    depObjects

  _isFrameworkPath: (importedPath) ->
    for framework in @compassFrameworks
      regex = ///
        ^
        #{framework}
        \b
      ///

      return true if regex.test(importedPath)

  extensionsToCheck: (inputPath, options = {}) ->
    [extension] = super inputPath, options

    # Also include any potential preprocesser extensions
    if extension in ['sass', 'scss', 'css']
      ['sass', 'scss', 'css']
    else
      [extension]




module.exports = SassDependenciesResolver

