const path = require('node:path');

function bundledCompanionArguments({
  port,
  dataFile,
  rendererDirectory,
  resourcesPath,
  mediaHostJournalFile,
}) {
  return [
    '--port',
    String(port),
    '--data-file',
    dataFile,
    ...(mediaHostJournalFile ? ['--media-host-journal', mediaHostJournalFile] : []),
    '--web-root',
    rendererDirectory,
    '--media-tools-dir',
    path.join(resourcesPath, 'media-tools'),
    '--icloud-host-helper',
    path.join(resourcesPath, 'native-tools', 'clawnsole_icloud_host'),
    '--secure-bootstrap',
  ];
}

module.exports = { bundledCompanionArguments };
