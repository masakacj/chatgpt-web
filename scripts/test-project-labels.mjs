import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const script = fs.readFileSync('safari/chatgpt-safari.user.js', 'utf8');
const start = script.indexOf('  function projectIdFromPath(');
const end = script.indexOf('  function currentConversationId()', start);
assert.ok(start > 0 && end > start, 'project helpers are present');

class FakeElement {
  constructor(href = '', text = '', title = '') {
    this.attrs = href ? { href } : {};
    this.href = href ? new URL(href, 'https://chatgpt.com').href : '';
    this.textContent = text;
    this.title = title;
    this.children = [];
  }
  matches(query) {
    if (query.includes('/g/g-p-')) return this.href.includes('/g/g-p-');
    return Boolean(this.getAttribute('data-conversation-id'));
  }
  getAttribute(name) { return this.attrs[name] ?? null; }
  setAttribute(name, value) { this.attrs[name] = String(value); }
  hasAttribute(name) { return this.attrs[name] !== undefined; }
  removeAttribute(name) { delete this.attrs[name]; }
  querySelector(query) {
    if (query.includes('project-name') && this.title) {
      return { textContent: this.title };
    }
    if (query.includes('[data-project-id]')) {
      return this.children.find(c => c.hasAttribute('data-project-id')) ?? null;
    }
    if (query.includes('[data-gizmo-id]')) {
      return this.children.find(c => c.hasAttribute('data-gizmo-id')) ?? null;
    }
    return this.children.find(c => c.href) ?? null;
  }
  querySelectorAll(query) {
    const matches = [];
    for (const child of this.children) {
      if (child.matches(query)) matches.push(child);
      matches.push(...child.querySelectorAll(query));
    }
    return matches;
  }
}
class FakeAnchor extends FakeElement {}
class FakeDocument extends FakeElement {}

let pathname = '/g/g-p-project001/c/11111111-1111-4111-8111-111111111111';
const location = {
  origin: 'https://chatgpt.com',
  get pathname() { return pathname; },
};
const values = new Map();
const localStorage = {
  getItem(key) { return values.get(key) ?? null; },
  setItem(key, value) { values.set(key, value); },
};
const state = {
  projectIndex: {
    names: Object.create(null),
    chats: Object.create(null),
  },
};
const ctx = {
  URL, Date, state, location, localStorage,
  Element: FakeElement,
  HTMLAnchorElement: FakeAnchor,
  Document: FakeDocument,
  PROJECT_INDEX_KEY: 'test-sidebar-projects',
  PROJECT_LINK_QUERY: 'a[href*="/g/g-p-"]',
  PROJECT_LABEL_ATTR: 'data-cgpt-project-label',
  currentConversationId() {
    return pathname.match(/\/c\/([^/]+)/)?.[1] ?? null;
  },
  conversationIdFromHref(href) {
    return new URL(href, location.origin).pathname.match(/\/c\/([^/]+)/)?.[1] ?? null;
  },
};
vm.createContext(ctx);
vm.runInContext(
  script.slice(start, end) +
  '\nglobalThis.helpers = {' +
  [
    'projectIdFromPath', 'projectIdFromHref', 'cleanProjectName',
    'indexProjectNames', 'rememberProjectChat', 'projectIdForChatItem',
    'renderProjectLabel', 'saveProjectIndex', 'loadProjectIndex',
    'rememberCurrentProjectChat',
  ].join(',') + '};',
  ctx
);
const h = ctx.helpers;
const chatId = '11111111-1111-4111-8111-111111111111';

assert.equal(h.projectIdFromPath(pathname), 'g-p-project001');
assert.equal(h.projectIdFromPath('/c/' + chatId), null);
assert.equal(h.projectIdFromHref('https://untrusted.example/g/g-p-project001'), null);
assert.equal(h.cleanProjectName(' 项目： 开发工作 '), '开发工作');

const root = new FakeDocument();
const project = new FakeAnchor('/g/g-p-project001', '开发工作');
const projectChatId = '55555555-5555-4555-8555-555555555555';
const projectChat = new FakeAnchor('/g/g-p-project001/c/' + projectChatId, '项目主页中的聊天');
root.children.push(project, projectChat);
assert.equal(h.indexProjectNames(root), true);
assert.equal(state.projectIndex.chats[projectChatId]?.pid, 'g-p-project001');
assert.equal(h.rememberProjectChat(chatId, 'g-p-project001'), true);

const recent = new FakeAnchor('/c/' + chatId, '一个聊天');
h.renderProjectLabel(recent, chatId);
assert.equal(recent.getAttribute('data-cgpt-project-label'), '开发工作');

h.saveProjectIndex();
assert.equal(h.loadProjectIndex().chats[chatId]?.pid, 'g-p-project001');

project.textContent = '工作项目';
assert.equal(h.indexProjectNames(root), true);
h.renderProjectLabel(recent, chatId);
assert.equal(recent.getAttribute('data-cgpt-project-label'), '工作项目');

const nested = new FakeAnchor('/c/22222222-2222-4222-8222-222222222222');
nested.children.push(new FakeElement());
nested.children[0].setAttribute('data-project-id', 'g-p-project001');
assert.equal(
  h.projectIdForChatItem(nested, '22222222-2222-4222-8222-222222222222'),
  'g-p-project001'
);

const outside = new FakeAnchor('/c/33333333-3333-4333-8333-333333333333');
assert.equal(
  h.projectIdForChatItem(outside, '33333333-3333-4333-8333-333333333333'),
  null
);
h.renderProjectLabel(outside, '33333333-3333-4333-8333-333333333333');
assert.equal(outside.hasAttribute('data-cgpt-project-label'), false);

pathname = '/g/g-p-project002/c/44444444-4444-4444-8444-444444444444';
h.rememberCurrentProjectChat();
assert.equal(state.projectIndex.chats['44444444-4444-4444-8444-444444444444'].pid, 'g-p-project002');

const noName = h.loadProjectIndex();
assert.equal(noName.chats['44444444-4444-4444-8444-444444444444'].pid, 'g-p-project002');

console.log('[project labels] project URL, project name, cache and badge tests passed');
