import { execFileSync } from 'node:child_process';

const owner = process.env.GITHUB_OWNER || 'masakacj';
const repo = process.env.GITHUB_REPO || 'chatgpt-web';

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

async function api(endpoint) {
  const response = await fetch(`https://api.github.com${endpoint}`, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: auth,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'chatgpt-web-status',
    },
  });
  const data = await response.json();
  if (!response.ok) throw new Error(`GitHub API ${response.status}: ${data.message}`);
  return data;
}

const runs = await api(`/repos/${owner}/${repo}/actions/runs?per_page=5`);
const latestRun = runs.workflow_runs[0];
let jobs = [];
if (latestRun) {
  const jobData = await api(`/repos/${owner}/${repo}/actions/runs/${latestRun.id}/jobs?per_page=20`);
  jobs = jobData.jobs.map((job) => ({
    id: job.id,
    name: job.name,
    status: job.status,
    conclusion: job.conclusion,
    html_url: job.html_url,
    steps: job.steps?.map((step) => ({
      number: step.number,
      name: step.name,
      status: step.status,
      conclusion: step.conclusion,
    })) || [],
  }));
}
let releases = { releases: [] };
try {
  releases = await api(`/repos/${owner}/${repo}/releases?per_page=5`);
} catch {}

console.log(JSON.stringify({
  runs: runs.workflow_runs.map((r) => ({
    id: r.id,
    name: r.name,
    event: r.event,
    head_sha: r.head_sha,
    status: r.status,
    conclusion: r.conclusion,
    html_url: r.html_url,
    created_at: r.created_at,
    updated_at: r.updated_at,
  })),
  jobs,
  releases: Array.isArray(releases) ? releases.map((r) => ({
    tag_name: r.tag_name,
    html_url: r.html_url,
    draft: r.draft,
    prerelease: r.prerelease,
    assets: r.assets?.map((a) => a.name) || [],
  })) : [],
}, null, 2));
