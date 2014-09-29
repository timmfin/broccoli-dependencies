require('coffee-script/register');

module.exports = {
  DependenciesCache: require('./dependencies-cache'),

  CopyDependenciesFilter: require('./copy-dependencies'),

  BaseResolver: require('./base-resolver'),
  MultiResolver: require('./multi-resolver'),

  FileStruct: require('./file-struct'),
  Tree: require('./tree')
};
