const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  findOpenPort,
  isAllowedAppUrl,
  isAllowedExplicitExternalUrl,
  isAllowedExternalUrl,
  isAllowedRendererPermission,
} = require("../lib/runtime.cjs");

test("app navigation stays on the active local renderer origin", () => {
  const origin = "http://127.0.0.1:43123";
  assert.equal(isAllowedAppUrl(`${origin}/settings`, origin), true);
  assert.equal(isAllowedAppUrl("http://127.0.0.1:43124", origin), false);
  assert.equal(isAllowedAppUrl("https://bfl.ai", origin), false);
  assert.equal(isAllowedAppUrl("not a URL", origin), false);
});

test("the local renderer may write text to the clipboard", () => {
  const origin = "http://127.0.0.1:43123";
  assert.equal(
    isAllowedRendererPermission(
      "clipboard-sanitized-write",
      `${origin}/#/library`,
      origin,
    ),
    true,
  );
  assert.equal(
    isAllowedRendererPermission("clipboard-read", origin, origin),
    false,
  );
  assert.equal(
    isAllowedRendererPermission(
      "clipboard-sanitized-write",
      "http://127.0.0.1:43124",
      origin,
    ),
    false,
  );
  assert.equal(
    isAllowedRendererPermission(
      "clipboard-sanitized-write",
      "https://example.com",
      origin,
    ),
    false,
  );
});

test("external navigation is HTTPS-only and explicitly allowlisted", () => {
  assert.equal(isAllowedExternalUrl("https://bfl.ai/pricing"), true);
  assert.equal(isAllowedExternalUrl("https://docs.bfl.ai/flux_3/flux3_video"), true);
  assert.equal(isAllowedExternalUrl("https://console.ltx.io/"), true);
  assert.equal(isAllowedExternalUrl("https://docs.ltx.io/pricing"), true);
  assert.equal(isAllowedExternalUrl("https://app.getartcraft.com/"), true);
  assert.equal(isAllowedExternalUrl("https://app.runwayml.com/"), true);
  assert.equal(
    isAllowedExternalUrl("https://docs.dev.runwayml.com/guides/models/"),
    true,
  );
  assert.equal(
    isAllowedExternalUrl("https://storyteller-docs.netlify.app/"),
    true,
  );
  assert.equal(
    isAllowedExternalUrl(
      "https://github.com/storytold/artcraft/blob/main/_docs/omni_api/artcraft_omni_api.md",
    ),
    true,
  );
  assert.equal(isAllowedExternalUrl("https://gist.github.com/example"), false);
  assert.equal(isAllowedExternalUrl("https://www.atlascloud.ai/console"), true);
  assert.equal(isAllowedExternalUrl("https://heresalexandria.com/"), true);
  assert.equal(
    isAllowedExternalUrl(
      "https://heresalexandria.github.io/clawnsole/privacy/",
    ),
    true,
  );
  assert.equal(isAllowedExternalUrl("http://bfl.ai/pricing"), false);
  assert.equal(isAllowedExternalUrl("http://heresalexandria.com/"), false);
  assert.equal(isAllowedExternalUrl("https://bfl.ai.example.com"), false);
  assert.equal(isAllowedExternalUrl("https://app.runwayml.com.example.com"), false);
  assert.equal(
    isAllowedExternalUrl("https://app.getartcraft.com.example.com"),
    false,
  );
  assert.equal(
    isAllowedExternalUrl("https://heresalexandria.com.example.com"),
    false,
  );
  assert.equal(isAllowedExternalUrl("https://example.com"), false);
  assert.equal(isAllowedExternalUrl("https://www.bfl.ai/"), false);
  assert.equal(isAllowedExternalUrl("https://console.atlascloud.ai/"), false);
});

test("every provider catalog link is allowlisted for desktop", () => {
  const catalog = fs.readFileSync(
    path.join(
      __dirname,
      "..",
      "..",
      "flutter",
      "lib",
      "core",
      "provider_catalog.dart",
    ),
    "utf8",
  );
  const urls = [...catalog.matchAll(
    /\b(?:consoleUrl|docsUrl|pricingUrl):\s*'([^']+)'/g,
  )].map((match) => match[1]);
  assert.ok(urls.length > 0, "provider catalog URLs must be discoverable");
  for (const url of urls) {
    assert.equal(isAllowedExternalUrl(url), true, `${url} must be allowlisted`);
  }
});

test("explicit external opens are HTTPS and purpose scoped", () => {
  assert.equal(
    isAllowedExplicitExternalUrl(
      "https://storage.googleapis.com/output/video.mp4?signature=temporary",
      "media",
    ),
    true,
  );
  assert.equal(
    isAllowedExplicitExternalUrl(
      "https://atlas-media.oss-us-west-1.aliyuncs.com/video.mp4",
      "media",
    ),
    true,
  );
  assert.equal(
    isAllowedExplicitExternalUrl(
      "https://github.com/heresalexandria/clawnsole/releases/tag/v0.24.0",
      "release",
    ),
    true,
  );
  assert.equal(
    isAllowedExplicitExternalUrl(
      "https://github.com/example/repo/releases",
      "release",
    ),
    false,
  );
  assert.equal(
    isAllowedExplicitExternalUrl(
      "https://github.com/heresalexandria/clawnsole/issues",
      "release",
    ),
    false,
  );
  assert.equal(
    isAllowedExplicitExternalUrl("http://cdn.example/video.mp4", "media"),
    false,
  );
  assert.equal(
    isAllowedExplicitExternalUrl(
      "https://user:password@cdn.example/video.mp4",
      "media",
    ),
    false,
  );
  assert.equal(
    isAllowedExplicitExternalUrl("https://cdn.example/video.mp4", "unknown"),
    false,
  );
});

test("findOpenPort allocates a loopback port", async () => {
  const port = await findOpenPort();
  assert.equal(Number.isInteger(port), true);
  assert.equal(port > 0 && port < 65_536, true);
});
