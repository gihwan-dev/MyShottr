import assert from "node:assert/strict";
import {
  CHECKSUM_MARKER,
  COMMIT_MARKER,
  ReleaseNotesError,
  renderReleaseNotes,
} from "../../Scripts/render-release-notes.mjs";

const VERSION = "0.2.0";
const COMMIT_SHA = "1234567890abcdef1234567890abcdef12345678";
const APP_HASH = "a".repeat(64);
const EXTENSION_HASH = "b".repeat(64);
const CHECKSUMS = [
  `${APP_HASH}  Inkbeam-${VERSION}-macos.zip`,
  `${EXTENSION_HASH}  Inkbeam-Chrome-${VERSION}.zip`,
  "",
].join("\n");
const TEMPLATE = `# Inkbeam v${VERSION}

## Downloads

- \`Inkbeam-${VERSION}-macos.zip\`
- \`Inkbeam-Chrome-${VERSION}.zip\`
- \`SHA256SUMS.txt\`

## SHA-256 checksums

${CHECKSUM_MARKER}

## Verification status

${COMMIT_MARKER}
`;

const rendered = renderReleaseNotes(TEMPLATE, CHECKSUMS, VERSION, COMMIT_SHA);
assert.ok(rendered.includes(`Tagged commit: \`${COMMIT_SHA}\``));
assert.ok(rendered.includes(`\`\`\`text\n${CHECKSUMS.trim()}\n\`\`\``));
assert.ok(!rendered.includes(COMMIT_MARKER));
assert.ok(!rendered.includes(CHECKSUM_MARKER));
assert.equal(
  rendered.match(/^[0-9a-f]{64}  /gm)?.length,
  2,
  "rendered release notes must contain exactly two checksum entries",
);

for (const [label, template, checksums, version, commit] of [
  ["missing checksum marker", TEMPLATE.replace(CHECKSUM_MARKER, ""), CHECKSUMS, VERSION, COMMIT_SHA],
  ["duplicate checksum marker", `${TEMPLATE}\n${CHECKSUM_MARKER}\n`, CHECKSUMS, VERSION, COMMIT_SHA],
  ["missing commit marker", TEMPLATE.replace(COMMIT_MARKER, ""), CHECKSUMS, VERSION, COMMIT_SHA],
  ["committed checksum", TEMPLATE.replace(CHECKSUM_MARKER, CHECKSUMS.trim()), CHECKSUMS, VERSION, COMMIT_SHA],
  ["reordered checksums", TEMPLATE, `${CHECKSUMS.split("\n")[1]}\n${CHECKSUMS.split("\n")[0]}\n`, VERSION, COMMIT_SHA],
  ["extra checksum", TEMPLATE, `${CHECKSUMS}${APP_HASH}  extra.zip\n`, VERSION, COMMIT_SHA],
  ["uppercase checksum", TEMPLATE, CHECKSUMS.replace(APP_HASH, APP_HASH.toUpperCase()), VERSION, COMMIT_SHA],
  ["wrong version", TEMPLATE, CHECKSUMS, "0.1", COMMIT_SHA],
  ["wrong title version", TEMPLATE.replace("v0.2.0", "v0.2.1"), CHECKSUMS, VERSION, COMMIT_SHA],
  [
    "stale release commit",
    TEMPLATE.replace(COMMIT_MARKER, `Release source: \`${"f".repeat(40)}\`\n\n${COMMIT_MARKER}`),
    CHECKSUMS,
    VERSION,
    COMMIT_SHA,
  ],
  [
    "stale release commit after screenshot provenance",
    `${TEMPLATE}\n## Documentation screenshot provenance\n\nSource \`${"e".repeat(40)}\`.\n\n## Known limitations\n\nRelease source \`${"f".repeat(40)}\`.\n`,
    CHECKSUMS,
    VERSION,
    COMMIT_SHA,
  ],
  ["short commit", TEMPLATE, CHECKSUMS, VERSION, COMMIT_SHA.slice(0, 12)],
]) {
  assert.throws(
    () => renderReleaseNotes(template, checksums, version, commit),
    ReleaseNotesError,
    label,
  );
}

process.stdout.write("Release notes renderer tests passed.\n");
