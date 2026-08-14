const contracts = new Map([
  [
    "v0.2.0-rc.1",
    {
      version: "0.2.0",
      build: 2,
      channel: "beta",
      dmg: "Inkbeam-0.2.0-rc.1.dmg",
      chromeZip: "Inkbeam-Chrome-0.2.0-rc.1.zip",
      releaseTitle: "Inkbeam v0.2.0-rc.1",
      prerelease: true,
    },
  ],
  [
    "v0.2.0-rc.2",
    {
      version: "0.2.0",
      build: 3,
      channel: "beta",
      dmg: "Inkbeam-0.2.0-rc.2.dmg",
      chromeZip: "Inkbeam-Chrome-0.2.0-rc.2.zip",
      releaseTitle: "Inkbeam v0.2.0-rc.2",
      prerelease: true,
    },
  ],
  [
    "v0.2.0",
    {
      version: "0.2.0",
      build: 4,
      channel: "stable",
      dmg: "Inkbeam-0.2.0.dmg",
      chromeZip: "Inkbeam-Chrome-0.2.0.zip",
      releaseTitle: "Inkbeam v0.2.0 (Final Candidate)",
      prerelease: true,
    },
  ],
]);

export function contractFor(tag) {
  const contract = contracts.get(tag);
  if (!contract) {
    throw new Error(`unsupported release tag: ${String(tag)}`);
  }
  return Object.freeze({ tag, ...contract });
}

export function versionNameForTag(tag) {
  return contractFor(tag).tag.slice(1);
}

export function releaseChannelLabel(channel) {
  switch (channel) {
    case "beta":
      return "Release Candidate";
    case "stable":
      return "Stable";
    default:
      throw new Error(`unsupported release channel: ${String(channel)}`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    const tag = process.argv[2];
    if (!tag || process.argv.length !== 3) {
      process.stderr.write("usage: release-contract.mjs TAG\n");
      process.exit(64);
    }
    process.stdout.write(`${JSON.stringify(contractFor(tag), null, 2)}\n`);
  } catch (error) {
    process.stderr.write(`release-contract: ${error.message}\n`);
    process.exit(65);
  }
}
