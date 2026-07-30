import assert from "node:assert/strict";
import {
  createHash,
} from "node:crypto";
import {
  existsSync,
  readFileSync,
} from "node:fs";
import { inflateSync } from "node:zlib";

const README_PATH = "README.md";
const LICENSE_PATH = "LICENSE";
const NOTES_PATH = "docs/releases/v0.1.0.md";
const INSTALL_PATH = "docs/testing/release-installation.md";
const SCREENSHOT_PATH = "docs/images/editor-quick-ink.png";

const RELEASE_SOURCE_SHA = "ddc95af1a2eb65a39ceb55d57e3154090a583679";
const APP_SHA256 =
  "2601c96dd5f8d3d674333c94754e522748a95bb88f051bfd26b2be1371c828f6";
const EXTENSION_SHA256 =
  "b5e8f91b31eaa3d5674954bcd1d63774be51f5a5ad595ee2542efed8458e2f3f";
const SCREENSHOT_SHA256 =
  "119461380435271d6e733475f62a35854f22316f76ac208f754a2bd2cb9cd5a1";

for (const path of [
  README_PATH,
  LICENSE_PATH,
  NOTES_PATH,
  INSTALL_PATH,
  SCREENSHOT_PATH,
]) {
  assert.ok(existsSync(path), `required public documentation is missing: ${path}`);
}

const readme = readFileSync(README_PATH, "utf8");
const license = readFileSync(LICENSE_PATH, "utf8");
const notes = readFileSync(NOTES_PATH, "utf8");
const installation = readFileSync(INSTALL_PATH, "utf8");
const screenshot = readFileSync(SCREENSHOT_PATH);

assert.deepEqual(
  markdownSections(readme, 2),
  [
    "Features",
    "한국어 빠른 설치",
    "Install",
    "Use",
    "Annotation shortcuts",
    "Privacy",
    "Development",
    "v1 limitations and roadmap",
    "License",
  ],
  "README public sections or their order changed",
);
assert.match(
  readme,
  /^# MyShottr\n\nFast, local screenshot capture and Excalidraw-style annotation for macOS\.\n/m,
);
assert.match(
  readme,
  /!\[MyShottr Quick Ink editor\]\(docs\/images\/editor-quick-ink\.png\)/,
);

const featuresBody = readme.match(
  /^## Features\n(?<body>[\s\S]*?)(?=^## )/m,
)?.groups?.body;
assert.ok(featuresBody, "README Features section is missing");
const featureBullets = [...featuresBody.matchAll(
  /^- (?<item>[^\n]*(?:\n  [^\n]*)*)/gm,
)].map((match) => match.groups.item.replace(/\s+/g, " "));
const telemetryFeatureBullets = featureBullets
  .filter((item) => /\btelemetry\b/i.test(item));
assert.equal(
  telemetryFeatureBullets.length,
  1,
  "README Features must have one consolidated privacy bullet",
);
assert.match(telemetryFeatureBullets[0], /local-only/i);
assert.match(telemetryFeatureBullets[0], /no account/i);
assert.match(telemetryFeatureBullets[0], /upload/i);
assert.match(telemetryFeatureBullets[0], /analytics/i);
assert.match(telemetryFeatureBullets[0], /background[\s-]+network transfer/i);

for (const text of [
  "macOS 15",
  "Command-Shift-2",
  "Option-Shift-2",
  "Command-Shift-C",
  "Command-S",
  "Command-E",
  "Chrome",
  "Developer mode",
  "unsigned",
  "unnotarized",
  "ad-hoc",
  "Developer ID",
  "viewport",
  "full-page",
  "Desktop mockup",
  "activeTab",
  "nativeMessaging",
  "presentation layer",
]) {
  assert.ok(readme.includes(text), `README missing release contract text: ${text}`);
}

for (const tool of [
  ["Select", "V"],
  ["Rectangle", "R"],
  ["Arrow", "A"],
  ["Line", "L"],
  ["Text", "T"],
  ["Freehand", "P"],
  ["Highlighter", "H"],
  ["Blur", "B"],
  ["Redaction", "X"],
  ["Number marker", "N"],
]) {
  assert.ok(
    readme.includes(`| ${tool[0]} | \`${tool[1]}\` |`),
    `README shortcut table is missing ${tool[0]}`,
  );
}

