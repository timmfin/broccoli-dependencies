'use strict'

Promise = require('rsvp').Promise
path = require('path')
fs = require('fs')

Filter = require('broccoli-filter')
DirectiveResolver = require('./directive-resolver')


class DirectiveFilter extends Filter

  extensions: [
    'js'
    'css'
  ]

  constructor: (inputTree, options = {}) ->
    if not (this instanceof DirectiveFilter)
      return new DirectiveFilter(inputTree, options)

    @inputTree = inputTree
    @options = options


  processFile: (srcDir, destDir, relativePath) ->

    # DEBUGGING
    debugContent = fs.readFileSync(srcDir + '/' + relativePath, { encoding: 'utf8' })

    return Promise.resolve(@processFileForDirectives(relativePath, srcDir))
      .then (outputString) =>
        outputPath = @getDestFilePath(relativePath)
        # TODO
        # fs.writeFileSync(destDir + '/' + outputPath, outputString, { encoding: 'utf8' })

        fs.writeFileSync(destDir + '/' + outputPath, debugContent, { encoding: 'utf8' })

  processFileForDirectives: (relativePath, srcDir) ->
    currentPath = path.join srcDir, relativePath

    directiveResolver = new DirectiveResolver
      loadPaths: [srcDir].concat(@options.loadPaths)

    directiveResolver.getFiles(currentPath)

    return "TODO"


module.exports = DirectiveFilter
