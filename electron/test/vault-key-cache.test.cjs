"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  CACHE_FILE_NAME,
  VaultKeyCache,
} = require("../lib/vault-key-cache.cjs");

function vaultKey() {
  return crypto.randomBytes(32).toString("base64url");
}

function fakeSafeStorage({ available = true } = {}) {
  return {
    isEncryptionAvailable: () => available,
    encryptString: (value) => Buffer.from(`protected:${value}`),
    decryptString: (value) => value.toString().replace(/^protected:/, ""),
  };
}

async function withTemporaryDirectory(run) {
  const directory = await fs.mkdtemp(
    path.join(os.tmpdir(), "clawnsole-vault-key-cache."),
  );
  try {
    await run(directory);
  } finally {
    await fs.rm(directory, { recursive: true, force: true });
  }
}

test("vault keys round-trip through safeStorage without plaintext at rest", async () => {
  await withTemporaryDirectory(async (directory) => {
    const cache = new VaultKeyCache({
      userData: directory,
      safeStorage: fakeSafeStorage(),
    });
    const key = vaultKey();

    await cache.save("vault_01", key);

    assert.equal(await cache.load("vault_01"), key);
    const file = path.join(directory, CACHE_FILE_NAME);
    const source = await fs.readFile(file, "utf8");
    assert.doesNotMatch(source, new RegExp(key));
    assert.equal((await fs.stat(file)).mode & 0o777, 0o600);
    assert.deepEqual(
      (await fs.readdir(directory)).filter((name) => name.endsWith(".tmp")),
      [],
    );
  });
});

test("vault IDs keep independent cached keys and delete cleanly", async () => {
  await withTemporaryDirectory(async (directory) => {
    const cache = new VaultKeyCache({
      userData: directory,
      safeStorage: fakeSafeStorage(),
    });
    const first = vaultKey();
    const second = vaultKey();

    await Promise.all([
      cache.save("vault-a", first),
      cache.save("vault-b", second),
    ]);
    assert.equal(await cache.load("vault-a"), first);
    assert.equal(await cache.load("vault-b"), second);

    await cache.delete("vault-a");
    assert.equal(await cache.load("vault-a"), null);
    assert.equal(await cache.load("vault-b"), second);

    await cache.delete("vault-b");
    await assert.rejects(
      fs.access(path.join(directory, CACHE_FILE_NAME)),
      { code: "ENOENT" },
    );
  });
});

test("invalid IDs and non-32-byte keys are rejected before encryption", async () => {
  await withTemporaryDirectory(async (directory) => {
    let encryptions = 0;
    const safeStorage = fakeSafeStorage();
    const cache = new VaultKeyCache({
      userData: directory,
      safeStorage: {
        ...safeStorage,
        encryptString: (value) => {
          encryptions += 1;
          return safeStorage.encryptString(value);
        },
      },
    });

    await assert.rejects(cache.save("../vault", vaultKey()), /vault ID/i);
    await assert.rejects(cache.load(""), /vault ID/i);
    await assert.rejects(cache.delete("vault.with.dots"), /vault ID/i);
    await assert.rejects(cache.save("vault-01", "too-short"), /32-byte/i);
    await assert.rejects(
      cache.save("vault-01", `${vaultKey()}=`),
      /32-byte/i,
    );
    assert.equal(encryptions, 0);
  });
});

test("safeStorage failures are sanitized and never persist a key", async () => {
  await withTemporaryDirectory(async (directory) => {
    const key = vaultKey();
    const cache = new VaultKeyCache({
      userData: directory,
      safeStorage: {
        isEncryptionAvailable: () => true,
        encryptString: () => {
          throw new Error(`failed to encrypt ${key}`);
        },
        decryptString: () => {
          throw new Error(`failed to decrypt ${key}`);
        },
      },
    });

    await assert.rejects(
      cache.save("vault-01", key),
      (error) => {
        assert.equal(error.message, "The vault key could not be protected.");
        assert.doesNotMatch(error.message, new RegExp(key));
        return true;
      },
    );
    await assert.rejects(
      fs.access(path.join(directory, CACHE_FILE_NAME)),
      { code: "ENOENT" },
    );
  });
});

test("unavailable encryption fails closed while deletion remains available", async () => {
  await withTemporaryDirectory(async (directory) => {
    const cache = new VaultKeyCache({
      userData: directory,
      safeStorage: fakeSafeStorage({ available: false }),
    });

    assert.equal(await cache.load("vault-01"), null);
    await assert.rejects(
      cache.save("vault-01", vaultKey()),
      /Secure vault-key storage is unavailable/,
    );
    await cache.delete("vault-01");
  });
});

test("malformed cache data is preserved and fails without leaking content", async () => {
  await withTemporaryDirectory(async (directory) => {
    const file = path.join(directory, CACHE_FILE_NAME);
    const sensitive = vaultKey();
    await fs.writeFile(file, `{not-json:${sensitive}}`, { mode: 0o600 });
    const cache = new VaultKeyCache({
      userData: directory,
      safeStorage: fakeSafeStorage(),
    });

    await assert.rejects(cache.load("vault-01"), (error) => {
      assert.equal(error.message, "The vault-key cache is malformed.");
      assert.doesNotMatch(error.message, new RegExp(sensitive));
      return true;
    });
    assert.match(await fs.readFile(file, "utf8"), new RegExp(sensitive));
  });
});
