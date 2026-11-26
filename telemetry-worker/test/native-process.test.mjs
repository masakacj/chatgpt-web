import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';

const source = readFileSync(new URL('../../OptimizedResources/Observation/native-process.js', import.meta.url), 'utf8');
const ID = 'optimized-native-process-style';

function fixture({origin='https://chatgpt.com', main=true, early=false}={}) {
  const styles = [], events = [];
  const root = {appendChild: el => styles.push(el)};
  const document = {
    documentElement: early ? null : root,
    getElementById: id => styles.find(el => el.id === id),
    createElement: tag => ({tag}),
    addEventListener: (name, fn, options) => events.push({name, fn, options}),
    querySelector() { throw Error('native relief must not scan'); },
    querySelectorAll() { throw Error('native relief must not scan'); }
  };
  const window = {}; window.top = main ? window : {};
  const world = {window,document,location:{origin}};
  const run = () => runInNewContext(source,world);
  return {styles,events,document,root,run};
}

test('native process installs one scoped stylesheet without scans or network operations',()=>{
  const x=fixture();x.run();x.run();
  assert.equal(x.styles.length,1);
  assert.equal(x.styles[0].id,ID);
  const css=x.styles[0].textContent;
  assert.match(css,/data-turn-key/);
  assert.match(css,/data-mcp-app-portal-target/);
  assert.match(css,/iframe\.pointer-events-none/);
  assert.match(css,/apply patch/);
  assert.match(css,/data-message-channel="final"/);
  assert.match(css,/data-tool-interaction/);
  assert.match(css,/:not\(:focus-within\)/);
  assert.match(css,/display:none!important/);
  assert.doesNotMatch(source,/\bnew\s+MutationObserver\b|\bsetInterval\s*\(|\bfetch\s*\(|\.querySelector(?:All)?\s*\(|\.click\s*\(|\.removeAttribute\s*\(/);
});

test('native process runs only in official main frame',()=>{
  for(const opts of [{origin:'https://example.com'},{main:false}]) {
    const x=fixture(opts);x.run();assert.equal(x.styles.length,0);
    assert.equal(x.events.length,0);
  }
});

test('document-start without root installs once at DOMContentLoaded',()=>{
  const x=fixture({early:true});x.run();
  assert.equal(x.styles.length,0);
  assert.equal(x.events.length,1);
  assert.equal(x.events[0].name,'DOMContentLoaded');
  assert.equal(x.events[0].options.once,true);
  x.document.documentElement=x.root;
  x.events[0].fn();x.events[0].fn();
  assert.equal(x.styles.length,1);
});
