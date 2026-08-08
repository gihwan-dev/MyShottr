import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import {
  ACCEPTANCE_CHECKS,
  ReleaseEvidenceError,
  RELEASE_INSTALL_CHECKS,
  validateAcceptanceReport,
  validateReleaseInstallReport,
} from "../../Scripts/validate-release-evidence.mjs";

const ACCEPTANCE_TEMPLATE = readFileSync(
  "docs/testing/inkbeam-acceptance.md",
  "utf8",
);
const INSTALL_TEMPLATE = readFileSync(
  "docs/testing/release-installation.md",
  "utf8",
);
const SCRIPT_PATH = "Scripts/validate-release-evidence.mjs";
const EXPECTED_SHA = "1234567890abcdef1234567890abcdef12345678";
const OTHER_SHA = "0234567890abcdef1234567890abcdef12345678";
const TAG = "v0.2.0";
const APP_HASH = "a".repeat(64);
const EXTENSION_HASH = "b".repeat(64);
const CHECKSUM_SOURCE = [
  `${APP_HASH}  Inkbeam-0.2.0-macos.zip`,
  `${EXTENSION_HASH}  Inkbeam-Chrome-0.2.0.zip`,
  "",
].join("\n");
const CHECKSUM_ASSET_HASH = createHash("sha256")
  .update(CHECKSUM_SOURCE)
  .digest("hex");

const EXPECTED_ACCEPTANCE_CHECKS = [
  "1. Native region shortcut",
  "2. Capture cancellation",
  "3. Retina source dimensions",
  "4. Overlay exclusion",
  "5. Chrome visible viewport",
  "6. Chrome keyboard command",
  "7. Drawing tools and live preview",
  "8. Annotation editing and shortcut ownership",
  "9. Clipboard PNG",
  "10. Export dimensions",
  "11. Project round trip and legacy rejection",
  "12. Modified-document close",
  "13. Direct capture launch",
  "14. Screen Recording denial",
  "15. Missing Chrome host",
  "16. Unsupported project version",
  "17. Failed export",
  "18. Save terminal truthfulness and exact-artifact privacy gate",
];

assert.deepEqual(ACCEPTANCE_CHECKS, EXPECTED_ACCEPTANCE_CHECKS);
assert.deepEqual(RELEASE_INSTALL_CHECKS, [
  "SHA-256 verification",
  "App launch",
  "Native region capture",
  "Chrome visible-viewport capture",
  "Project reopen",
  "Extension manifest permissions",
  "Gatekeeper behavior",
]);

function replaceExact(source, before, after, label) {
  assert.ok(source.includes(before), `${label} fixture is stale`);
  const changed = source.replace(before, after);
  assert.notEqual(changed, source, `${label} did not change the fixture`);
  return changed;
}

function validAcceptanceReport() {
  let evidenceIndex = 0;
  return ACCEPTANCE_TEMPLATE
    .replace("- Date:", "- Date: `2026-08-02 12:00 KST`")
    .replace("- macOS version:", "- macOS version: `26.5.2`")
    .replace("- Google Chrome version:", "- Google Chrome version: `150.0.7339.0`")
    .replace("- Tested commit SHA:", `- Tested commit SHA: \`${EXPECTED_SHA}\``)
    .replace(
      "- `Scripts/verify-inkbeam.sh` result:",
      "- `Scripts/verify-inkbeam.sh` result: `PASS`",
    )
    .replace(
      "- `Scripts/verify-inkbeam.sh` evidence:",
      "- `Scripts/verify-inkbeam.sh` evidence: full gate completed with exit code 0",
    )
    .replaceAll("- Result: `<PASS|FAIL|BLOCKED>`", "- Result: `PASS`")
    .replace(/^- Evidence:$/gm, () => {
      evidenceIndex += 1;
      return `- Evidence: observed acceptance check ${evidenceIndex}`;
    })
    .replace("- Overall result: `<PASS|FAIL|BLOCKED>`", "- Overall result: `PASS`")
    .replace("- Reviewer:", "- Reviewer: `gihwan-dev`")
    .replace("- Notes:", "- Notes: Exact candidate accepted without exceptions.");
}

