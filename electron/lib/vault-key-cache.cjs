"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const path = require("node:path");

const CACHE_FILE_NAME = "vault-key-cache.json";
const CACHE_SCHEMA_VERSION = 1;
const VAULT_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const VAULT_KEY_PATTERN = /^[A-Za-z0-9_-]{43}$/;

function validateVaultId(vaultId) {
  if (typeof vaultId !== "string" || !VAULT_ID_PATTERN.test(vaultId)) {
    throw new TypeError("The vault ID is invalid.");
  }
  return vaultId;
}

function validateVaultKey(vaultKey) {
  if (typeof vaultKey !== "string" || !VAULT_KEY_PATTERN.test(vaultKey)) {
    throw new TypeError("The vault key must be a base64url-encoded 32-byte key.");
  }
  const decoded = Buffer.from(vaultKey, "base64url");
  if (decoded.length !== 32 || decoded.toString("base64url") !== vaultKey) {
    throw new TypeError("The vault key must be a base64url-encoded 32-byte key.");
  }
  return vaultKey;
}

function emptyCache() {
  return {
    schemaVersion: CACHE_SCHEMA_VERSION,
    vaultKeys: Object.create(null),
  };
}

class VaultKeyCache {
  constructor({ userData, safeStorage }) {
    if (typeof userData !== "string" || !userData.trim()) {
      throw new TypeError("A user-data directory is required.");
    }
    if (!safeStorage || typeof safeStorage.isEncryptionAvailable !== "function") {
      throw new TypeError("Electron safeStorage is required.");
    }
    this.file = path.join(userData.trim(), CACHE_FILE_NAME);
    this.safeStorage = safeStorage;
    this.queue = Promise.resolve();
  }

  async load(vaultId) {
    validateVaultId(vaultId);
    return this.#serialized(async () => {
      const cache = await this.#read();
      const encrypted = cache.vaultKeys[vaultId];
      if (!encrypted || !this.safeStorage.isEncryptionAvailable()) return null;
      try {
        const vaultKey = this.safeStorage.decryptString(
          Buffer.from(encrypted, "base64"),
        );
        return validateVaultKey(vaultKey);
      } catch {
        return null;
      }
    });
  }

  async save(vaultId, vaultKey) {
    validateVaultId(vaultId);
    validateVaultKey(vaultKey);
    return this.#serialized(async () => {
      if (!this.safeStorage.isEncryptionAvailable()) {
        throw new Error("Secure vault-key storage is unavailable.");
      }
      let encrypted;
      try {
        encrypted = this.safeStorage.encryptString(vaultKey);
      } catch {
        throw new Error("The vault key could not be protected.");
      }
      if (!Buffer.isBuffer(encrypted) || encrypted.length === 0) {
        throw new Error("The vault key could not be protected.");
      }
      const cache = await this.#read();
      cache.vaultKeys[vaultId] = encrypted.toString("base64");
      await this.#write(cache);
    });
  }

  async delete(vaultId) {
    validateVaultId(vaultId);
    return this.#serialized(async () => {
      const cache = await this.#read();
      if (!Object.hasOwn(cache.vaultKeys, vaultId)) return;
      delete cache.vaultKeys[vaultId];
      if (Object.keys(cache.vaultKeys).length === 0) {
        await fs.rm(this.file, { force: true });
        return;
      }
      await this.#write(cache);
    });
  }

  #serialized(operation) {
    const result = this.queue.then(operation, operation);
    this.queue = result.catch(() => {});
    return result;
  }

  async #read() {
    let source;
    try {
      source = await fs.readFile(this.file, "utf8");
    } catch (error) {
      if (error?.code === "ENOENT") return emptyCache();
      throw new Error("The vault-key cache could not be read.");
    }
    try {
      const payload = JSON.parse(source);
      if (
        payload?.schemaVersion !== CACHE_SCHEMA_VERSION
        || !payload.vaultKeys
        || typeof payload.vaultKeys !== "object"
        || Array.isArray(payload.vaultKeys)
      ) {
        throw new Error("invalid cache");
      }
      const cache = emptyCache();
      for (const [vaultId, encrypted] of Object.entries(payload.vaultKeys)) {
        validateVaultId(vaultId);
        if (typeof encrypted !== "string" || encrypted.length === 0) {
          throw new Error("invalid cache");
        }
        cache.vaultKeys[vaultId] = encrypted;
      }
      return cache;
    } catch {
      throw new Error("The vault-key cache is malformed.");
    }
  }

  async #write(cache) {
    await fs.mkdir(path.dirname(this.file), { recursive: true });
    const temporary = `${this.file}.${process.pid}.${crypto.randomUUID()}.tmp`;
    try {
      await fs.writeFile(
        temporary,
        `${JSON.stringify(cache)}\n`,
        { encoding: "utf8", mode: 0o600, flag: "wx", flush: true },
      );
      await fs.rename(temporary, this.file);
      await fs.chmod(this.file, 0o600);
    } catch {
      throw new Error("The vault-key cache could not be saved.");
    } finally {
      await fs.rm(temporary, { force: true }).catch(() => {});
    }
  }
}

module.exports = {
  CACHE_FILE_NAME,
  VaultKeyCache,
};
