#!/usr/bin/env node
"use strict"
const fs = require("node:fs")
const path = require("node:path")

const root = path.resolve(__dirname, "..")
const read = (name) => fs.readFileSync(path.join(root, name))
const meta = JSON.parse(read(".github/marketplace.json"))
const manifest = JSON.parse(read("manifest.json"))
const pkg = JSON.parse(read("package.json"))
const categories = new Set(["Appearance", "Desktop", "Developer Tools", "Hardware", "Kids", "Productivity", "System", "Widgets", "Other"])
// The labels are the exact visible choices in the marketplace issue form.
const tags = new Map(Object.entries({
  ai: "AI", bar: "Bar", education: "Education", games: "Games",
  hyprland: "Hyprland", kids: "Kids", launcher: "Launcher", media: "Media",
  "power-management": "Power management", quickshell: "Quickshell",
  security: "Security", system: "System", vpn: "VPN", workspaces: "Workspaces"
}))
const fail = (message) => { throw new Error(message) }
if (meta.repository !== "https://github.com/omaviz/omaviz") fail("repository must be the public root URL")
if (!categories.has(meta.category)) fail("invalid marketplace category: " + meta.category)
if (!Array.isArray(meta.tags) || meta.tags.length < 1 || meta.tags.length > 3 || new Set(meta.tags).size !== meta.tags.length || meta.tags.some(t => !tags.has(t))) fail("marketplace tags must be 1–3 distinct allowed values")
if (manifest.id !== "org.omaviz.visualizer" || !manifest.entryPoints?.barWidget || !fs.existsSync(path.join(root, manifest.entryPoints.barWidget))) fail("invalid plugin identity or entry point")
if (fs.existsSync(path.join(root, "AGENTS.md"))) fail("root AGENTS.md must not ship in the marketplace checkout")
if (manifest.version !== pkg.version) fail("manifest and package versions differ")
if (!fs.existsSync(path.join(root, "LICENSE"))) fail("root LICENSE missing")
const readme = read("README.md").toString()
if (!/omarchy plugin add/.test(readme) || !/omarchy plugin remove/.test(readme)) fail("README must contain marketplace install and removal commands")
const png = read("preview.png")
if (png.toString("hex", 0, 8) !== "89504e470d0a1a0a") fail("preview.png is not a PNG")
const width = png.readUInt32BE(16), height = png.readUInt32BE(20)
if (png.length > 50e6 || width * height > 40e6) fail("preview exceeds marketplace size limits")

if (process.argv.includes("--check")) {
  process.stdout.write(`Marketplace preflight OK: ${manifest.id} v${manifest.version}, ${meta.category}, ${meta.tags.join(", ")}, ${width}x${height} preview\n`)
} else if (process.argv.includes("--title")) {
  process.stdout.write(`[Plugin]: ${manifest.name}\n`)
} else {
  process.stdout.write(`### Repository URL\n\n${meta.repository}\n\n### Category\n\n${meta.category}\n\n### Tags\n\n${meta.tags.map(tag => tags.get(tag)).join(", ")}\n\n### Suggest a missing tag\n\n_No response_\n\n### Maintainer notes\n\n_No response_\n\n### Submission checklist\n\n- [x] The repository is public and contains installation and removal instructions.\n- [x] I have documented the plugin license and any external dependencies.\n- [x] I confirm that I own or have permission to submit this plugin and its preview assets.\n- [x] The plugin does not overwrite user configuration without explicit consent.\n- [x] I understand that approval is for listing and is not a security review.\n`)
}
