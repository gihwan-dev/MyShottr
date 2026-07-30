# Chrome visible-viewport capture acceptance

MyShottr v1 supports installed Google Chrome 150 or newer. It captures only
the active tab's visible page pixels. It does not use content scripts, host
permissions, network requests, browser metadata, full-page capture, or a
desktop-capture alternative.

## Automated gate

Run from the repository root:

```bash
pnpm --filter @myshottr/chrome-extension build
pnpm --filter @myshottr/chrome-extension test
pnpm --filter @myshottr/chrome-extension exec playwright install chromium
pnpm --filter @myshottr/chrome-extension exec playwright test
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottrNativeHost \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Playwright uses its bundled Chromium with a persistent context. It loads an
E2E-only build whose compile-time seam counts calls around
`captureVisibleTab`. The production build contains neither that seam nor its
global test API. The process test launches the real `MyShottrNativeHost`
executable and verifies the exact one-reply lifecycle in an injected temporary
inbox. Success publishes one owner-only PNG. A staging failure returns
`STAGING_FAILED` without a new PNG. An injected activation failure returns
`APP_ACTIVATION_FAILED` with no stderr and preserves exactly one valid,
owner-only pending PNG for MyShottr's next launch scan.

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

`APP_ACTIVATION_FAILED` means the PNG is already durably staged for MyShottr's
next launch scan. The extension shows an `ERR` badge with the bounded title
`Capture saved. Open MyShottr to import.` It does not resend the capture or
expose the helper's activation diagnostic.

Run the combined product gate:

```bash
pnpm test
pnpm typecheck
pnpm build
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottr \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project MyShottr.xcodeproj -scheme MyShottrNativeHost \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## Installed Google Chrome acceptance

Use `Packages/chrome-extension/dist`, never `dist-e2e`. Keep the host manifest
restoration step in the same test session.

1. Build and launch MyShottr once.
2. Verify
   `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.myshottr.capture.json`
   exists and its `path` points into the running MyShottr app bundle.
3. Open `chrome://extensions`, enable Developer mode, choose **Load unpacked**,
   and select `Packages/chrome-extension/dist`.
4. Visit a page with an unmistakable top edge and scroll position.
5. Click the MyShottr extension action.
6. Confirm MyShottr opens exactly one editor document.
7. Confirm the PNG contains page pixels but no tab strip, address bar, toolbar,
   or extension popup.
8. Trigger `Option-Shift-2` and confirm the same behavior.
9. Rename the host manifest, trigger capture, and confirm the extension shows
   an `ERR` badge with the title `Open MyShottr once, then retry.` without a
   desktop-capture alternative.
10. Restore the manifest and confirm capture succeeds again.

For step 9, first ensure the disabled name does not already exist:

```bash
MANIFEST="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.myshottr.capture.json"
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

## Latest local acceptance attempt

Attempted on 2026-07-30 with Google Chrome `150.0.7871.187`.

| Check | Status | Evidence |
| --- | --- | --- |
| 1. Build and launch once | VERIFIED | The Debug app built and launched under the focused app test. |
| 2. Host manifest path | VERIFIED | The owner-only manifest existed and pointed to the current DerivedData Debug app helper. |
| 3. Load unpacked extension | BLOCKED / UNVERIFIED | Chrome UI focus changed during the attempt, and installing a local unpacked extension requires an explicit interactive approval. No extension was installed. |
| 4. Distinct page edge and scroll | BLOCKED / UNVERIFIED | Depends on check 3. |
| 5. Toolbar action | BLOCKED / UNVERIFIED | Depends on check 3. |
| 6. Exactly one editor document | BLOCKED / UNVERIFIED | Depends on check 3. |
| 7. Page pixels without browser chrome | BLOCKED / UNVERIFIED | Depends on check 3. |
| 8. `Option-Shift-2` | BLOCKED / UNVERIFIED | Depends on check 3. |
| 9. Actionable missing-host state with no alternative | BLOCKED / UNVERIFIED | Depends on check 3; the live manifest was not renamed. |
| 10. Restore and succeed | BLOCKED / UNVERIFIED | Depends on checks 3 and 9. |

Do not mark the installed-Chrome gate complete until checks 1 through 10 have
direct evidence in one controlled session.
