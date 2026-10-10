import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const script = fs.readFileSync('safari/chatgpt-desktop-lite.user.js', 'utf8');
assert.match(script, /^\/\/ @version\s+0\.2\.2$/m);
assert.match(script, /const VERSION = '0\.2\.2'/);
new vm.Script(script, {filename: 'chatgpt-desktop-lite.user.js'});

const prohibited = [
  /\b(?:innerHTML|outerHTML)\s*=/,
  /\.replaceChildren\(/,
  /\.removeChild\(/,
  /\b(?:fetch|XMLHttpRequest|WebSocket)\s*\(/,
  /\.scrollIntoView\(/,
  /\.scrollTo\(/,
  /(?:window|history)\.pushState\s*=/,
  /(?:window|history)\.replaceState\s*=/
];
for (const pattern of prohibited) {
  assert.doesNotMatch(script, pattern, 'official message/network/navigation must remain native');
}
assert.equal((script.match(/new MutationObserver\(/g) || []).length, 1,
  'only one scoped sidebar mutation observer is allowed');
assert.equal((script.match(/setInterval\(/g) || []).length, 0,
  'no permanent polling interval is allowed');
assert.match(script,/document\.querySelector\('nav,aside'\)|document\.querySelectorAll\('nav,aside'\)/);
assert.match(script,/window\.navigation\?\.addEventListener\('navigatesuccess', onRoute\)/);
assert.match(script,/const STALE_MS = 90000/);
assert.match(script,/return 'uncertain'/);
assert.match(script,/BroadcastChannel\(CHANNEL\)/);

const helper = script.match(/  const chatId = \(href = location.href\) => \{[\s\S]*?\n  \};/);
assert.ok(helper, 'chat ID parser exists');
const location = {
  origin: 'https://chatgpt.com',
  href: 'https://chatgpt.com/g/g-p-example/c/11111111-1111-4111-8111-111111111111'
};
const getChatId = vm.runInNewContext(
  helper[0] + '\nchatId', {location,URL}
);
assert.equal(getChatId(), '11111111-1111-4111-8111-111111111111');
assert.equal(
  getChatId('https://chatgpt.com/c/22222222-2222-4222-8222-222222222222'),
  '22222222-2222-4222-8222-222222222222'
);
assert.equal(getChatId('https://malicious.example/c/22222222-2222-4222-8222-222222222222'), null);
assert.equal(getChatId('https://chatgpt.com/'),null);
assert.equal(getChatId('https://chatgpt.com/c/x'),null);

console.log('[desktop lite] syntax, URL parsing, and native-first safety checks passed');
