path = require('path')

# Basic little class to simply directive proccessing
module.exports = class DirectiveResult
  constructor: (@resolvedDir, @relativePath, @debugInfo) ->
    @fullDirectivePath = path.join @resolvedDir, @relativePath


