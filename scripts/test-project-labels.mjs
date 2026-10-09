import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const script = fs.readFileSync('safari/chatgpt-safari.user.js', 'utf8');
const start = script.indexOf('  function projectIdFromPath(');
const end = script.indexOf('  function currentConversationId()', start);
assert.ok(start > 0 && end > start, 'sidebar project helpers are present');

class FakeElement {
  constructor(href = '', text = '', title = '', tag = 'DIV') {
    this.attrs = href ? { href } : {};
    this.href = href ? new URL(href, 'https://chatgpt.com').href : '';
    this.textContent = text;
    this.title = title;
    this.tagName = tag;
    this.children = [];
    this.parentElement = null;
  }
  append(...children) {
    for (const child of children) {
      child.parentElement = this;
      this.children.push(child);
    }
    return this;
  }
  contains(item) {
    return item === this || this.children.some(child => child.contains(item));
  }
  matches(query) {
    if (query === 'nav,aside,[role="navigation"]') {
      return ['NAV', 'ASIDE'].includes(this.tagName) ||
        this.getAttribute('role') === 'navigation';
    }
    if (query.includes('/g/g-p-')) return this.href.includes('/g/g-p-');
    if (query.includes('/c/')) return this.href.includes('/c/');
    return Boolean(this.getAttribute('data-conversation-id'));
  }
  getAttribute(name) { return this.attrs[name] ?? null; }
  setAttribute(name, value) { this.attrs[name] = String(value); }
  hasAttribute(name) { return this.attrs[name] !== undefined; }
  removeAttribute(name) { delete this.attrs[name]; }
  querySelector(query) {
    if (query.startsWith(':scope >')) {
      return this.children.find(child => ['H2', 'H3', 'HEADER'].includes(child.tagName))
        ?? null;
    }
    if (query.includes('project-name') && this.title) {
      return { textContent: this.title };
    }
    if (query.includes('[data-project-id]')) {
      return this.children.find(c => c.hasAttribute('data-project-id')) ?? null;
    }
    if (query.includes('[data-gizmo-id]')) {
      return this.children.find(c => c.hasAttribute('data-gizmo-id')) ?? null;
    }
    if (query.includes(':not([href*="/c/"])')) {
      const matches = this.querySelectorAll('a[href*="/g/g-p-"]');
      return matches.find(item => !item.href.includes('/c/')) ?? null;
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
class FakeAnchor extends FakeElement {
  constructor(href = '', text = '', title = '') {
    super(href, text, title, 'A');
  }
}
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
  sidebarRoot: null,
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
  ChatGPTDOMAdapter: {
    sidebarRoot() { return state.sidebarRoot; },
  },
};
vm.createContext(ctx);
vm.runInContext(
  script.slice(start, end) +
    '\nglobalThis.helpers = {' +
    [
      'projectIdFromPath', 'projectIdFromHref', 'cleanProjectName',
      'indexProjectNames', 'rememberProjectChat', 'projectIdForChatItem',
      'renderProjectLabel', 'sidebarSectionKind', 'sidebarContextKind',
      'saveProjectIndex', 'loadProjectIndex', 'rememberCurrentProjectChat',
    ].join(',') + '};',
  ctx,
);
const h = ctx.helpers;
const chatId = '11111111-1111-4111-8111-111111111111';

assert.equal(h.projectIdFromPath(pathname), 'g-p-project001');
assert.equal(h.projectIdFromPath('/c/' + chatId), null);
assert.equal(h.projectIdFromHref('https://untrusted.example/g/g-p-project001'), null);
assert.equal(h.cleanProjectName(' 项目： 开发工作 '), '开发工作');
assert.equal(h.sidebarSectionKind('最近'), 'recent');
assert.equal(h.sidebarSectionKind('Recents'), 'recent');
assert.equal(h.sidebarSectionKind('Pinned'), 'other');

const sidebar = new FakeElement('', '', '', 'NAV');
const recentSection = new FakeElement().append(new FakeElement('', '最近', '', 'H2'));
recentSection.setAttribute('data-sidebar-section', 'recents');
const projectSection = new FakeElement().append(new FakeElement('', '项目', '', 'H2'));
projectSection.setAttribute('data-sidebar-section', 'projects');
const pinnedSection = new FakeElement();
pinnedSection.setAttribute('data-sidebar-section', 'pinned');
sidebar.append(recentSection, projectSection, pinnedSection);
state.sidebarRoot = sidebar;

const project = new FakeAnchor('/g/g-p-project001', '开发工作');
const projectChatId = '55555555-5555-4555-8555-555555555555';
const projectChat = new FakeAnchor('/g/g-p-project001/c/' + projectChatId, '项目内会话');
projectSection.append(project, projectChat);
assert.equal(h.indexProjectNames(sidebar), true);
assert.equal(state.projectIndex.chats[projectChatId]?.pid, 'g-p-project001');
assert.equal(h.rememberProjectChat(chatId, 'g-p-project001'), true);

const recent = new FakeAnchor('/c/' + chatId, '一个聊天');
recentSection.append(recent);
h.renderProjectLabel(recent, chatId);
assert.equal(recent.getAttribute('data-cgpt-project-label'), '开发工作',
  'recent project conversation should display project name');

h.renderProjectLabel(projectChat, projectChatId);
assert.equal(projectChat.hasAttribute('data-cgpt-project-label'), false,
  'same conversation inside project folder should not display project name');

// Both links can be present at once. The project-row title stays untouched.
const recentDuplicate = new FakeAnchor('/g/g-p-project001/c/' + projectChatId, '项目内会话');
recentSection.append(recentDuplicate);
h.renderProjectLabel(recentDuplicate, projectChatId);
assert.equal(recentDuplicate.getAttribute('data-cgpt-project-label'), '开发工作',
  'project-scoped route in Recents still displays a project label');

const pinned = new FakeAnchor('/c/' + chatId, '置顶聊天');
pinnedSection.append(pinned);
h.renderProjectLabel(pinned, chatId);
assert.equal(pinned.hasAttribute('data-cgpt-project-label'), false);

projectChat.setAttribute('data-cgpt-project-label', '旧版残留');
h.renderProjectLabel(projectChat, projectChatId);
assert.equal(projectChat.hasAttribute('data-cgpt-project-label'), false,
  'old project-folder labels must be cleaned');

h.saveProjectIndex();
assert.equal(h.loadProjectIndex().chats[chatId]?.pid, 'g-p-project001');

project.textContent = '工作项目';
assert.equal(h.indexProjectNames(sidebar), true);
h.renderProjectLabel(recent, chatId);
assert.equal(recent.getAttribute('data-cgpt-project-label'), '工作项目');
h.renderProjectLabel(projectChat, projectChatId);
assert.equal(projectChat.hasAttribute('data-cgpt-project-label'), false);

const nested = new FakeAnchor('/c/22222222-2222-4222-8222-222222222222');
const nestedMarker = new FakeElement();
nestedMarker.setAttribute('data-project-id', 'g-p-project001');
nested.append(nestedMarker);
assert.equal(h.projectIdForChatItem(nested, '22222222-2222-4222-8222-222222222222'),
  'g-p-project001');

const outside = new FakeAnchor('/c/33333333-3333-4333-8333-333333333333');
recentSection.append(outside);
h.renderProjectLabel(outside, '33333333-3333-4333-8333-333333333333');
assert.equal(outside.hasAttribute('data-cgpt-project-label'), false);

pathname = '/g/g-p-project002/c/44444444-4444-4444-8444-444444444444';
h.rememberCurrentProjectChat();
assert.equal(state.projectIndex.chats['44444444-4444-4444-8444-444444444444'].pid,
  'g-p-project002');
assert.equal(h.loadProjectIndex().chats['44444444-4444-4444-8444-444444444444'].pid,
  'g-p-project002');

const unlabeledProjectItem = new FakeAnchor('/c/' + chatId);
projectSection.append(unlabeledProjectItem);
h.renderProjectLabel(unlabeledProjectItem, chatId);
assert.equal(unlabeledProjectItem.hasAttribute('data-cgpt-project-label'), false,
  'generic /c/ conversation inside project section remains plain');

const headingOnlyRecent = new FakeElement().append(new FakeElement('', 'Recents', '', 'H2'));
const headingRecentChat = new FakeAnchor('/c/' + chatId);
headingOnlyRecent.append(headingRecentChat);
sidebar.append(headingOnlyRecent);
h.renderProjectLabel(headingRecentChat, chatId);
assert.equal(headingRecentChat.getAttribute('data-cgpt-project-label'), '工作项目',
  'recent section can be identified by heading without data-testid');

console.log('[project labels] Recents-only, project-folder, cache and route tests passed');
