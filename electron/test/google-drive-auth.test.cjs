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

test("silent authorization refreshes a stored token without any interactive flow", async () => {
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
  let serversStarted = 0;
  const auth = new GoogleDriveAuth({
    clientId: "desktop-client",
    userData: directory,
    safeStorage,
    openExternal: async () => {
      throw new Error("silent authorization must never open a browser");
    },
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return {
        ok: true,
        status: 200,
        json: async () => ({ access_token: "fresh-access-token" }),
      };
    },
    createServer: () => {
      serversStarted += 1;
      throw new Error("silent authorization must never start a callback server");
    },
  });

  try {
    assert.equal(await auth.authorizeSilently(), "fresh-access-token");
    assert.equal(serversStarted, 0);
    assert.equal(requests.length, 1);
    assert.equal(requests[0].url, "https://oauth2.googleapis.com/token");
    assert.equal(requests[0].options.body.get("grant_type"), "refresh_token");
    assert.equal(requests[0].options.body.get("refresh_token"), "refresh-token");
    await fs.access(tokenFile);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

test("silent authorization forgets a refresh token Google rejects", async () => {
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
      encrypted: Buffer.from("encrypted:stale-token").toString("base64"),
    }),
  );
  let serversStarted = 0;
  const auth = new GoogleDriveAuth({
    clientId: "desktop-client",
    userData: directory,
    safeStorage,
    openExternal: async () => {
      throw new Error("silent authorization must never open a browser");
    },
    fetchImpl: async () => ({
      ok: false,
      status: 400,
      json: async () => ({ error: "invalid_grant", error_description: "Token has been revoked." }),
    }),
    createServer: () => {
      serversStarted += 1;
      throw new Error("silent authorization must never start a callback server");
    },
  });

  try {
    assert.equal(await auth.authorizeSilently(), "");
    assert.equal(serversStarted, 0);
    await assert.rejects(fs.access(tokenFile));
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});

for (const [label, failure] of [
  ["offline", async () => { throw new TypeError("fetch failed: offline"); }],
  ["timeout", async () => { throw new DOMException("timed out", "TimeoutError"); }],
  ["server error", async () => ({ ok: false, status: 503, json: async () => ({ error: "temporarily_unavailable" }) })],
  ["rate limit", async () => ({ ok: false, status: 429, json: async () => ({ error: "rate_limit_exceeded" }) })],
  ["client configuration", async () => ({ ok: false, status: 400, json: async () => ({ error: "invalid_client" }) })],
  ["malformed JSON", async () => ({ ok: false, status: 502, json: async () => { throw new SyntaxError("bad JSON"); } })],
  ["invalid-grant body on a server failure", async () => ({ ok: false, status: 503, json: async () => ({ error: "invalid_grant" }) })],
]) {
  for (const method of ["authorizeSilently", "authorize"]) {
    test(`${method} preserves a refresh token after ${label} and retries it`, async (t) => {
      const directory = await fs.mkdtemp(path.join(os.tmpdir(), "clawnsole-drive-auth."));
      t.after(() => fs.rm(directory, { recursive: true, force: true }));
      const tokenFile = path.join(directory, "google-drive-auth.json");
      const stored = JSON.stringify({ encrypted: Buffer.from("encrypted:fake-refresh").toString("base64") });
      await fs.writeFile(tokenFile, stored);
      let recovered = false;
      const auth = new GoogleDriveAuth({
        clientId: "desktop-client",
        userData: directory,
        safeStorage: {
          isEncryptionAvailable: () => true,
          decryptString: (value) => value.toString().replace(/^encrypted:/, ""),
        },
        openExternal: async () => { throw new Error("transient failure must not open a browser"); },
        createServer: () => { throw new Error("transient failure must not start interactive authorization"); },
        fetchImpl: async (_url, options) => {
          assert.equal(options.body.get("refresh_token"), "fake-refresh");
          assert.ok(options.signal instanceof AbortSignal);
          return recovered
            ? { ok: true, status: 200, json: async () => ({ access_token: "recovered-access" }) }
            : failure();
        },
      });
      if (method === "authorizeSilently") assert.equal(await auth[method](), "");
      else await assert.rejects(auth[method]());
      assert.equal(await fs.readFile(tokenFile, "utf8"), stored);
      recovered = true;
      assert.equal(await auth[method](), "recovered-access");
    });
  }
}

test("silent authorization returns nothing when no token is stored", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "clawnsole-drive-auth."));
  const safeStorage = {
    isEncryptionAvailable: () => true,
    encryptString: (value) => Buffer.from(`encrypted:${value}`),
    decryptString: (value) => value.toString().replace(/^encrypted:/, ""),
  };
  const requests = [];
  const auth = new GoogleDriveAuth({
    clientId: "desktop-client",
    userData: directory,
    safeStorage,
    openExternal: async () => {
      throw new Error("silent authorization must never open a browser");
    },
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return { ok: true, status: 200, json: async () => ({}) };
    },
    createServer: () => {
      throw new Error("silent authorization must never start a callback server");
    },
  });

  try {
    assert.equal(await auth.authorizeSilently(), "");
    assert.equal(requests.length, 0);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
});
