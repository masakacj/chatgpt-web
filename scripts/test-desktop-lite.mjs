import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
// Retirement guard replaces the obsolete optimizer tests. iOS runtime tests
// remain untouched. The PC production code lives in the Orchestrator project.
const entry = fs.readFileSync('safari/chatgpt-desktop-lite.user.js','utf8');
assert.match(entry,/RETIRED 2026-10-10/);
assert.doesNotMatch(entry,/==UserScript==|@match|@updateURL|@downloadURL|MutationObserver|setInterval|addEventListener|document\./);
new vm.Script(entry);
assert.ok(fs.existsSync('PC_EXTENSION_HANDOFF.md'));
assert.ok(fs.existsSync('AGENTS.md'));
console.log('[PC extension-only] retired userscript cannot be reinstalled or activated');