function validReleaseInstallReport() {
  let evidenceIndex = 0;
  const liveURL = `https://github.com/gihwan-dev/inkbeam/releases/tag/${TAG}`;
  let report = INSTALL_TEMPLATE
    .replace("- Exact release commit SHA: `<40-hex SHA>`", `- Exact release commit SHA: \`${EXPECTED_SHA}\``)
    .replace(
      /- CI workflow URL:\n  `https:\/\/github\.com\/gihwan-dev\/inkbeam\/actions\/runs\/<run-id>`/,
      "- CI workflow URL: `https://github.com/gihwan-dev/inkbeam/actions/runs/1001`",
    )
    .replace(
      /- Release workflow URL:\n  `https:\/\/github\.com\/gihwan-dev\/inkbeam\/actions\/runs\/<run-id>`/,
      "- Release workflow URL: `https://github.com/gihwan-dev/inkbeam/actions/runs/1002`",
    )
    .replace("- Test date and timezone:", "- Test date and timezone: `2026-08-02 13:00 KST`")
    .replace("- macOS version:", "- macOS version: `26.5.2`")
    .replace("- Google Chrome version:", "- Google Chrome version: `150.0.7339.0`")
    .replace("- Tester:", "- Tester: `gihwan-dev`")
    .replace(
      /^\| `Inkbeam-0\.2\.0-macos\.zip` .*$/m,
      `| \`Inkbeam-0.2.0-macos.zip\` | \`${APP_HASH}\` | \`123456\` | \`PASS\` |`,
    )
    .replace(
      /^\| `Inkbeam-Chrome-0\.2\.0\.zip` .*$/m,
      `| \`Inkbeam-Chrome-0.2.0.zip\` | \`${EXTENSION_HASH}\` | \`23456\` | \`PASS\` |`,
    )
    .replace(
      /^\| `SHA256SUMS\.txt` .*$/m,
      `| \`SHA256SUMS.txt\` | \`${CHECKSUM_ASSET_HASH}\` | \`256\` | \`PASS\` |`,
    )
    .replaceAll("- Result: `<PASS|FAIL|BLOCKED>`", "- Result: `PASS`")
    .replace(/^- Evidence:$/gm, () => {
      evidenceIndex += 1;
      return `- Evidence: observed installed-release check ${evidenceIndex}`;
    })
    .replace("- Overall result: `<PASS|FAIL|BLOCKED>`", "- Overall result: `PASS`")
    .replace("- Exact release commit SHA rechecked:", `- Exact release commit SHA rechecked: \`${EXPECTED_SHA}\``)
    .replace("- Remote tag dereference SHA:", `- Remote tag dereference SHA: \`${EXPECTED_SHA}\``)
    .replace("- Downloaded release URL rechecked:", `- Downloaded release URL rechecked: \`${liveURL}\``)
    .replace("- Git note attachment SHA:", `- Git note attachment SHA: \`${EXPECTED_SHA}\``)
    .replace("- Reviewer:", "- Reviewer: `gihwan-dev`")
    .replace("- Notes:", "- Notes: Live assets accepted without exceptions.");

  report = replaceExact(
    report,
    "- Live release URL:\n  `https://github.com/gihwan-dev/inkbeam/releases/tag/v0.2.0`",
    `- Live release URL: \`${liveURL}\``,
    "live release URL",
  );
  report = replaceExact(
    report,
    "- Download source URL:\n  `https://github.com/gihwan-dev/inkbeam/releases/download/v0.2.0/`",
    "- Download source URL: `https://github.com/gihwan-dev/inkbeam/releases/download/v0.2.0/`",
    "download URL",
  );
  return report;
}

function expectAcceptanceRejected(report, label) {
  assert.throws(
    () => validateAcceptanceReport(report, EXPECTED_SHA),
    ReleaseEvidenceError,
    label,
  );
}

