#!/usr/bin/env node
"use strict"
const fs = require("node:fs")
const path = require("node:path")
const { request } = require("./release/marketplace.cjs")
const root = path.resolve(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
// CI supplies GITHUB_SHA. Local callers pass the exact *merged master* SHA.
const sha = (process.env.MARKETPLACE_COMMIT || process.env.GITHUB_SHA || "").trim()
if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error("update target must be a full commit SHA")
if (manifest.id !== "org.omaviz.visualizer") throw new Error("marketplace listing ID changed")
const form = request({ id: manifest.id, repository: "omaviz/omaviz", commit: sha })
if (process.argv.includes("--check")) {
  process.stdout.write(`Marketplace update target: ${manifest.id} at ${sha}\n`)
} else if (process.argv.includes("--title")) {
  process.stdout.write(form.title + "\n")
} else {
  process.stdout.write(form.body)
}
