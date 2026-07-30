# MyShottr

MyShottr is a local-first macOS screenshot and annotation app. It captures a
native screen region or the visible content area of the active Google Chrome
tab, then opens the result in an Excalidraw-inspired editor for annotation,
copying, PNG export, and editable `.myshottr` project saves.

This repository is still a local release candidate. Automated verification does
not replace the interactive checklist in
[`docs/testing/v1-acceptance.md`](docs/testing/v1-acceptance.md).

## Prerequisites

- macOS 15 or newer
- Xcode 26 or newer
- Node.js 22 or newer
- pnpm 10 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Google Chrome 150 or newer for browser capture

## Build and verify

From any working directory, run:

```bash
/absolute/path/to/MyShottr/Scripts/verify-v1.sh
```

The script installs the exact locked JavaScript dependencies, runs unit and
Playwright tests, verifies privacy boundaries, regenerates the Xcode project,
runs the app and Native Messaging host suites, and creates a clean signed
Debug build. Any missing prerequisite or failed assertion stops the gate.

After it passes, open the Debug app from:

```text
DerivedData/VerifyV1/Build/Products/Debug/MyShottr.app
```

You can also launch it from the repository root:

```bash
open DerivedData/VerifyV1/Build/Products/Debug/MyShottr.app
```

## Chrome setup

1. Open the built MyShottr app once. First launch registers the per-user Native
   Messaging host for the app's current path.
2. Open `chrome://extensions` in Google Chrome.
3. Enable **Developer mode**, choose **Load unpacked**, and select
   `Packages/chrome-extension/dist`.
4. Use the extension action or `Option-Shift-2` to capture only the active
   tab's visible page viewport.

The extension intentionally has only `activeTab` and `nativeMessaging`
permissions. It does not use a content script, persistent host access, or an
alternate desktop-capture path.

## macOS permission

Grant **Screen Recording** when macOS prompts, then relaunch MyShottr. Native
region capture uses ScreenCaptureKit only. If permission is denied, MyShottr
stops the operation and offers the relevant System Settings action.

## v0.1.0 non-goals

The following are intentionally outside the v1 release:

- full-page or scrolling web capture
- HTML element capture
- desktop, browser, device, or social-card mockups
- Safari, Firefox, and guaranteed support for Chromium variants other than
  Google Chrome
- full-display, window-specific, multi-display-spanning, video, or audio
  capture
- OCR
- capture history or a screenshot library
- cloud sync, collaboration, accounts, billing, licensing services, analytics,
  or telemetry
- automatic updates
- Developer ID signing, Apple notarization, the Mac App Store, or the Chrome
  Web Store

The document model already keeps capture source and presentation concerns
separate so future full-page capture and desktop mockups can be added without
rewriting annotation state. Those features are not implemented in v0.1.0.

## Privacy

Captures, projects, inbox files, and recovery packages remain on the Mac. The
editor runs from bundled assets with remote navigation and network access
blocked. Run `Scripts/verify-privacy.sh` after building to verify the local-only
editor and extension permission contract.