function expectInstallRejected(report, label) {
  assert.throws(
    () => validateReleaseInstallReport(
      report,
      EXPECTED_SHA,
      TAG,
      CHECKSUM_SOURCE,
      CHECKSUM_ASSET_HASH,
    ),
    ReleaseEvidenceError,
    label,
  );
}

assert.throws(
  () => validateAcceptanceReport(ACCEPTANCE_TEMPLATE, EXPECTED_SHA),
  ReleaseEvidenceError,
  "the unfilled acceptance template must fail",
);
const acceptance = validAcceptanceReport();
assert.deepEqual(validateAcceptanceReport(acceptance, EXPECTED_SHA), {
  kind: "acceptance",
  expectedSHA: EXPECTED_SHA,
  checkCount: 18,
});
assert.equal(
  validateAcceptanceReport(acceptance.replaceAll("\n", "\r\n"), EXPECTED_SHA).checkCount,
  18,
  "CRLF acceptance evidence must be accepted",
);
expectAcceptanceRejected(
  acceptance.replace(EXPECTED_SHA, OTHER_SHA),
  "a mismatched tested SHA must fail",
);
expectAcceptanceRejected(
  replaceExact(acceptance, "- Result: `PASS`", "- Result: `FAIL`", "failed result"),
  "a failed check must fail",
);
expectAcceptanceRejected(
  replaceExact(
    acceptance,
    "- Evidence: observed acceptance check 1",
    "- Evidence:",
    "empty evidence",
  ),
  "empty evidence must fail",
);
expectAcceptanceRejected(
  replaceExact(acceptance, "without exceptions.", "<TODO>", "placeholder"),
  "a placeholder must fail",
);
expectAcceptanceRejected(
  replaceExact(
    acceptance,
    "observed acceptance check 1",
    "BLOCKED because the recording is missing",
    "blocked evidence",
  ),
  "contradictory BLOCKED evidence must fail",
);
expectAcceptanceRejected(
  replaceExact(
    acceptance,
    "Exact candidate accepted without exceptions.",
    "FAIL remains unresolved.",
    "failed final notes",
  ),
  "contradictory FAIL notes must fail",
);
expectAcceptanceRejected(
  replaceExact(
    acceptance,
    "### 8. Annotation editing and shortcut ownership",
    "### 8. Shortcut smoke",
    "renamed check",
  ),
  "a renamed check must fail",
);
expectAcceptanceRejected(
  replaceExact(
    acceptance,
    "- Result: `PASS`",
    "- Result: `PASS`\n- Result: `PASS`",
    "duplicate result",
  ),
  "a duplicate result must fail",
);
expectAcceptanceRejected(
  replaceExact(
    acceptance,
    "- macOS version: `26.5.2`",
    "- macOS version: `26.5.2`\n- Extra candidate field: value",
    "extra candidate field",
  ),
  "an extra candidate field must fail",
);
expectAcceptanceRejected(
  replaceExact(
    acceptance,
    "- `Scripts/verify-inkbeam.sh` result: `PASS`",
    "- `Scripts/verify-inkbeam.sh` result: `BLOCKED`",
    "blocked automated gate",
  ),
  "a blocked automated gate must fail",
);

const acceptanceCLI = spawnSync(
  process.execPath,
  [SCRIPT_PATH, "acceptance", "-", EXPECTED_SHA],
  { input: acceptance, encoding: "utf8" },
);
assert.equal(
  acceptanceCLI.status,
  0,
  `valid stdin acceptance evidence must pass the CLI:\n${acceptanceCLI.stderr}`,
);
const invalidAcceptanceCLI = spawnSync(
  process.execPath,
  [SCRIPT_PATH, "acceptance", "-", OTHER_SHA],
  { input: acceptance, encoding: "utf8" },
);
assert.notEqual(invalidAcceptanceCLI.status, 0, "the CLI must fail a mismatched SHA");

