const net = require("node:net");

const EXTERNAL_HOSTS = new Set([
  "bfl.ai",
  "docs.bfl.ai",
  "dashboard.bfl.ai",
  "docs.ltx.io",
  "console.ltx.io",
  "developer.apple.com",
  "app.getartcraft.com",
  "app.runwayml.com",
  "docs.dev.runwayml.com",
  "clawnsole.app",
  "console.anthropic.com",
  "github.com",
  "storyteller-docs.netlify.app",
  "support.apple.com",
  "www.atlascloud.ai",
  "www.krea.ai",
  "heresalexandria.com",
  "heresalexandria.github.io",
  "platform.openai.com",
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

function isAllowedExplicitExternalUrl(value, purpose) {
  const candidate = parseUrl(value);
  if (
    !candidate
    || candidate.protocol !== "https:"
    || candidate.username
    || candidate.password
  ) {
    return false;
  }
  if (purpose === "media") return true;
  return (
    purpose === "release"
    && candidate.hostname === "github.com"
    && candidate.pathname.startsWith(
      "/heresalexandria/clawnsole/releases/",
    )
  );
}

// A preferred port is tried first so a restarted companion can keep the
// renderer origin it had; any other port is acceptable when it is taken.
function findOpenPort(host = "127.0.0.1", { preferred = null } = {}) {
  const wanted = Number.isInteger(preferred) && preferred > 0 && preferred < 65_536
    ? preferred
    : null;
  return new Promise((resolve, reject) => {
    const attempt = (port, fallback) => {
      const server = net.createServer();
      server.unref();
      server.once("error", (error) => {
        if (fallback === null) reject(error);
        else attempt(fallback, null);
      });
      server.listen(port, host, () => {
        const address = server.address();
        const bound = typeof address === "object" && address ? address.port : null;
        server.close((error) => {
          if (error) reject(error);
          else if (bound) resolve(bound);
          else reject(new Error("Clawnsole could not allocate a local port."));
        });
      });
    };
    attempt(wanted ?? 0, wanted === null ? null : 0);
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
  isAllowedExplicitExternalUrl,
  isAllowedExternalUrl,
  isAllowedRendererPermission,
  waitForServer,
};
