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

test('temporary media recovery stays in user data when the library moves', () => {
  const journal = '/Users/director/Library/Application Support/Clawnsole/temporary-media-leases.json';
  const argumentsList = bundledCompanionArguments({
    port: 8787,
    dataFile: '/Volumes/Films/Clawnsole/data.json',
    rendererDirectory: '/Applications/Clawnsole.app/Contents/Resources/renderer',
    resourcesPath: '/Applications/Clawnsole.app/Contents/Resources',
    mediaHostJournalFile: journal,
  });
  assert.equal(argumentsList[argumentsList.indexOf('--media-host-journal') + 1], journal);
  assert.equal(argumentsList[argumentsList.indexOf('--data-file') + 1], '/Volumes/Films/Clawnsole/data.json');
});
