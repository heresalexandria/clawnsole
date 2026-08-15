# Clawnsole for macOS

The Electron app is deliberately a thin desktop shell around Clawnsole's existing
Next.js application. Development loads the local Next dev server. Release builds
package Next's standalone server and start it on a private loopback port, so the
finished app has no external runtime or companion-process requirement.

## Start in development

From the repository root:

```bash
./electron/scripts/start_macos
# or: npm run electron:start
```

The script installs missing root and Electron dependencies, reuses a healthy
Clawnsole server on port 3000, or starts and owns one for the Electron session.
Set `CLAWNSOLE_WEB_PORT` to use another port.

## Build the standalone app

```bash
./electron/scripts/build_macos
# or: npm run electron:build
```

Artifacts land in `electron/dist/release`: a `.app`, DMG, and ZIP for the current
Mac architecture. Set `CLAWNSOLE_ELECTRON_ARCH` to `arm64`, `x64`, or `universal`.

The default build is unsigned and usable locally. Set
`CLAWNSOLE_ELECTRON_SIGN=true` and provide the Apple signing/notarization
environment expected by `electron-builder` for distribution to other Macs;
unsigned apps will trigger Gatekeeper warnings away from the build machine.

Desktop metadata lives at `~/Library/Application Support/Clawnsole/clawnsole.json`,
with retained inputs and completed videos in the adjacent `assets/` directory.
It follows the same reference-aware cleanup policy as the local web app.
