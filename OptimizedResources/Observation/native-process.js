// WKWebView port of PC Optimizer v0.1.14. Only native CSS rendering relief.
(() => {
  'use strict';
  if (window !== window.top || location.origin !== 'https://chatgpt.com') return;
  const STYLE = 'optimized-native-process-style';
  const scope = 'main :is([data-turn-key],[data-testid^="conversation-turn-"])';
  // Reuse semantic protection for the candidate, ancestors and descendants.
  // Markdown ancestry is protected separately; tool-output Markdown children
  // need not veto relief. Ancestor tabindex may belong to the entire turn.
  const semantic = 'button,a[href],input,textarea,select,form,summary,details,[contenteditable]:not([contenteditable="false"]),[role="button"],[role="dialog"],[aria-modal="true"],[role="alert"],[role="status"],[role="link"],[role="checkbox"],[role="radio"],[role="switch"],[role="textbox"],[role="combobox"],[role="menuitem"],[role="menuitemcheckbox"],[role="menuitemradio"],[role="tab"],[role="slider"],[role="spinbutton"],[role="option"],[role="treeitem"],[role="searchbox"],[data-tool-interaction],[data-message-author-role="user"],[data-conversation-role="user"],[data-testid*="user-message" i],[data-testid*="error" i],[data-testid*="approval" i],[data-testid*="permission" i],[data-testid*="confirm" i],[data-testid*="authorize" i],[data-testid*="interactive" i],[aria-expanded],[data-message-channel="final"],[data-channel="final"],[data-testid*="final-answer" i],header,[class~="group/activity-header"],[data-testid*="status" i],[data-testid*="progress" i]';
  const protectedNode = ':is(' + semantic + ',.markdown,[class*="MarkdownRoot"])';
  const outsideProtected = ':not(' + protectedNode + ',' + protectedNode + ' *)';
  const controls = semantic + ',[tabindex],video,audio,canvas,svg';
  const explicit = ':is([data-testid="mcp-output"],[data-testid="mcp-result"],[data-testid="mcp-tool-output"],[data-testid="mcp-tool-result"])';
  const owned = ':is([data-testid="tool-call"],[data-testid="mcp-call"]) :is([data-testid="tool-output"],[data-testid="tool-result"],[data-testid="tool-response"],[data-testid="tool-input"],[data-testid="tool-arguments"])';
  // A verified tool body, not the native activity header or a whole turn.
  const textBody = scope + ' :is(' + explicit + ',' + owned + ')' + outsideProtected +
    ':not(:is(' + controls + ',iframe)):not(:focus-within):not(:has(' + controls + ',iframe))';
  // Actual Nov 26 native MCP presentation: response-body -> activity header
  // + portal target -> frame wrapper -> iframe. Require a known DevSpace
  // operation title AND the site's non-interactive frame class. Unknown and
  // interactive frames are left alone; the official header stays usable.
  const names = ['apply patch','apply_patch','exec command','exec_command','write stdin','write_stdin','read file','read_file','opened workspace','open workspace','open_workspace','edit file','edit_file','write file','write_file'];
  const title = ':is(' + names.flatMap(n=>['[title*="'+n+'" i]','[aria-label*="'+n+'" i]']).join(',') + ')';
  const passive = 'iframe.pointer-events-none' + title + ':not([tabindex]:not([tabindex="-1"]))';
  // WebKit can defer :has() invalidation inside display:none ancestors.
  // Keep the portal and wrapper visible; only the verified passive iframe
  // itself is eligible. A newly mounted sibling control remains accessible.
  const frame = scope + ' [data-response-body]' + outsideProtected + ':not(:focus-within)' +
    ':has(> [class~="group/activity-header"]) > [data-mcp-app-portal-target]' + outsideProtected +
    ':not(:has(> :not(div:empty,[data-mcp-app-frame])))' +
    ':not(:focus-within):not(:has(' + controls + ',iframe:not(' + passive + '))) > [data-mcp-app-frame]' + outsideProtected +
    ':not(:has(> :not(' + passive + '))) > ' + passive + outsideProtected + ':not(:focus-within)';
  // The browser handles DOM changes, including late controls and native
  // pointer-event state changes, without an extension MutationObserver.
  const css = textBody + '{display:none!important;}\n' + frame + '{display:none!important;}';
  function install() {
    if (!document.documentElement || document.getElementById(STYLE)) return;
    const style = document.createElement('style');
    style.id = STYLE;
    style.textContent = css;
    document.documentElement.appendChild(style);
  }
  // At document start, WebKit may not have constructed the document element.
  if (document.documentElement) install();
  else document.addEventListener('DOMContentLoaded', install, {once: true});
})();
