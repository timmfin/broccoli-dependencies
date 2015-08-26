symlinkOrCopy  = require('symlink-or-copy')

class CopyProjectDependenciesFilter extends CopyDependenciesFilter

  constructor: (inputTree, options = {}) ->
    if not (this instanceof CopyDependenciesFilter)
      return new CopyProjectDependenciesFilter(inputTree, options)

    super

  # Override symlink/copy behavior since we can optimize since we know this is a project

  # Symlink all top-level directories in the input path (allows us to not need
  # to symlink _any_ files in `onVisitedFileInInputTree()`)
  onVisitedDirectory: (srcDir, relativePath, destDir) ->
    relativePathMinusSlash = relativePath.slice(0, relativePath.length - 1)
    isTopLevelDirectory = relativePathMinusSlash.split('/').length is 1

    if isTopLevelDirectory
      symlinkOrCopy.sync srcDir + '/' + relativePathMinusSlash, destDir + '/' + relativePathMinusSlash

  onVisitedFileInInputTree: (srcDir, relativePath, wasProcessed, destDir, outputPath) ->
    # Do nothing
    #
    # We don't need to symlink files that are processed, since we've already
    # symlinked all of the top-level directories in from the inputPath


module.exports = CopyProjectDependenciesFilter
