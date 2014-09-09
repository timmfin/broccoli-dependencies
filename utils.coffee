path = require('path')


extractBaseDirectory = (filepath, baseDirs) ->
  for baseDir in baseDirs
    baseDir = "#{baseDir}/" unless baseDir[baseDir.length - 1] is '/'  # Ensure trailing slash

    if filepath.indexOf(baseDir) is 0
      return baseDir

  throw new Error "#{filepath} isn't in any of #{baseDirs.join(', ')}"

extractBaseDirectoryAndRelativePath = (filepath, baseDirs) ->
  resolvedBaseDir = extractBaseDirectory filepath, baseDirs
  relativePath = filepath.replace(resolvedBaseDir, '')
  [resolvedBaseDir, relativePath]

stripBaseDirectory = (filepath, baseDirs) ->
  [resolvedBaseDir, relativePath] = extractBaseDirectoryAndRelativePath filepath, baseDirs
  relativePath

convertFromPrepressorExtension = (filepath, options = {}) ->
  extension = extractExtension(filepath)

  # If there was no valid extension on the passed path, get the extension from the
  # parent path (the file where the passed path came from)
  if extension is '' and options.parentFilename?
    extension = extractExtension(options.parentFilename)

  if extension in ['sass', 'scss']
    newExtension = 'css'
  else if extension in ['coffee', 'jade', 'lyaml', 'handlebars']
    newExtension = 'js'

  if newExtension
    filepath.replace(new RegExp("\\.#{extension}$"), ".#{newExtension}")
  else
    filepath

extractExtension = (filepath, options = {}) ->
  extension = path.extname(filepath).slice(1)

  if options.onlyAllow? and not(extension in options.onlyAllow)
    extension = ''

  extension


module.exports = {
  stripBaseDirectory
  extractBaseDirectory
  extractBaseDirectoryAndRelativePath
  extractExtension
  convertFromPrepressorExtension
}
