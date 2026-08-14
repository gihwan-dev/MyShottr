#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EDITOR_DIST="${REPO_ROOT}/Packages/editor/dist"
EDITOR_SOURCE="${REPO_ROOT}/Packages/editor/src"
EXTENSION_DIST="${REPO_ROOT}/Packages/chrome-extension/dist"
EXTENSION_SOURCE="${REPO_ROOT}/Packages/chrome-extension/src"
EXTENSION_PUBLIC_MANIFEST="${REPO_ROOT}/Packages/chrome-extension/public/manifest.json"
EXTENSION_DIST_MANIFEST="${EXTENSION_DIST}/manifest.json"
APP_INFO_PLIST="${REPO_ROOT}/Config/Inkbeam-Info.plist"

[[ -f "${APP_INFO_PLIST}" ]] \
  || { print -u2 "Missing Inkbeam Info.plist: ${APP_INFO_PLIST}"; exit 1; }

function assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${APP_INFO_PLIST}")"
  [[ "${actual}" == "${expected}" ]] \
    || { print -u2 "Unexpected ${key}: ${actual}"; exit 1; }
}

if /usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' \
  "${APP_INFO_PLIST}" >/dev/null 2>&1; then
  print -u2 'SUEnableAutomaticChecks must be absent so Sparkle obtains consent'
  exit 1
fi

assert_plist_value SUScheduledCheckInterval 86400
assert_plist_value SUAutomaticallyUpdate false
assert_plist_value SUAllowsAutomaticUpdates false
assert_plist_value SUEnableSystemProfiling false
assert_plist_value SUEnableJavaScript false
assert_plist_value SUVerifyUpdateBeforeExtraction true
assert_plist_value SURequireSignedFeed true
assert_plist_value SUSignedFeedFailureExpirationInterval 0

node --input-type=module - \
  "${EDITOR_DIST}" \
  "${EDITOR_SOURCE}" \
  "${EXTENSION_DIST}" \
  "${EXTENSION_SOURCE}" \
  "${EXTENSION_PUBLIC_MANIFEST}" \
  "${EXTENSION_DIST_MANIFEST}" <<'NODE'
import { promises as fs } from "node:fs";
import { extname, relative, resolve, sep } from "node:path";

const [
  editorDist,
  editorSource,
  extensionDist,
  extensionSource,
  extensionPublicManifest,
  extensionDistManifest,
] = process.argv.slice(2);

const requiredDirectories = [
  editorDist,
  editorSource,
  extensionDist,
  extensionSource,
];
const requiredFiles = [
  extensionPublicManifest,
  extensionDistManifest,
  resolve(editorDist, "index.html"),
  resolve(extensionDist, "service-worker.js"),
];

for (const directory of requiredDirectories) {
  const status = await fs.lstat(directory).catch(() => null);
  assert(
    status?.isDirectory() === true && !status.isSymbolicLink(),
    `Required privacy input is not a real directory: ${directory}`,
  );
}
for (const path of requiredFiles) {
  const status = await fs.lstat(path).catch(() => null);
  assert(
    status?.isFile() === true && !status.isSymbolicLink(),
    `Required privacy input is not a real file: ${path}`,
  );
}

