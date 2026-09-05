"use strict";

const { isAllowedAppUrl, isAllowedExternalUrl } = require("./runtime.cjs");

// Resolve the active companion URL each time, including after a restart.
function protectRendererNavigation({ contents, getRendererUrl, openExternal }) {
  contents.setWindowOpenHandler(({ url }) => {
    if (isAllowedExternalUrl(url)) void openExternal(url);
    return { action: "deny" };
  });
  contents.on("will-navigate", (event, legacyUrl) => {
    const url = event.url ?? legacyUrl;
    if (isAllowedAppUrl(url, getRendererUrl())) return;
    event.preventDefault();
    if (isAllowedExternalUrl(url)) void openExternal(url);
  });
  // A redirect is another document decision, not permission inherited from
  // the original entry URL. Never launch external apps from a redirect.
  contents.on("will-redirect", (event, legacyUrl) => {
    if (!isAllowedAppUrl(event.url ?? legacyUrl, getRendererUrl())) {
      event.preventDefault();
    }
  });
  contents.on("will-attach-webview", (event) => event.preventDefault());
}

module.exports = { protectRendererNavigation };
