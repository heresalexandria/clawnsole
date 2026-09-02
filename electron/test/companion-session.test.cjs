"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");

const {
  companionBootstrapLine,
  installCompanionSessionHeader,
  is32ByteBase64Url,
  MAX_VAULT_VALUE_BYTES,
  proxySettingsVault,
  SESSION_HEADER,
  validateVaultRequest,
} = require("../lib/companion-session.cjs");

const rendererUrl = "http://127.0.0.1:43123";
const requestToken = crypto.randomBytes(32).toString("base64url");

test("companion tokens are canonical base64url 32-byte values", () => {
  assert.equal(is32ByteBase64Url(requestToken), true);
  assert.equal(is32ByteBase64Url("short"), false);
  assert.equal(is32ByteBase64Url(`${requestToken}=`), false);
});

test("the packaged companion bootstrap is one validated JSON line", () => {
  const deviceKey = crypto.randomBytes(32).toString("base64url");
  const line = companionBootstrapLine(deviceKey, requestToken);
  assert.equal(line.endsWith("\n"), true);
  assert.equal(line.slice(0, -1).includes("\n"), false);
  assert.deepEqual(JSON.parse(line), { deviceKey, requestToken });
  assert.throws(() => companionBootstrapLine("short", requestToken), /invalid/i);
});

test("the session header is confined to the renderer origin", () => {
  let listener;
  const webRequest = {
    onBeforeSendHeaders: (_filter, value) => {
      listener = value;
    },
  };
  installCompanionSessionHeader(webRequest, rendererUrl, requestToken);

  let local;
  listener(
    {
      url: `${rendererUrl}/state`,
      requestHeaders: { Accept: "application/json" },
    },
    (value) => {
      local = value;
    },
  );
  assert.equal(local.requestHeaders[SESSION_HEADER], requestToken);

  let external;
  listener(
    {
      url: "https://api.bfl.ai/v1/generations",
      requestHeaders: { Accept: "application/json" },
    },
    (value) => {
      external = value;
    },
  );
  assert.equal(external.requestHeaders[SESSION_HEADER], undefined);
  assert.equal(external.requestHeaders.Accept, "application/json");
});

// A restarted companion keeps its session token but can come back on another
// port, and the token must follow the live origin without ever leaking to the
// dead one.
test("the session header follows a restarted companion's origin", () => {
  let listener;
  const webRequest = {
    onBeforeSendHeaders: (_filter, value) => {
      listener = value;
    },
  };
  const session = installCompanionSessionHeader(
    webRequest,
    rendererUrl,
    requestToken,
  );
  const headersFor = (url) => {
    let result;
    listener({ url, requestHeaders: {} }, (value) => {
      result = value;
    });
    return result.requestHeaders;
  };

  const movedUrl = "http://127.0.0.1:43124";
  assert.equal(headersFor(`${rendererUrl}/state`)[SESSION_HEADER], requestToken);
  assert.equal(headersFor(`${movedUrl}/state`)[SESSION_HEADER], undefined);

  session.rebind(movedUrl);
  assert.equal(headersFor(`${movedUrl}/state`)[SESSION_HEADER], requestToken);
  assert.equal(headersFor(`${rendererUrl}/state`)[SESSION_HEADER], undefined);

  assert.throws(() => session.rebind("not a URL"), /invalid/i);
  assert.equal(headersFor(`${movedUrl}/state`)[SESSION_HEADER], requestToken);
});

test("settings-vault requests use a strict action and value contract", () => {
  assert.deepEqual(validateVaultRequest("setup", "a passphrase"), {
    action: "setup",
    value: "a passphrase",
  });
  assert.deepEqual(validateVaultRequest("sync"), {
    action: "sync",
    value: "",
  });
  assert.throws(() => validateVaultRequest("../../state", "value"), /action/i);
  assert.throws(() => validateVaultRequest("unlock", ""), /value/i);
  assert.throws(() => validateVaultRequest("forget", "value"), /does not accept/i);
  assert.throws(
    () => validateVaultRequest("recover", "x".repeat(MAX_VAULT_VALUE_BYTES + 1)),
    /value/i,
  );
});

test("vault proxy authenticates requests and returns only approved fields", async () => {
  const seen = [];
  const result = await proxySettingsVault({
    action: "setup",
    value: "correct horse battery staple",
    rendererUrl,
    requestToken,
    fetchImpl: async (url, options) => {
      seen.push({ url, options });
      return {
        ok: true,
        text: async () => JSON.stringify({
          ok: true,
          state: "unlocked",
          message: "Vault ready.",
          syncedAt: "2026-08-20T12:00:00Z",
          recoveryCode: "recovery-code",
          deviceKey: "must-not-cross-the-bridge",
          apiKeys: { bfl: "must-not-cross-the-bridge" },
        }),
      };
    },
  });

  assert.equal(seen.length, 1);
  assert.equal(seen[0].url.toString(), `${rendererUrl}/vault/setup`);
  assert.equal(seen[0].options.headers[SESSION_HEADER], requestToken);
  assert.deepEqual(JSON.parse(seen[0].options.body), {
    value: "correct horse battery staple",
  });
  assert.deepEqual(result, {
    ok: true,
    state: "unlocked",
    message: "Vault ready.",
    syncedAt: "2026-08-20T12:00:00Z",
    recoveryCode: "recovery-code",
  });
});

test("recovery codes only cross the bridge after successful setup", async () => {
  for (const action of ["unlock", "recover", "changePassphrase"]) {
    const result = await proxySettingsVault({
      action,
      value: "value",
      rendererUrl,
      requestToken,
      fetchImpl: async () => ({
        ok: true,
        text: async () => JSON.stringify({
          ok: true,
          state: "unlocked",
          recoveryCode: "must-not-cross-the-bridge",
        }),
      }),
    });
    assert.equal(result.recoveryCode, undefined);
  }
});

test("invalid and failed vault proxy requests return sanitized errors", async () => {
  let called = false;
  assert.deepEqual(
    await proxySettingsVault({
      action: "unknown",
      value: "secret",
      rendererUrl,
      requestToken,
      fetchImpl: async () => {
        called = true;
      },
    }),
    { ok: false, error: "The settings-vault request is invalid." },
  );
  assert.equal(called, false);

  assert.deepEqual(
    await proxySettingsVault({
      action: "sync",
      rendererUrl,
      requestToken,
      fetchImpl: async () => {
        throw new Error(`request failed with ${requestToken}`);
      },
    }),
    { ok: false, error: "The local vault could not be reached." },
  );
});
