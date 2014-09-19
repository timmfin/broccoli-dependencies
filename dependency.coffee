
createGetter = (klass, prop, get) ->
  Object.defineProperty klass, prop, {get, configurable: yes}


class Dependency
  constructor: (@srcDir, @relativePath, @extra = {}) ->

  createGetter @::, 'originalAbsolutePath', ->
    "#{@srcDir}/#{@relativePath}"



module.exports = Dependency
