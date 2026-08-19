const net = require("node:net");

const EXTERNAL_HOSTS = new Set([
  "bfl.ai",
  "www.bfl.ai",
  "docs.bfl.ai",
  "dashboard.bfl.ai",
  "ltx.io",
  "www.ltx.io",
  "docs.ltx.io",
  "console.ltx.io",
  "atlascloud.ai",
  "www.atlascloud.ai",
  "console.atlascloud.ai",
  "heresalexandria.com",
  "www.heresalexandria.com",
]);

function parseUrl(value) {
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

function isAllowedAppUrl(value, rendererOrigin) {
  const candidate = parseUrl(value);
  const origin = parseUrl(rendererOrigin);
  return Boolean(candidate && origin && candidate.origin === origin.origin);
}

function isAllowedRendererPermission(permission, requestingUrl, rendererOrigin) {
  return (
    permission === "clipboard-sanitized-write"
    && isAllowedAppUrl(requestingUrl, rendererOrigin)
  );
}

function isAllowedExternalUrl(value) {
  const candidate = parseUrl(value);
  return Boolean(
    candidate
      && candidate.protocol === "https:"
      && EXTERNAL_HOSTS.has(candidate.hostname),
  );
}

function findOpenPort(host = "127.0.0.1") {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.once("error", reject);
    server.listen(0, host, () => {
      const address = server.address();
      const port = typeof address === "object" && address ? address.port : null;
      server.close((error) => {
        if (error) reject(error);
        else if (port) resolve(port);
        else reject(new Error("Clawnsole could not allocate a local port."));
      });
    });
  });
}

async function waitForServer(url, options = {}) {
  const timeoutMs = options.timeoutMs ?? 30_000;
  const intervalMs = options.intervalMs ?? 250;
  const isProcessAlive = options.isProcessAlive ?? (() => true);
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    if (!isProcessAlive()) {
      throw new Error("The bundled Clawnsole server stopped before it became ready.");
    }

    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(2_000) });
      if (response.ok) return;
    } catch {
      // The server is expected to reject connections during startup.
    }

    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  throw new Error(`Clawnsole did not become ready at ${url} within ${timeoutMs}ms.`);
}

module.exports = {
  findOpenPort,
  isAllowedAppUrl,
  isAllowedExternalUrl,
  isAllowedRendererPermission,
  waitForServer,
};
