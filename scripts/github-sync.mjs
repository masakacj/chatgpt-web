import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const owner = process.env.GITHUB_OWNER || 'masakacj';
const repo = process.env.GITHUB_REPO || 'chatgpt-web';
const branch = process.env.GITHUB_BRANCH || 'main';
const root = process.cwd();

function gitCredential() {
  const out = execFileSync('git', ['credential', 'fill'], {
    input: 'protocol=https\nhost=github.com\n\n',
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  const values = Object.fromEntries(
    out.trim().split(/\r?\n/).map((line) => {
      const i = line.indexOf('=');
      return [line.slice(0, i), line.slice(i + 1)];
    })
  );

  if (!values.username || !values.password) {
    throw new Error('No GitHub HTTPS credential is available through git credential helper');
  }

  return values;
}

const credential = gitCredential();
const auth = 'Basic ' + Buffer.from(`${credential.username}:${credential.password}`).toString('base64');

async function api(endpoint, options = {}) {
  const response = await fetch(`https://api.github.com${endpoint}`, {
    ...options,
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: auth,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'chatgpt-web-bootstrap',
      ...(options.headers || {}),
    },
  });

  if (response.status === 204) return null;
  const raw = await response.text();
  const data = raw ? JSON.parse(raw) : null;

  if (!response.ok) {
    throw new Error(`GitHub API ${response.status}: ${data?.message || raw}`);
  }
  return data;
}

function listFiles(dir = root, prefix = '') {
  const ignored = new Set(['.git', 'node_modules', 'DerivedData', 'build', 'dist']);
  const result = [];

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ignored.has(entry.name)) continue;

    const full = path.join(dir, entry.name);
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;

    if (entry.isDirectory()) {
      result.push(...listFiles(full, relative));
    } else if (entry.isFile()) {
      result.push({ full, relative: relative.replaceAll('\\\\', '/') });
    }
  }

  return result.sort((a, b) => a.relative.localeCompare(b.relative));
}

async function getHead() {
  try {
    const ref = await api(`/repos/${owner}/${repo}/git/ref/heads/${branch}`);
    const commit = await api(`/repos/${owner}/${repo}/git/commits/${ref.object.sha}`);
    return {
      commitSHA: ref.object.sha,
      treeSHA: commit.tree.sha,
    };
  } catch (error) {
    const message = String(error.message || error);
    if (message.includes('GitHub API 409') || message.includes('GitHub API 404')) {
      return null;
    }
    throw error;
  }
}

async function ensureInitialized() {
  const existing = await getHead();
  if (existing) return existing;

  const readmePath = path.join(root, 'README.md');
  const readme = fs.readFileSync(readmePath);

  await api(`/repos/${owner}/${repo}/contents/README.md`, {
    method: 'PUT',
    body: JSON.stringify({
      message: 'Initialize repository',
      content: readme.toString('base64'),
    }),
  });

  const initialized = await getHead();
  if (!initialized) throw new Error('Repository bootstrap completed but main branch is still unavailable');
  return initialized;
}

async function syncRepository(message) {
  const files = listFiles();
  const head = await ensureInitialized();
  const tree = [];

  for (const file of files) {
    const data = fs.readFileSync(file.full);
    const blob = await api(`/repos/${owner}/${repo}/git/blobs`, {
      method: 'POST',
      body: JSON.stringify({
        content: data.toString('base64'),
        encoding: 'base64',
      }),
    });

    tree.push({
      path: file.relative,
      mode: '100644',
      type: 'blob',
      sha: blob.sha,
    });
  }

  const createdTree = await api(`/repos/${owner}/${repo}/git/trees`, {
    method: 'POST',
    body: JSON.stringify({
      base_tree: head.treeSHA,
      tree,
    }),
  });

  const commit = await api(`/repos/${owner}/${repo}/git/commits`, {
    method: 'POST',
    body: JSON.stringify({
      message,
      tree: createdTree.sha,
      parents: [head.commitSHA],
    }),
  });

  await api(`/repos/${owner}/${repo}/git/refs/heads/${branch}`, {
    method: 'PATCH',
    body: JSON.stringify({ sha: commit.sha, force: false }),
  });

  return commit.sha;
}

async function createTag(tagName) {
  const head = await getHead();
  if (!head) throw new Error('Cannot tag an empty repository');

  try {
    const existing = await api(`/repos/${owner}/${repo}/git/ref/tags/${encodeURIComponent(tagName)}`);
    console.log(JSON.stringify({ ok: true, tag: tagName, exists: true, sha: existing.object.sha }, null, 2));
    return;
  } catch (error) {
    if (!String(error.message || error).includes('GitHub API 404')) throw error;
  }

  const ref = await api(`/repos/${owner}/${repo}/git/refs`, {
    method: 'POST',
    body: JSON.stringify({ ref: `refs/tags/${tagName}`, sha: head.commitSHA }),
  });

  console.log(JSON.stringify({ ok: true, tag: tagName, sha: ref.object.sha }, null, 2));
}

const args = process.argv.slice(2);

if (args[0] === '--tag') {
  if (!args[1]) throw new Error('Usage: npm run release:tag -- v0.1.0');
  await createTag(args[1]);
} else {
  const message = args.join(' ') || 'Update ChatGPT Web';
  const sha = await syncRepository(message);
  console.log(JSON.stringify({ ok: true, branch, sha }, null, 2));
}
