"use strict";

// Origin storage that must not outlive a launch. The companion origin is now
// stable across launches so cached media stays valid; the same stability
// would let a Flutter service worker keep serving a previous bundle after an
// update, and older random-port launches may have left workers behind. The
// renderer bundle is served no-store and the app keeps no state in the
// browser, so nothing legitimate lives in these stores.
const STORAGES = Object.freeze(["serviceworkers", "cachestorage"]);

async function clearRendererOriginStorage(session, rendererUrl) {
  let origin;
  try {
    origin = new URL(rendererUrl).origin;
  } catch {
    return false;
  }
  if (!session || typeof session.clearStorageData !== "function") return false;
  try {
    await session.clearStorageData({ origin, storages: [...STORAGES] });
    return true;
  } catch {
    return false;
  }
}

module.exports = { STORAGES, clearRendererOriginStorage };
