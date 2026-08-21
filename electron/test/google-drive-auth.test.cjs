"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  GoogleDriveAuth,
  configuredOAuth,
  DRIVE_SCOPE,
} = require("../lib/google-drive-auth.cjs");
const {
  oauthResultPage,
} = require("../lib/google-drive-auth-page.cjs");

test("OAuth result pages carry the Clawnsole site identity", () => {
  const success = oauthResultPage(true);
  const failure = oauthResultPage(false);

  assert.match(success, /<title>Clawnsole connected<\/title>/);
  assert.match(success, /You’re connected\./);
  assert.match(success, /Authorization complete/);
  assert.match(success, /data:image\/png;base64,/);
  assert.match(success, /color-scheme: light dark/);
  assert.match(success, /--paper: light-dark\(#f8f3e8, #171116\)/);
  assert.match(success, /--plum: light-dark\(#5a2856, #d2a0ca\)/);
  assert.match(success, /font-family: Georgia/);
  assert.match(
    success,
    /\.status-icon\s*{[\s\S]*?display: grid;[\s\S]*?place-items: center;/,
  );
  assert.doesNotMatch(success, /\.status span\s*{\s*display: block;/);

  assert.match(failure, /<title>Clawnsole connection not completed<\/title>/);
  assert.match(failure, /Connection not completed\./);
  assert.match(failure, /No Drive files were changed\./);
  assert.doesNotMatch(failure, /Authorization complete/);
});

test("OAuth configuration prefers process values and exposes only drive.file", () => {
  const previous = process.env.CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID;
  process.env.CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID = "environment-client";
  try {
    assert.deepEqual(configuredOAuth({ googleOAuthClientId: "package-client" }), {
      clientId: "environment-client",
      clientSecret: "",
    });
    assert.equal(DRIVE_SCOPE, "https://www.googleapis.com/auth/drive.file");
  } finally {
    if (previous === undefined) {
      delete process.env.CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID;
    } else {
      process.env.CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID = previous;
    }
  }
});

test("a desktop refresh token stays encrypted at rest and refreshes silently", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "clawnsole-drive-auth."));
  const tokenFile = path.join(directory, "google-drive-auth.json");
  const safeStorage = {
    isEncryptionAvailable: () => true,
    encryptString: (value) => Buffer.from(`encrypted:${value}`),
    decryptString: (value) => value.toString().replace(/^encrypted:/, ""),
  };
  await fs.writeFile(
    tokenFile,
    JSON.stringify({
      encrypted: Buffer.from("encrypted:refresh-token").toString("base64"),
    }),
  );
  const requests = [];
  const auth = new GoogleDriveAuth({
    clientId: "desktop-client",
    userData: directory,
    safeStorage,
    openExternal: async () => {},
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return {
        ok: true,
        status: 200,
        json: async () => ({ access_token: "fresh-access-token" }),
      };
    },
  });

  try {
    assert.equal(await auth.authorize(), "fresh-access-token");
    assert.equal(requests.length, 1);
    assert.equal(requests[0].url, "https://oauth2.googleapis.com/token");
    assert.equal(requests[0].options.body.get("refresh_token"), "refresh-token");

    await auth.disconnect();
    assert.equal(requests[1].url, "https://oauth2.googleapis.com/revoke");
    await assert.rejects(fs.access(tokenFile));
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});