for (const expectedLink of [
  "[latest GitHub Release](https://github.com/gihwan-dev/MyShottr/releases/latest)",
  "[MIT License](LICENSE)",
  "[v0.1.0 release notes](docs/releases/v0.1.0.md)",
  "[manual acceptance record](docs/testing/v1-acceptance.md)",
]) {
  assert.ok(readme.includes(expectedLink), `README link changed: ${expectedLink}`);
}

assert.match(
  readme,
  /Control-click[\s\S]*시스템 설정[\s\S]*개인정보 보호 및 보안[\s\S]*확인 없이 열기/,
);
assert.match(
  readme,
  /Control-click[\s\S]*System Settings[\s\S]*Privacy & Security[\s\S]*Open Anyway/,
);
assert.match(
  readme,
  /first launch[\s\S]*Native Messaging Host/i,
);
assert.match(
  readme,
  /chrome:\/\/extensions[\s\S]*Developer mode[\s\S]*Load unpacked/,
);
assert.match(
  readme,
  /Screen Recording[\s\S]*relaunch MyShottr/,
);

const quarantineCommands = [
  ...readme.matchAll(/^\s*xattr\s+.+$/gm),
].map((match) => match[0].trim());
assert.deepEqual(
  quarantineCommands,
  ["xattr -dr com.apple.quarantine /Applications/MyShottr.app"],
  "README may contain only the exact, app-scoped quarantine command",
);
assert.match(
  readme,
  /last resort[\s\S]{0,500}xattr -dr com\.apple\.quarantine \/Applications\/MyShottr\.app/i,
  "quarantine removal must be presented only as a warned last resort",
);
assert.doesNotMatch(readme, /\bsudo\b|\bcurl\b[^\n]*\|\s*(?:sh|bash|zsh)\b/);
assert.match(
  readme,
  /link-time ad-hoc[\s\S]*not a Developer ID signature/i,
);
assert.match(
  readme,
  /no account, cloud upload, analytics, or telemetry/i,
);
assert.match(
  readme,
  /Blur is a visual effect, not secure redaction/,
);
assert.match(
  readme,
  /visible viewport only[\s\S]*capture-mode boundary/i,
);
assert.match(
  readme,
  /Desktop mockup[\s\S]*presentation layer/i,
);
assert.match(readme, /Safari and Firefox are not supported in v1/);
assert.match(readme, /no automatic updater/);
assert.match(readme, /not distributed through (?:an app store|the Mac App Store)/);

const expectedLicense = `MIT License

Copyright (c) 2026 gihwan-dev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
`;
assert.equal(license, expectedLicense, "LICENSE must be the exact approved MIT text");

assert.deepEqual(
  markdownSections(notes, 2),
  [
    "Downloads",
    "SHA-256 checksums",
    "Important installation note",
    "Verification status",
    "Documentation screenshot provenance",
    "Known limitations",
  ],
  "release-note sections or their order changed",
);
for (const asset of [
  "MyShottr-0.1.0-macos.zip",
  "MyShottr-Chrome-0.1.0.zip",
  "SHA256SUMS.txt",
]) {
  assert.ok(notes.includes(asset), `release notes missing artifact: ${asset}`);
}
for (const hash of [APP_SHA256, EXTENSION_SHA256]) {
  assert.ok(notes.includes(hash), `release notes missing current SHA-256: ${hash}`);
}
assert.ok(notes.includes(RELEASE_SOURCE_SHA), "release notes missing screenshot source SHA");
assert.match(notes, /unsigned and unnotarized/);
assert.match(notes, /link-time ad-hoc[\s\S]*no Developer ID/i);
assert.match(notes, /automated[\s\S]*passed/i);
assert.match(notes, /manual acceptance[\s\S]*BLOCKED \/ UNVERIFIED/i);
assert.match(
  notes,
  /not a native\s+NSWindow or ScreenCaptureKit acceptance proof/i,
);
assert.match(notes, /production\s+bridge[\s\S]*loadDocument/i);
assert.match(notes, /neutral\s+generated source PNG/i);
assert.doesNotMatch(
  notes,
  /manual acceptance(?: gate| checks?) (?:passed|complete)|Apple-(?:reviewed|notarized)|available (?:in|on) the Chrome Web Store/i,
);

