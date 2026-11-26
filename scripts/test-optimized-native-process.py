"""Offline WebKit/Chromium regression using the actual optimized document-start script."""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'OptimizedResources/Observation/native-process.js'
FRAME = 'https://mcp-endpoint-fixture.web-sandbox.oaiusercontent.com/fixture'
PAGE = """<!doctype html><html><head><style>.pointer-events-none{pointer-events:none}</style></head>
<body><nav><button id="sidebar">Project</button></nav><main>
<article data-turn-key="native-tail">
  <div data-conversation-role="user"><p id="user" data-testid="mcp-tool-output">User message</p></div>
  <div data-response-body><div class="group/activity-header"><span role="status">Apply patch</span><button id="header">Details</button></div>
    <div id="passive" data-mcp-app-portal-target><div></div><div data-mcp-app-frame><iframe id="patch" class="pointer-events-none" title="Apply patch" src="FRAME"></iframe></div></div>
  </div>
  <div data-response-body><div class="group/activity-header">Read file</div>
    <div id="active" data-mcp-app-portal-target><div data-mcp-app-frame><iframe title="Read file" src="FRAME"></iframe></div></div>
  </div>
  <div data-response-body><div class="group/activity-header">Unknown tool</div>
    <div id="unknown" data-mcp-app-portal-target><div data-mcp-app-frame><iframe class="pointer-events-none" title="Other app" src="FRAME"></iframe></div></div>
  </div>
  <div data-response-body data-message-channel="final"><div class="group/activity-header">Final answer</div>
    <div id="final-frame" data-mcp-app-portal-target><div data-mcp-app-frame><iframe class="pointer-events-none" title="Read file" src="FRAME"></iframe></div></div>
  </div>
  <div data-testid="tool-call"><div role="status">Command finished</div><pre id="stdout" data-testid="tool-output">stdout</pre></div>
  <div id="output" data-testid="mcp-tool-output">tool output</div>
  <div id="error" data-testid="mcp-tool-output"><div role="alert">Error details</div></div>
  <div id="approval" data-testid="mcp-tool-output"><button>Confirm</button></div>
  <div id="nested-interaction" data-testid="mcp-tool-output"><div data-tool-interaction>Tool surface</div></div>
  <div id="nested-modal" data-testid="mcp-tool-output"><div aria-modal="true">Modal</div></div>
  <div id="nested-user" data-testid="mcp-tool-output"><div data-conversation-role="user">User content</div></div>
  <div id="nested-status" data-testid="mcp-tool-output"><div data-testid="tool-progress">Progress</div></div>
  <div id="self-control" data-testid="mcp-tool-output" role="checkbox" aria-checked="false">Native checkbox</div>
  <div id="self-expanded" data-testid="mcp-tool-output" aria-expanded="false">Native disclosure</div>
  <div role="combobox"><div id="ancestor-control" data-testid="mcp-tool-output">Native control content</div></div>
  <div data-testid="final-answer" class="MarkdownRoot"><p id="final" data-testid="mcp-tool-output">Final markdown</p><a id="download" href="#download">Download</a></div>
</article><form><textarea id="prompt-textarea">draft</textarea><button id="send">Send</button></form>
</main></body></html>""".replace('FRAME', FRAME)

