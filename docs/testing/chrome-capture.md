# Chrome visible-viewport capture acceptance

Inkbeam v0.2.0 supports installed Google Chrome 150 or newer. It captures only
the active tab's visible page pixels. It does not use content scripts, host
permissions, network requests, browser metadata, full-page capture, or a
desktop-capture alternative.

## Automated gate

Run from the repository root:

```bash
pnpm --filter @inkbeam/chrome-extension test
pnpm --filter @inkbeam/chrome-extension typecheck
pnpm --filter @inkbeam/chrome-extension build
pnpm --filter @inkbeam/chrome-extension exec playwright install chromium
pnpm --filter @inkbeam/chrome-extension exec playwright test
xcodebuild test -project Inkbeam.xcodeproj -scheme InkbeamNativeHost \
  -destination 'platform=macOS'
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS' \
  -only-testing:InkbeamTests/NativeMessagingRegistrarTests \
  -only-testing:InkbeamTests/CaptureInboxCoordinatorTests \
  -only-testing:InkbeamTests/PendingCaptureInboxTests \
  -only-testing:InkbeamTests/ChromeExtensionIdentityTests
```

Playwright uses its bundled Chromium with a persistent context. It loads an
E2E-only build whose compile-time seam counts calls around
`captureVisibleTab`. The production build contains neither that seam nor its
global test API. The process test launches the real `InkbeamNativeHost`
executable and verifies the exact one-reply lifecycle in an injected temporary
inbox. Success publishes one owner-only PNG. A staging failure returns
`STAGING_FAILED` without a new PNG. An injected activation failure returns
`APP_ACTIVATION_FAILED` with no stderr and preserves exactly one valid,
owner-only pending PNG for Inkbeam's next launch scan.

The bounded capture failure code list is:

- `HOST_UNAVAILABLE`
- `INVALID_MESSAGE`
- `UNSUPPORTED_CAPTURE_MODE`
- `INVALID_IMAGE`
- `IMAGE_TOO_LARGE`
- `STAGING_FAILED`
- `APP_ACTIVATION_FAILED`

`HOST_UNAVAILABLE` is the extension-side connection failure. The native helper
emits the other six codes. A helper failure reply contains only `ok` and
`code`, stays below the 1 MiB reply limit, and never includes a raw activation
or staging error.

`APP_ACTIVATION_FAILED` means the PNG is already durably staged for Inkbeam's
next launch scan. The extension shows an `ERR` badge with the bounded title
`Capture saved. Open Inkbeam to import.` It does not resend the capture or
expose the helper's activation diagnostic.

Run the combined product gate:

```bash
pnpm test
pnpm typecheck
pnpm build
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam \
  -destination 'platform=macOS'
xcodebuild test -project Inkbeam.xcodeproj -scheme InkbeamNativeHost \
  -destination 'platform=macOS'
```

## Installed Google Chrome acceptance

Use `Packages/chrome-extension/dist`, never `dist-e2e`. Keep the host manifest
restoration step in the same test session.

1. Install and launch `/Applications/Inkbeam.app` once.
2. Verify
   `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.gihwan.inkbeam.capture.json`
   exists and its `path` is exactly
   `/Applications/Inkbeam.app/Contents/Helpers/InkbeamNativeHost`.
3. Open `chrome://extensions`, enable Developer mode, choose **Load unpacked**,
   and select `Packages/chrome-extension/dist`.
4. Visit a page with an unmistakable top edge and scroll position.
5. Click the Inkbeam extension action.
6. Confirm Inkbeam opens exactly one editor document.
7. Confirm the PNG contains page pixels but no tab strip, address bar, toolbar,
   or extension popup.
8. Trigger `Option-Shift-2` and confirm the same behavior.
9. Rename the host manifest, trigger capture, and confirm the extension shows
   an `ERR` badge with the title `Open Inkbeam once, then retry.` without a
   desktop-capture alternative.
10. Restore the manifest and confirm capture succeeds again.

For step 9, first ensure the disabled name does not already exist:

```bash
MANIFEST="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.gihwan.inkbeam.capture.json"
DISABLED_MANIFEST="${MANIFEST}.disabled-for-test"
test -f "$MANIFEST"
test ! -e "$DISABLED_MANIFEST"
mv "$MANIFEST" "$DISABLED_MANIFEST"
```

Restore it immediately after the failure check:

```bash
mv "$DISABLED_MANIFEST" "$MANIFEST"
test -f "$MANIFEST"
```

No current Inkbeam installed-Chrome acceptance session has completed checks 1
through 10. Do not mark this gate complete until all checks have direct evidence
in one controlled session.
