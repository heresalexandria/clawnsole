const assert = require("node:assert/strict");
const test = require("node:test");
const {
  findOpenPort,
  isAllowedAppUrl,
  isAllowedExternalUrl,
} = require("../lib/runtime.cjs");

test("app navigation stays on the active local renderer origin", () => {
  const origin = "http://127.0.0.1:43123";
  assert.equal(isAllowedAppUrl(`${origin}/settings`, origin), true);
  assert.equal(isAllowedAppUrl("http://127.0.0.1:43124", origin), false);
  assert.equal(isAllowedAppUrl("https://bfl.ai", origin), false);
  assert.equal(isAllowedAppUrl("not a URL", origin), false);
});

test("external navigation is HTTPS-only and explicitly allowlisted", () => {
  assert.equal(isAllowedExternalUrl("https://bfl.ai/pricing"), true);
  assert.equal(isAllowedExternalUrl("https://docs.bfl.ai/flux_3/flux3_video"), true);
  assert.equal(isAllowedExternalUrl("https://console.ltx.io/"), true);
  assert.equal(isAllowedExternalUrl("https://docs.ltx.io/pricing"), true);
  assert.equal(isAllowedExternalUrl("https://www.atlascloud.ai/console"), true);
  assert.equal(isAllowedExternalUrl("https://console.atlascloud.ai/"), true);
  assert.equal(isAllowedExternalUrl("https://heresalexandria.com/"), true);
  assert.equal(isAllowedExternalUrl("https://www.heresalexandria.com/"), true);
  assert.equal(isAllowedExternalUrl("http://bfl.ai/pricing"), false);
  assert.equal(isAllowedExternalUrl("http://heresalexandria.com/"), false);
  assert.equal(isAllowedExternalUrl("https://bfl.ai.example.com"), false);
  assert.equal(
    isAllowedExternalUrl("https://heresalexandria.com.example.com"),
    false,
  );
  assert.equal(isAllowedExternalUrl("https://example.com"), false);
});

test("findOpenPort allocates a loopback port", async () => {
  const port = await findOpenPort();
  assert.equal(Number.isInteger(port), true);
  assert.equal(port > 0 && port < 65_536, true);
});