def check(engine):
    browser = engine.launch(headless=True)
    try:
        context = browser.new_context()
        def route(r):
            if r.request.url == 'https://chatgpt.com/c/native-fixture-12345678':
                r.fulfill(status=200, content_type='text/html', body=PAGE)
            elif r.request.url == FRAME:
                r.fulfill(status=200, content_type='text/html',
                          body='<p>Frame document</p><script>window.fixtureBoot=Math.random()</script>')
            else:
                r.abort()
        context.route('**/*', route)
        context.add_init_script(path=SOURCE)
        page = context.new_page()
        page.goto('https://chatgpt.com/c/native-fixture-12345678', wait_until='load')
        page.wait_for_function("!!document.getElementById('optimized-native-process-style')")
        display = lambda id: page.locator('#'+id).evaluate('(n)=>getComputedStyle(n).display')
        for id in ['patch','stdout','output']:
            assert display(id)=='none', (engine.name,id,display(id))
        for id in ['passive','active','unknown','final-frame','user','final','download','error','approval','header','sidebar','send',
                   'nested-interaction','nested-modal','nested-user','nested-status','self-control','self-expanded','ancestor-control']:
            assert display(id)!='none', (engine.name,id)
        frame = page.locator('#patch').element_handle().content_frame()
        frame.wait_for_function('window.fixtureBoot !== undefined')
        boot = frame.evaluate('window.fixtureBoot')
        page.locator('#header').focus()
        assert display('patch')!='none'
        page.locator('#header').evaluate('(n)=>n.blur()')
        assert display('patch')=='none'
        page.locator('#patch').evaluate("(n)=>n.classList.remove('pointer-events-none')")
        assert display('patch')!='none'
        page.locator('#patch').evaluate("(n)=>n.classList.add('pointer-events-none')")
        assert display('patch')=='none'
        page.locator('#output').evaluate("(n)=>n.append(document.createElement('button'))")
        assert display('output')!='none'
        page.locator('#output button').evaluate('(n)=>n.remove()')
        assert display('output')=='none'
        for name,value in [('role','checkbox'),('role','combobox'),('aria-expanded','false'),
                           ('data-tool-interaction',''),('aria-modal','true')]:
            page.locator('#output').evaluate('(n,p)=>n.setAttribute(p[0],p[1])',[name,value])
            assert display('output')!='none', (engine.name,'self',name,value)
            page.locator('#output').evaluate('(n,name)=>n.removeAttribute(name)',name)
            assert display('output')=='none'
        for name,value in [('data-tool-interaction',''),('aria-modal','true'),
                           ('data-message-author-role','user'),('data-conversation-role','user'),
                           ('data-testid','user-message'),('data-message-channel','final'),
                           ('data-testid','tool-progress')]:
            page.locator('#output').evaluate("""(n,p)=>{const el=document.createElement('div');
                el.setAttribute(p[0],p[1]);el.textContent='Protected native content';n.append(el)}""",[name,value])
            assert display('output')!='none', (engine.name,name,value)
            page.locator('#output').evaluate('(n)=>n.lastElementChild.remove()')
            assert display('output')=='none'
        # Ordinary Markdown within a positively identified tool body stays eligible.
        page.locator('#output').evaluate("(n)=>{const el=document.createElement('div');el.className='MarkdownRoot';el.textContent='log';n.append(el)}")
        assert display('output')=='none'
        page.locator('#output').evaluate('(n)=>n.lastElementChild.remove()')
        page.locator('#output').evaluate("(n)=>n.append(document.createElement('div'))")
        assert display('output')=='none'
        page.locator('#output > div').evaluate("(n)=>{const el=document.createElement('div');el.setAttribute('data-tool-interaction','');n.append(el)}")
        assert display('output')!='none', (engine.name,'nested late interaction')
        page.locator('#output > div').evaluate('(n)=>n.remove()')
        assert display('output')=='none'
        page.locator('#passive [data-mcp-app-frame]').evaluate("""(n)=>{
            const el=document.createElement('div');el.setAttribute('data-tool-interaction','');n.append(el)
        }""")
        assert display('passive')!='none'
        assert display('patch')!='none'
        assert page.locator('#passive [data-tool-interaction]').evaluate("(n)=>getComputedStyle(n).display")!='none'
        page.locator('#passive [data-mcp-app-frame]').evaluate('(n)=>n.lastElementChild.remove()')
        assert display('patch')=='none'
        result = page.evaluate("""()=>new Promise(resolve=>{
            const row=document.createElement('div');row.dataset.testid='mcp-tool-output';
            row.append(document.createTextNode('X'.repeat(6000000)));
            const frag=document.createDocumentFragment();
            for(let i=0;i<12000;i++)frag.append(document.createElement('span'));
            row.append(frag);document.querySelector('article').append(row);
            requestAnimationFrame(()=>resolve({display:getComputedStyle(row).display,
                chars:row.firstChild.length,children:row.childElementCount}));
        })""")
        assert result == {'display':'none','chars':6000000,'children':12000}, result
        assert frame.evaluate('window.fixtureBoot') == boot
        assert page.locator('#prompt-textarea').input_value() == 'draft'
        page.evaluate("document.getElementById('optimized-native-process-style').remove()")
        assert display('patch')!='none' and display('output')!='none'
        print(json.dumps({'engine':engine.name,'pass':True,'toolDataIntact':result,
              'frameDocumentIntact':True,'nativeControlsPreserved':True,'restore':True}))
    finally:
        browser.close()

if __name__ == '__main__':
    with sync_playwright() as p:
        for engine in (p.webkit, p.chromium):
            check(engine)