assert.throws(
  () => validateReleaseInstallReport(
    INSTALL_TEMPLATE,
    EXPECTED_SHA,
    TAG,
    CHECKSUM_SOURCE,
    CHECKSUM_ASSET_HASH,
  ),
  ReleaseEvidenceError,
  "the unfilled release-install template must fail",
);
const installation = validReleaseInstallReport();
const installResult = validateReleaseInstallReport(
  installation,
  EXPECTED_SHA,
  TAG,
  CHECKSUM_SOURCE,
  CHECKSUM_ASSET_HASH,
);
assert.equal(installResult.checkCount, 7);
assert.deepEqual(
  installResult.artifacts.map((artifact) => artifact.name),
  [
    "Inkbeam-0.2.0-macos.zip",
    "Inkbeam-Chrome-0.2.0.zip",
    "SHA256SUMS.txt",
  ],
);

const TAG_021 = "v0.2.1";
const CHECKSUM_SOURCE_021 = CHECKSUM_SOURCE.replaceAll("0.2.0", "0.2.1");
const installation021 = installation.replaceAll("0.2.0", "0.2.1");
assert.equal(
  validateReleaseInstallReport(
    installation021,
    EXPECTED_SHA,
    TAG_021,
    CHECKSUM_SOURCE_021,
    CHECKSUM_ASSET_HASH,
  ).expectedTag,
  TAG_021,
  "release-install validation must derive all versioned contracts from the tag",
);
assert.throws(
  () => validateReleaseInstallReport(
    installation021.replace(
      "# Inkbeam v0.2.1 release-installation record",
      "# Inkbeam v0.2.0 release-installation record",
    ),
    EXPECTED_SHA,
    TAG_021,
    CHECKSUM_SOURCE_021,
    CHECKSUM_ASSET_HASH,
  ),
  ReleaseEvidenceError,
  "a stale release-install title must fail",
);
assert.throws(
  () => validateReleaseInstallReport(
    installation021.replace("reports version `0.2.1`", "reports version `0.2.0`"),
    EXPECTED_SHA,
    TAG_021,
    CHECKSUM_SOURCE_021,
    CHECKSUM_ASSET_HASH,
  ),
  ReleaseEvidenceError,
  "stale app-version prose must fail",
);
expectInstallRejected(
  replaceExact(
    installation,
    `\`${APP_HASH}\``,
    `\`${"c".repeat(64)}\``,
    "wrong app checksum",
  ),
  "a downloaded artifact checksum mismatch must fail",
);
expectInstallRejected(
  replaceExact(installation, "`123456` | `PASS`", "`0` | `PASS`", "zero size"),
  "a zero-byte artifact must fail",
);
expectInstallRejected(
  replaceExact(
    installation,
    "https://github.com/gihwan-dev/inkbeam/actions/runs/1001",
    "https://github.com/gihwan-dev/inkbeam/actions/runs/latest",
    "invalid workflow URL",
  ),
  "a non-run workflow URL must fail",
);
expectInstallRejected(
  replaceExact(installation, "- Result: `PASS`", "- Result: `BLOCKED`", "blocked install"),
  "a blocked installed check must fail",
);
expectInstallRejected(
  replaceExact(
    installation,
    "observed installed-release check 1",
    "FAIL checksum proof is missing",
    "failed install evidence",
  ),
  "contradictory FAIL install evidence must fail",
);
expectInstallRejected(
  replaceExact(
    installation,
    "Live assets accepted without exceptions.",
    "BLOCKED pending another run.",
    "blocked install notes",
  ),
  "contradictory BLOCKED install notes must fail",
);
expectInstallRejected(
  replaceExact(
    installation,
    "- Git note attachment SHA: `1234567890abcdef1234567890abcdef12345678`",
    `- Git note attachment SHA: \`${OTHER_SHA}\``,
    "wrong note SHA",
  ),
  "a release-install note bound to another SHA must fail",
);

process.stdout.write("Release evidence validator tests passed.\n");
