"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const http = require("node:http");
const path = require("node:path");
const { oauthResultPage } = require("./google-drive-auth-page.cjs");

const DRIVE_SCOPE = "https://www.googleapis.com/auth/drive.file";
const AUTHORIZATION_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const REVOCATION_ENDPOINT = "https://oauth2.googleapis.com/revoke";

function base64Url(value) {
  return Buffer.from(value).toString("base64url");
}

function configuredOAuth(packageMetadata = {}) {
  return {
    clientId:
      process.env.CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_ID
      || packageMetadata.googleOAuthClientId
      || "",
    clientSecret:
      process.env.CLAWNSOLE_GOOGLE_DESKTOP_CLIENT_SECRET
      || packageMetadata.googleOAuthClientSecret
      || "",
  };
}

class GoogleDriveAuth {
  constructor({
    clientId,
    clientSecret = "",
    userData,
    safeStorage,
    openExternal,
    fetchImpl = globalThis.fetch,
    createServer = http.createServer,
  }) {
    this.clientId = clientId?.trim() || "";
    this.clientSecret = clientSecret?.trim() || "";
    this.tokenFile = path.join(userData, "google-drive-auth.json");
    this.safeStorage = safeStorage;
    this.openExternal = openExternal;
    this.fetch = fetchImpl;
    this.createServer = createServer;
  }

  get available() {
    return Boolean(this.clientId);
  }

  async authorize() {
    if (!this.available) {
      throw new Error(
        "This desktop build does not have a Google OAuth client ID configured.",
      );
    }
    const refreshToken = await this.#readRefreshToken();
    if (refreshToken) {
      try {
        return await this.#refresh(refreshToken);
      } catch {
        await this.#deleteRefreshToken();
      }
    }
    return this.#interactive();
  }

  async authorizeSilently() {
    if (!this.available) return "";
    const refreshToken = await this.#readRefreshToken();
    if (!refreshToken) return "";
    try {
      return await this.#refresh(refreshToken);
    } catch {
      await this.#deleteRefreshToken();
      return "";
    }
  }

  async disconnect() {
    const refreshToken = await this.#readRefreshToken();
    await this.#deleteRefreshToken();
    if (!refreshToken) return;
    try {
      await this.fetch(REVOCATION_ENDPOINT, {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ token: refreshToken }),
      });
    } catch {
      // Local disconnect succeeds when Google is temporarily unavailable.
    }
  }

  async #interactive() {
    const state = base64Url(crypto.randomBytes(32));
    const verifier = base64Url(crypto.randomBytes(64));
    const challenge = base64Url(
      crypto.createHash("sha256").update(verifier).digest(),
    );
    const result = await new Promise((resolve, reject) => {
      const server = this.createServer(async (request, response) => {
        try {
          const callback = new URL(request.url, "http://127.0.0.1");
          const returnedState = callback.searchParams.get("state");
          const code = callback.searchParams.get("code");
          const error = callback.searchParams.get("error");
          const valid = !error && code && returnedState === state;
          const address = server.address();
          const redirectUri = `http://127.0.0.1:${address.port}/oauth/google/callback`;
          response.writeHead(valid ? 200 : 400, {
            "cache-control": "no-store",
            "content-security-policy": [
              "default-src 'none'",
              "img-src data:",
              "style-src 'unsafe-inline'",
              "base-uri 'none'",
              "form-action 'none'",
              "frame-ancestors 'none'",
            ].join("; "),
            "content-type": "text/html; charset=utf-8",
            "referrer-policy": "no-referrer",
            "x-content-type-options": "nosniff",
          });
          response.end(oauthResultPage(valid));
          server.close();
          if (error) return reject(new Error("Google authorization was declined."));
          if (returnedState !== state) {
            return reject(new Error("Google authorization returned an invalid state."));
          }
          if (!code) return reject(new Error("Google authorization returned no code."));
          resolve({ code, redirectUri });
        } catch (error) {
          server.close();
          reject(error);
        }
      });
      server.on("error", reject);
      server.listen(0, "127.0.0.1", async () => {
        const redirectUri = `http://127.0.0.1:${server.address().port}/oauth/google/callback`;
        const authorization = new URL(AUTHORIZATION_ENDPOINT);
        authorization.search = new URLSearchParams({
          client_id: this.clientId,
          redirect_uri: redirectUri,
          response_type: "code",
          scope: DRIVE_SCOPE,
          state,
          code_challenge: challenge,
          code_challenge_method: "S256",
          access_type: "offline",
          prompt: "consent",
          include_granted_scopes: "true",
        }).toString();
        try {
          await this.openExternal(authorization.toString());
        } catch (error) {
          server.close();
          reject(error);
        }
      });
      setTimeout(() => {
        server.close();
        reject(new Error("Google authorization timed out."));
      }, 5 * 60 * 1000).unref();
    });
    const payload = await this.#token({
      code: result.code,
      code_verifier: verifier,
      grant_type: "authorization_code",
      redirect_uri: result.redirectUri,
    });
    if (payload.refresh_token) await this.#writeRefreshToken(payload.refresh_token);
    return payload.access_token;
  }

  async #refresh(refreshToken) {
    const payload = await this.#token({
      refresh_token: refreshToken,
      grant_type: "refresh_token",
    });
    return payload.access_token;
  }

  async #token(values) {
    const response = await this.fetch(TOKEN_ENDPOINT, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: this.clientId,
        ...(this.clientSecret ? { client_secret: this.clientSecret } : {}),
        ...values,
      }),
    });
    const payload = await response.json();
    if (!response.ok || !payload.access_token) {
      throw new Error(
        payload.error_description || `Google authorization failed with HTTP ${response.status}.`,
      );
    }
    return payload;
  }

  async #readRefreshToken() {
    try {
      const payload = JSON.parse(await fs.readFile(this.tokenFile, "utf8"));
      if (!payload.encrypted || !this.safeStorage.isEncryptionAvailable()) return "";
      return this.safeStorage.decryptString(Buffer.from(payload.encrypted, "base64"));
    } catch {
      return "";
    }
  }

  async #writeRefreshToken(refreshToken) {
    if (!this.safeStorage.isEncryptionAvailable()) return;
    const encrypted = this.safeStorage.encryptString(refreshToken).toString("base64");
    await fs.mkdir(path.dirname(this.tokenFile), { recursive: true });
    await fs.writeFile(this.tokenFile, `${JSON.stringify({ encrypted })}\n`, {
      encoding: "utf8",
      mode: 0o600,
    });
  }

  async #deleteRefreshToken() {
    await fs.rm(this.tokenFile, { force: true });
  }
}

module.exports = {
  GoogleDriveAuth,
  configuredOAuth,
  DRIVE_SCOPE,
};
