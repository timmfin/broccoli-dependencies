
stripBaseDirectory = (filepath, baseDirs) ->
  for baseDir in baseDirs
    baseDir = "#{baseDir}/" unless baseDir[baseDir.length - 1] is '/'  # Ensure trailing slash

    if filepath.indexOf(baseDir) is 0
      return filepath.replace(baseDir, '')

  throw new Error "#{filepath} isn't in any of #{baseDirs.join(', ')}"


module.exports = {
  stripBaseDirectory
}