const editorIndexPath = resolve(editorDist, "index.html");
const editorIndex = await fs.readFile(editorIndexPath, "utf8");
assert(
  !containsRemoteURL(editorIndex),
  "Remote URL found in the bundled editor entrypoint",
);
const expectedCSP = [
  "default-src 'none'",
  "connect-src 'none'",
  "object-src 'none'",
  "base-uri 'none'",
  "frame-src 'none'",
  "script-src 'self'",
  "style-src 'self'",
  "img-src 'self'",
];
const csp = editorIndex.match(
  /<meta\s+[^>]*http-equiv=["']Content-Security-Policy["'][^>]*content=["']([^"']*(?:'[^']*'[^"']*)*)["'][^>]*>/i,
)?.[1];
assert(csp, "Bundled editor entrypoint is missing its Content Security Policy");
const cspDirectives = csp
  .split(";")
  .map((directive) => directive.trim())
  .filter(Boolean);
assert(
  JSON.stringify(cspDirectives) === JSON.stringify(expectedCSP),
  "Bundled editor Content Security Policy changed from the local-only contract",
);

const assetReferences = [
  ...editorIndex.matchAll(/\b(?:src|href)=["']([^"']+)["']/gi),
].map((match) => match[1]);
assert(assetReferences.length > 0, "Bundled editor has no local asset references");
for (const reference of assetReferences) {
  assert(
    /^\.\/assets\/index-[A-Za-z0-9_-]+\.(?:js|css)$/.test(reference),
    `Non-local or unexpected editor asset reference: ${reference}`,
  );
  const assetPath = resolve(editorDist, reference);
  assertInside(editorDist, assetPath, "Editor asset escaped the dist directory");
  const status = await fs.lstat(assetPath).catch(() => null);
  assert(
    status?.isFile() === true && !status.isSymbolicLink(),
    `Referenced editor asset is missing or symbolic: ${reference}`,
  );
}
assert(
  assetReferences.some((reference) => reference.endsWith(".js")),
  "Bundled editor is missing its local JavaScript asset",
);
assert(
  assetReferences.some((reference) => reference.endsWith(".css")),
  "Bundled editor is missing its local stylesheet asset",
);

for (const path of await listFiles(editorDist)) {
  if (extname(path) === ".js") {
    const source = await fs.readFile(path, "utf8");
    assertNoRemoteImport(source, display(path));
    assertOnlyReviewedBundleURLLiterals(source, display(path));
    continue;
  }
  if (extname(path) !== ".css") continue;
  const source = await fs.readFile(path, "utf8");
  assert(
    !containsRemoteURL(source)
      && !/@import\s+(?:url\s*\()?\s*["']?(?:https?:)?\/\//i.test(source)
      && !/url\s*\(\s*["']?(?:https?:)?\/\//i.test(source),
    `Remote stylesheet asset found: ${display(path)}`,
  );
}

const productionSourcePattern =
  /\.(?:ts|tsx|js|jsx|html|css)$/;
for (const path of await listFiles(editorSource)) {
  if (!productionSourcePattern.test(path) || isNonProductionSource(path)) {
    continue;
  }
  const source = await fs.readFile(path, "utf8");
  assertNoNetworkAPI(source, display(path));
  assert(
    !containsRemoteURL(source),
    `Remote URL found in editor production source: ${display(path)}`,
  );
}

const publicManifest = await readManifest(extensionPublicManifest);
const distManifest = await readManifest(extensionDistManifest);
const expectedExtensionPageCSP =
  "default-src 'none'; script-src 'self'; connect-src 'none'; "
  + "object-src 'none'; base-uri 'none'; frame-src 'none'; "
  + "img-src 'self'; style-src 'self'";
for (const [label, manifest] of [
  ["extension source manifest", publicManifest],
  ["built extension manifest", distManifest],
]) {
  assert(
    manifest.manifest_version === 3,
    `${label} is not Manifest V3`,
  );
  assert(
    JSON.stringify(manifest.permissions) ===
      JSON.stringify(["activeTab", "nativeMessaging"]),
    `${label} permissions differ from activeTab + nativeMessaging`,
  );
  for (const forbiddenKey of [
    "optional_permissions",
    "host_permissions",
    "optional_host_permissions",
    "content_scripts",
  ]) {
    assert(
      !Object.hasOwn(manifest, forbiddenKey),
      `${label} contains forbidden ${forbiddenKey}`,
    );
  }
  assert(
    manifest.background?.service_worker === "service-worker.js"
      && manifest.background?.type === "module",
    `${label} has an unexpected background entrypoint`,
  );
  assert(
    JSON.stringify(manifest.content_security_policy)
      === JSON.stringify({ extension_pages: expectedExtensionPageCSP }),
    `${label} Content Security Policy changed from the local-only contract`,
  );
}

for (const path of await listFiles(extensionSource)) {
  if (!productionSourcePattern.test(path) || isNonProductionSource(path)) {
    continue;
  }
  const source = await fs.readFile(path, "utf8");
  assertNoExtensionPrivilegeAPI(source, display(path));
  assertNoNetworkAPI(source, display(path));
  assert(
    !containsRemoteURL(source),
    `Remote URL found in extension production source: ${display(path)}`,
  );
}

for (const path of await listFiles(extensionDist)) {
  if (extname(path) !== ".js" || path.endsWith(".map")) continue;
  const source = await fs.readFile(path, "utf8");
  assertNoExtensionPrivilegeAPI(source, display(path));
  assertNoNetworkAPI(source, display(path));
  assert(
    !containsRemoteURL(source),
    `Remote URL found in built extension source: ${display(path)}`,
  );
}

function assertNoNetworkAPI(source, label) {
  const forbidden = [
    [/\b(?:(?:globalThis|window)\s*\.\s*)?fetch\s*\(/, "fetch"],
    [/\bnew\s+(?:(?:globalThis|window)\s*\.\s*)?XMLHttpRequest\s*\(/, "XMLHttpRequest"],
    [/\bnew\s+(?:(?:globalThis|window)\s*\.\s*)?WebSocket\s*\(/, "WebSocket"],
    [/\bnew\s+(?:(?:globalThis|window)\s*\.\s*)?EventSource\s*\(/, "EventSource"],
    [/\b(?:navigator|window\s*\.\s*navigator)\s*\.\s*sendBeacon\s*\(/, "sendBeacon"],
  ];
  for (const [pattern, name] of forbidden) {
    assert(
      !pattern.test(source),
      `Direct network API reference ${name} found in ${label}`,
    );
  }
}

function assertNoRemoteImport(source, label) {
  const remoteImportPatterns = [
    /\bimport\s*\(\s*["'](?:https?|wss?):\/\//i,
    /\bimportScripts\s*\(\s*["'](?:https?|wss?):\/\//i,
    /\brequire\s*\(\s*["'](?:https?|wss?):\/\//i,
    /\bfrom\s*["'](?:https?|wss?):\/\//i,
    /sourceMappingURL\s*=\s*(?:https?|wss?):\/\//i,
  ];
  for (const pattern of remoteImportPatterns) {
    assert(!pattern.test(source), `Remote import found in ${label}`);
  }
}

function assertOnlyReviewedBundleURLLiterals(source, label) {
  const reviewedPrefixes = [
    "https://react.dev/errors/",
    "http://www.w3.org/",
    "https://konvajs.org/docs/",
    "https://github.com/konvajs/react-konva/issues/",
    "https://konvajs.github.io/docs/",
    "https://json-schema.org/",
    "http://json-schema.org/",
    "http://[${",
  ];
  const remoteLiterals = [
    ...source.matchAll(/(?:https?|wss?):\/\/[^\s"'`<>\\)]+/gi),
  ].map((match) => match[0]);
  for (const literal of remoteLiterals) {
    assert(
      reviewedPrefixes.some((prefix) => literal.startsWith(prefix)),
      `Unreviewed remote URL literal found in ${label}: ${literal}`,
    );
  }
}

function assertNoExtensionPrivilegeAPI(source, label) {
  const forbidden = [
    [/\bchrome\s*(?:\.\s*scripting\b|\[\s*["']scripting["']\s*\])/, "chrome.scripting"],
    [/\bchrome\s*(?:\.\s*webRequest\b|\[\s*["']webRequest["']\s*\])/, "chrome.webRequest"],
  ];
  for (const [pattern, name] of forbidden) {
    assert(!pattern.test(source), `Forbidden API ${name} found in ${label}`);
  }
}

function containsRemoteURL(source) {
  return /(?:https?|wss?):\/\/|(?:src|href)\s*=\s*["']\/\//i.test(source);
}

function isNonProductionSource(path) {
  const normalized = path.split(sep).join("/");
  return normalized.endsWith(".d.ts")
    || /\.(?:test|spec)\.[^.]+$/.test(normalized)
    || normalized.includes("/test/")
    || normalized.includes("/tests/")
    || normalized.endsWith(".map");
}

async function listFiles(directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  const paths = [];
  for (const entry of entries) {
    const path = resolve(directory, entry.name);
    assert(
      !entry.isSymbolicLink(),
      `Privacy input contains a symbolic link: ${path}`,
    );
    if (entry.isDirectory()) {
      paths.push(...await listFiles(path));
    } else if (entry.isFile()) {
      paths.push(path);
    } else {
      throw new Error(`Privacy input contains an unsupported entry: ${path}`);
    }
  }
  return paths.sort();
}

async function readManifest(path) {
  let manifest;
  try {
    manifest = JSON.parse(await fs.readFile(path, "utf8"));
  } catch (error) {
    throw new Error(`Invalid extension manifest ${path}: ${error}`);
  }
  assert(
    manifest && typeof manifest === "object" && !Array.isArray(manifest),
    `Extension manifest must be a JSON object: ${path}`,
  );
  return manifest;
}

function assertInside(root, path, message) {
  const child = relative(resolve(root), resolve(path));
  assert(
    child !== "" && child !== ".." && !child.startsWith(`..${sep}`),
    message,
  );
}

function display(path) {
  return relative(process.cwd(), path);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
NODE

echo "Privacy verification passed"
