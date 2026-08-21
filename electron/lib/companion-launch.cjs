const path = require('node:path');

function bundledCompanionArguments({
  port,
  dataFile,
  rendererDirectory,
  resourcesPath,
}) {
  return [
    '--port',
    String(port),
    '--data-file',
    dataFile,
    '--web-root',
    rendererDirectory,
    '--media-tools-dir',
    path.join(resourcesPath, 'media-tools'),
    '--secure-bootstrap',
  ];
}

module.exports = { bundledCompanionArguments };
