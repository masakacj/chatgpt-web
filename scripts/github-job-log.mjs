import { execFileSync } from 'node:child_process';

const owner = process.env.GITHUB_OWNER || 'masakacj';
const repo = process.env.GITHUB_REPO || 'chatgpt-web';
const jobId = process.argv[2];
if (!jobId) throw new Error('Usage: node scripts/github-job-log.mjs <job-id>');

const out = execFileSync('git', ['credential', 'fill'], {
  input: 'protocol=https\nhost=github.com\n\n',
  encoding: 'utf8',
  stdio: ['pipe', 'pipe', 'pipe'],
});
const values = Object.fromEntries(out.trim().split(/\r?\n/).map((line) => {
  const i = line.indexOf('=');
  return [line.slice(0, i), line.slice(i + 1)];
}));
if (!values.username || !values.password) throw new Error('GitHub credential unavailable');
const auth = 'Basic ' + Buffer.from(`${values.username}:${values.password}`).toString('base64');

const response = await fetch(`https://api.github.com/repos/${owner}/${repo}/actions/jobs/${jobId}/logs`, {
  headers: {
    Accept: 'application/vnd.github+json',
    Authorization: auth,
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'chatgpt-web-log',
  },
});

if (!response.ok) throw new Error(`GitHub API ${response.status}: ${await response.text()}`);
const text = await response.text();
const lines = text.split(/\r?\n/);
const interesting = lines.filter((line) =>
  /error:|warning:|BUILD FAILED|SwiftCompile|CompileSwift|fatal|Undefined symbols|Command .* failed|xcodebuild:/i.test(line)
);

console.log((interesting.length ? interesting : lines.slice(-160)).slice(-260).join('\n'));