assert.deepEqual(
  markdownSections(installation, 2),
  [
    "Candidate and live release",
    "Downloaded artifacts",
    "Installation and product checks",
    "Final decision",
  ],
  "release-installation template sections or their order changed",
);
for (const field of [
  "Tag",
  "Exact release commit SHA",
  "CI workflow URL",
  "Release workflow URL",
  "Live release URL",
  "Download source URL",
  "Downloaded artifact sizes",
  "SHA-256 verification",
  "App launch",
  "Native region capture",
  "Chrome visible-viewport capture",
  "Project reopen",
  "Extension manifest permissions",
  "Gatekeeper behavior",
]) {
  assert.ok(installation.includes(field), `installation template missing field: ${field}`);
}
assert.match(
  installation,
  /Allowed result values are exactly `PASS`, `FAIL`, or `BLOCKED`/,
);
assert.match(
  installation,
  /https:\/\/github\.com\/gihwan-dev\/MyShottr\/actions\/runs\/<run-id>/,
);
assert.match(
  installation,
  /https:\/\/github\.com\/gihwan-dev\/MyShottr\/releases\/tag\/v0\.1\.0/,
);
assert.match(installation, /- Result: `<PASS\|FAIL\|BLOCKED>`/);
assert.match(installation, /- Evidence:/);
assert.match(
  installation,
  /A report containing `FAIL`, `BLOCKED`, a placeholder, or missing\s+evidence is not passing release-install evidence/,
);

for (const publicDocument of [readme, notes, installation]) {
  assert.doesNotMatch(publicDocument, /\/Users\/|choegihwan|localhost|127\.0\.0\.1/);
}

const png = decodePng(screenshot);
assert.ok(png.width >= 1440, `screenshot width must be at least 1440, got ${png.width}`);
assert.ok(png.height >= 800, `screenshot height must be at least 800, got ${png.height}`);
assert.ok(
  png.width / png.height >= 1.3 && png.width / png.height <= 2.2,
  "screenshot must show a plausible landscape editor window",
);
assert.equal(
  createHash("sha256").update(screenshot).digest("hex"),
  SCREENSHOT_SHA256,
  "the reviewed real-product screenshot changed",
);

const colors = analyzeColors(png);
assert.ok(colors.unique >= 1_000, "screenshot lacks real UI/source-image color detail");
assert.ok(colors.opaqueRatio > 0.999, "documentation screenshot must be opaque");
for (const [label, color, minimum] of [
  ["warm ivory workspace", [247, 241, 232], 5_000],
  ["Quick Ink coral", [255, 107, 95], 100],
  ["red rectangle", [255, 77, 79], 80],
  ["blue arrow", [22, 119, 255], 80],
  ["yellow line", [250, 219, 20], 80],
  ["black text", [0, 0, 0], 80],
]) {
  assert.ok(
    colors.count(color) >= minimum,
    `screenshot is missing reviewed ${label} pixels`,
  );
}
assert.ok(
  colors.luminanceBuckets.dark > 1_000
    && colors.luminanceBuckets.mid > 10_000
    && colors.luminanceBuckets.light > 100_000,
  "screenshot does not contain the reviewed editor, annotations, and source image",
);

console.log(
  `Public documentation contract passed (${png.width}x${png.height}, ${SCREENSHOT_SHA256}).`,
);

function markdownSections(source, level) {
  const prefix = "#".repeat(level);
  return [...source.matchAll(new RegExp(`^${prefix} (.+)$`, "gm"))]
    .map((match) => match[1]);
}

