import crypto from 'node:crypto';
import fs from 'node:fs';

const manifest = JSON.parse(fs.readFileSync('remote/manifest.json', 'utf8'));
const script = fs.readFileSync('remote/perf.js');
const sha256 = crypto.createHash('sha256').update(script).digest('hex');

if (sha256 !== manifest.sha256) {
  console.error('Remote perf manifest hash mismatch');
  console.error('manifest:', manifest.sha256);
  console.error('actual:  ', sha256);
  process.exit(1);
}

const match = script.toString('utf8').match(/ENGINE_VERSION\s*=\s*['"]([^'"]+)['"]/);
if (!match) {
  console.error('ENGINE_VERSION not found in remote/perf.js');
  process.exit(1);
}

if (match[1] !== manifest.version) {
  console.error(`Version mismatch: perf.js=${match[1]} manifest=${manifest.version}`);
  process.exit(1);
}

console.log(JSON.stringify({ ok: true, version: manifest.version, sha256 }, null, 2));
