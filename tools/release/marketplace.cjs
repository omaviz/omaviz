'use strict';
const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const target = 'omacom/omarchy-plugin-marketplace';
function request({id, repository, commit}) {
  if (!/^[a-f0-9]{40}$/.test(commit)) throw new Error('Expected a full commit SHA');
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) throw new Error('Expected owner/repository');
  if (!/^[a-z0-9][a-z0-9._-]{0,127}$/.test(id)) throw new Error('Invalid plugin ID');
  const title = `[Verify]: ${id} ${commit.slice(0, 12)}`;
  const marker = `<!-- omaviz-marketplace:${commit} -->`;
  const fields = {
    'verification-action': 'Verify and publish a newer upstream commit',
    'plugin-id': id,
    repository: `https://github.com/${repository}`,
    'target-commit': commit,
  };
  const url = new URL(`https://github.com/${target}/issues/new`);
  url.search = new URLSearchParams({template: 'verify-plugin.yml', title, ...fields}).toString();
  const body = `${marker}\n\n### Verification action\n\n${fields['verification-action']}\n\n### Plugin ID\n\n${id}\n\n### Repository URL\n\n${fields.repository}\n\n### Target commit\n\n${commit}\n\n### Verification acknowledgment\n\n- [x] I understand that only the exact target commit can become a verified marketplace snapshot and that verification is not a security audit.\n\n### Standard installation acknowledgment\n\n- [ ] I confirm that this listed root plugin supports the standard Omarchy installation path and does not require manual setup.\n`;
  return {title, body, url: url.href, marker};
}
module.exports = {request};
if (require.main === module) {
  const manifest = JSON.parse(fs.readFileSync('manifest.json', 'utf8'));
  const repository = process.env.GITHUB_REPOSITORY;
  const commit = process.env.RELEASE_COMMIT;
  const data = request({id: manifest.id, repository, commit});
  if (!process.argv.includes('--submit')) {
    console.log(`## Marketplace verification\n\n[Request verification of this exact commit](${data.url}). Confirm the acknowledgment before submitting. Publication remains subject to the marketplace checks and maintainer approval.\n`);
  } else if (!process.env.GH_TOKEN) {
    console.log('::warning::MARKETPLACE_TOKEN is not configured; use the verification link in the release notes.');
  } else {
    const gh = args => execFileSync('gh', args, {encoding: 'utf8'}).trim();
    // The upstream form requires current HEAD. Never submit an older release.
    const head = gh(['api', `repos/${repository}/commits/master`, '--jq', '.sha']);
    if (head !== commit) {
      console.log('::warning::Release is no longer master HEAD; skipping stale marketplace submission.');
    } else {
      const pages = JSON.parse(gh(['api', '--paginate', '--slurp', `repos/${target}/issues?state=all&per_page=100`]));
      const existing = pages.flat().find(issue => !issue.pull_request && issue.body?.includes(data.marker));
      if (existing) console.log(`Marketplace request already exists: ${existing.html_url}`);
      else console.log(gh(['issue', 'create', '--repo', target, '--title', data.title, '--body', data.body]));
    }
  }
}
