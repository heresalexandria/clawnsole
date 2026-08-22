const assert = require('node:assert/strict');
const path = require('node:path');
const test = require('node:test');

const { bundledCompanionArguments } = require('../lib/companion-launch.cjs');

test('bundled companion receives the signed media tool directory', () => {
  const argumentsList = bundledCompanionArguments({
    port: 8787,
    dataFile: '/Library/Application Support/Clawnsole/data.json',
    rendererDirectory: '/Applications/Clawnsole.app/Contents/Resources/renderer',
    resourcesPath: '/Applications/Clawnsole.app/Contents/Resources',
  });

  const mediaIndex = argumentsList.indexOf('--media-tools-dir');
  assert.notEqual(mediaIndex, -1);
  assert.equal(
    argumentsList[mediaIndex + 1],
    path.join(
      '/Applications/Clawnsole.app/Contents/Resources',
      'media-tools',
    ),
  );
  assert.equal(argumentsList.at(-1), '--secure-bootstrap');
});
