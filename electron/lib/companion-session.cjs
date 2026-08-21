"use strict";

const SESSION_HEADER = "X-Clawnsole-Session";
const VAULT_ACTIONS = new Set([
  "setup",
  "unlock",
  "recover",
  "changePassphrase",
  "forget",
  "sync",
]);
const VALUE_ACTIONS = new Set([
  "setup",
  "unlock",
  "recover",
  "changePassphrase",
]);
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const MAX_VAULT_VALUE_BYTES = 4096;

function is32ByteBase64Url(value) {
  if (typeof value !== "string" || !TOKEN_PATTERN.test(value)) return false;
  const decoded = Buffer.from(value, "base64url");
  return decoded.length === 32 && decoded.toString("base64url") === value;
}

function companionBootstrapLine(deviceKey, requestToken) {
  if (!is32ByteBase64Url(deviceKey) || !is32ByteBase64Url(requestToken)) {
    throw new TypeError("The companion bootstrap values are invalid.");
  }
  return `${JSON.stringify({ deviceKey, requestToken })}\n`;
}

function validateVaultRequest(action, value = "") {
  if (!VAULT_ACTIONS.has(action)) {
    throw new TypeError("The settings-vault action is invalid.");
  }
  if (typeof value !== "string") {
    throw new TypeError("The settings-vault value is invalid.");
  }
  const valueBytes = Buffer.byteLength(value, "utf8");
  if (VALUE_ACTIONS.has(action)) {
    if (valueBytes === 0 || valueBytes > MAX_VAULT_VALUE_BYTES) {
      throw new TypeError("The settings-vault value is invalid.");
    }
  } else if (valueBytes !== 0) {
    throw new TypeError("This settings-vault action does not accept a value.");
  }
  return { action, value };
}

function sameOrigin(value, expected) {
  try {
    return new URL(value).origin === new URL(expected).origin;
  } catch {
    return false;
  }
}

function installCompanionSessionHeader(webRequest, rendererUrl, requestToken) {
  if (!webRequest || typeof webRequest.onBeforeSendHeaders !== "function") {
    throw new TypeError("An Electron webRequest session is required.");
  }
  if (!sameOrigin(rendererUrl, rendererUrl) || !is32ByteBase64Url(requestToken)) {
    throw new TypeError("The companion session configuration is invalid.");
  }
  webRequest.onBeforeSendHeaders(
    { urls: ["<all_urls>"] },
    (details, callback) => {
      const requestHeaders = { ...details.requestHeaders };
      if (sameOrigin(details.url, rendererUrl)) {
        requestHeaders[SESSION_HEADER] = requestToken;
      }
      callback({ requestHeaders });
    },
  );
}

function sanitizedString(value, maximum) {
  if (typeof value !== "string") return null;
  return value.slice(0, maximum);
}

function sanitizeVaultResponse(payload, { action, responseOk }) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return { ok: false, error: "The local vault returned an invalid response." };
  }
  const result = { ok: responseOk && payload.ok === true };
  const state = sanitizedString(payload.state, 64);
  const message = sanitizedString(payload.message, 2048);
  const error = sanitizedString(payload.error, 2048);
  const syncedAt = sanitizedString(payload.syncedAt, 128);
  if (state !== null) result.state = state;
  if (message !== null) result.message = message;
  if (error !== null) result.error = error;
  if (syncedAt !== null) result.syncedAt = syncedAt;
  if (action === "setup" && result.ok) {
    const recoveryCode = sanitizedString(payload.recoveryCode, 512);
    if (recoveryCode !== null) result.recoveryCode = recoveryCode;
  }
  if (!result.ok && !result.error) {
    result.error = "The local vault request was not completed.";
  }
  return result;
}

async function proxySettingsVault({
  action,
  value = "",
  rendererUrl,
  requestToken,
  fetchImpl = globalThis.fetch,
}) {
  let request;
  try {
    request = validateVaultRequest(action, value);
    if (!sameOrigin(rendererUrl, rendererUrl) || !is32ByteBase64Url(requestToken)) {
      throw new TypeError("invalid companion session");
    }
  } catch {
    return { ok: false, error: "The settings-vault request is invalid." };
  }
  try {
    const response = await fetchImpl(
      new URL(`/vault/${request.action}`, rendererUrl),
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          [SESSION_HEADER]: requestToken,
        },
        body: JSON.stringify({ value: request.value }),
      },
    );
    const source = await response.text();
    if (Buffer.byteLength(source, "utf8") > 65_536) {
      return { ok: false, error: "The local vault returned an invalid response." };
    }
    return sanitizeVaultResponse(JSON.parse(source), {
      action: request.action,
      responseOk: response.ok,
    });
  } catch {
    return { ok: false, error: "The local vault could not be reached." };
  }
}

module.exports = {
  companionBootstrapLine,
  installCompanionSessionHeader,
  is32ByteBase64Url,
  MAX_VAULT_VALUE_BYTES,
  proxySettingsVault,
  SESSION_HEADER,
  validateVaultRequest,
};
