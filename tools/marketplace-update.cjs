#!/usr/bin/env node
"use strict"
const fs = require("node:fs")
const path = require("node:path")
const root = path.resolve(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
// CI supplies GITHUB_SHA. Local callers pass the exact *merged master* SHA.
const sha = (process.env.MARKETPLACE_COMMIT || process.env.GITHUB_SHA || "").trim()
if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error("update target must be a full commit SHA")
if (manifest.id !== "org.omaviz.visualizer") throw new Error("marketplace listing ID changed")
if (process.argv.includes("--check")) {
  process.stdout.write(`Marketplace update target: ${manifest.id} at ${sha}\n`)
} else if (process.argv.includes("--title")) {
  process.stdout.write(`[Verify]: ${manifest.id} ${sha.slice(0, 12)}\n`)
} else {
  process.stdout.write(`### Verification action\n\nVerify and publish a newer upstream commit\n\n### Plugin ID\n\n${manifest.id}\n\n### Repository URL\n\nhttps://github.com/omaviz/omaviz\n\n### Target commit\n\n${sha}\n\n### Verification acknowledgment\n\n- [x] I understand that only the exact target commit can become a verified marketplace snapshot and that verification is not a security audit.\n\n### Standard installation acknowledgment\n\n- [ ] I confirm that this listed root plugin supports the standard Omarchy installation path and does not require manual setup.\n`)
}