function decodePng(buffer) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  assert.ok(buffer.subarray(0, 8).equals(signature), "screenshot is not a PNG");

  let offset = 8;
  let header;
  const idat = [];
  let sawEnd = false;
  while (offset < buffer.length) {
    assert.ok(offset + 12 <= buffer.length, "PNG chunk is truncated");
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    assert.ok(dataEnd + 4 <= buffer.length, `PNG ${type} chunk is truncated`);
    if (type === "IHDR") {
      assert.equal(length, 13);
      header = {
        width: buffer.readUInt32BE(dataStart),
        height: buffer.readUInt32BE(dataStart + 4),
        bitDepth: buffer[dataStart + 8],
        colorType: buffer[dataStart + 9],
        compression: buffer[dataStart + 10],
        filter: buffer[dataStart + 11],
        interlace: buffer[dataStart + 12],
      };
    } else if (type === "IDAT") {
      idat.push(buffer.subarray(dataStart, dataEnd));
    } else if (type === "IEND") {
      sawEnd = true;
    }
    offset = dataEnd + 4;
  }
  assert.ok(header, "PNG is missing IHDR");
  assert.ok(sawEnd, "PNG is missing IEND");
  assert.equal(header.bitDepth, 8, "screenshot PNG must use 8-bit channels");
  assert.ok(
    header.colorType === 2 || header.colorType === 6,
    "screenshot PNG must be RGB or RGBA",
  );
  assert.equal(header.compression, 0);
  assert.equal(header.filter, 0);
  assert.equal(header.interlace, 0, "interlaced screenshots are not supported");

  const channels = header.colorType === 6 ? 4 : 3;
  const stride = header.width * channels;
  const inflated = inflateSync(Buffer.concat(idat));
  assert.equal(
    inflated.length,
    (stride + 1) * header.height,
    "PNG scanline payload has unexpected length",
  );

  const pixels = Buffer.alloc(stride * header.height);
  for (let y = 0; y < header.height; y += 1) {
    const sourceOffset = y * (stride + 1);
    const filterType = inflated[sourceOffset];
    const rowOffset = y * stride;
    for (let x = 0; x < stride; x += 1) {
      const raw = inflated[sourceOffset + 1 + x];
      const left = x >= channels ? pixels[rowOffset + x - channels] : 0;
      const above = y > 0 ? pixels[rowOffset - stride + x] : 0;
      const upperLeft =
        y > 0 && x >= channels
          ? pixels[rowOffset - stride + x - channels]
          : 0;
      pixels[rowOffset + x] = unfilter(
        filterType,
        raw,
        left,
        above,
        upperLeft,
      );
    }
  }

  return { ...header, channels, pixels };
}

function unfilter(type, raw, left, above, upperLeft) {
  switch (type) {
    case 0:
      return raw;
    case 1:
      return (raw + left) & 0xff;
    case 2:
      return (raw + above) & 0xff;
    case 3:
      return (raw + Math.floor((left + above) / 2)) & 0xff;
    case 4:
      return (raw + paeth(left, above, upperLeft)) & 0xff;
    default:
      assert.fail(`unsupported PNG filter type: ${type}`);
  }
}

function paeth(left, above, upperLeft) {
  const estimate = left + above - upperLeft;
  const leftDistance = Math.abs(estimate - left);
  const aboveDistance = Math.abs(estimate - above);
  const upperLeftDistance = Math.abs(estimate - upperLeft);
  if (leftDistance <= aboveDistance && leftDistance <= upperLeftDistance) {
    return left;
  }
  if (aboveDistance <= upperLeftDistance) return above;
  return upperLeft;
}

function analyzeColors(png) {
  const histogram = new Map();
  let opaque = 0;
  const luminanceBuckets = { dark: 0, mid: 0, light: 0 };
  for (let offset = 0; offset < png.pixels.length; offset += png.channels) {
    const red = png.pixels[offset];
    const green = png.pixels[offset + 1];
    const blue = png.pixels[offset + 2];
    const alpha = png.channels === 4 ? png.pixels[offset + 3] : 255;
    if (alpha === 255) opaque += 1;
    const key = (red << 16) | (green << 8) | blue;
    histogram.set(key, (histogram.get(key) ?? 0) + 1);
    const luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    if (luminance < 70) luminanceBuckets.dark += 1;
    else if (luminance < 210) luminanceBuckets.mid += 1;
    else luminanceBuckets.light += 1;
  }
  return {
    unique: histogram.size,
    opaqueRatio: opaque / (png.width * png.height),
    luminanceBuckets,
    count([red, green, blue]) {
      return histogram.get((red << 16) | (green << 8) | blue) ?? 0;
    },
  };
}
