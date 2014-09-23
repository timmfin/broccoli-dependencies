
createGetter = (klass, prop, get) ->
  Object.defineProperty klass, prop, {get, configurable: yes}


class FileStruct
  constructor: (@srcDir, @relativePath, @extra = {}) ->

  createGetter @::, 'originalAbsolutePath', ->
    "#{@srcDir}/#{@sourceRelativePath ? @relativePath}"



module.exports = FileStruct
