// One-time source integration, executed only in the isolated GitHub work branch.
// No MCP/local copy of iOS source is needed. Fails if base source differs.
import fs from 'node:fs';
import assert from 'node:assert/strict';
function change(path,fn){const old=fs.readFileSync(path,'utf8');const next=fn(old);fs.writeFileSync(path,next)}
function one(s,a,b){assert.equal(s.split(a).length-1,1,'unique patch: '+a.slice(0,90));return s.replace(a,b)}
if(fs.readFileSync('App/ChatGPTWebView.swift','utf8').includes('let nativeResilience = ChatGPTConversationResilience()')){
  console.log('Native integration already present');process.exit(0);
}
change('App/ChatGPTWebView.swift',s=>{
 s=one(s,'        private let nativePerformance = ChatGPTNativePerformanceProbe()','        private let nativePerformance = ChatGPTNativePerformanceProbe()\n        let nativeResilience = ChatGPTConversationResilience()');
 s=one(s,'        webView.uiDelegate = context.coordinator','        webView.uiDelegate = context.coordinator\n        context.coordinator.nativeResilience.attach(to: webView)');
 s=one(s,'        let store = UnifiedScriptStore.shared\n\n        controller.addUserScript(','        let store = UnifiedScriptStore.shared\n        ChatGPTConversationResilience.installScripts(on: controller)\n\n        controller.addUserScript(');
 s=one(s,'        uiView.webView.configuration.userContentController\n            .removeScriptMessageHandler(','        coordinator.nativeResilience.detach()\n        uiView.webView.configuration.userContentController\n            .removeScriptMessageHandler(');
 // The existing updater replaces document-start scripts; re-add native assets
 // immediately after clearing, before the legacy menu resource is appended.
 const pattern=/([ \t]*)([A-Za-z]+)\.removeAllUserScripts\(\)/g;
 let n=0;
 s=s.replace(pattern,(all,indent,name)=>{n++;return all+'\n'+indent+'ChatGPTConversationResilience.installScripts(on: '+name+')'});
 assert.equal(n,1,'one future-navigation reset');
 return s;
});
change('App/ConversationResilienceBridge.swift',s=>{
 s=one(s,'("NativeConversationEvidence", WKUserScriptInjectionTime.atDocumentStart, WKContentWorld.page)','("NativeConversationBootstrap", WKUserScriptInjectionTime.atDocumentStart, WKContentWorld.page)');
 s=one(s,'        controller.add(proxy, contentWorld: .page, name: "nativeReadEvidence")\n','');
 // No iOS equivalent of Chrome webRequest is assumed. Unverified page messages
 // must never authorize an automatic retry. Keep policy tests, fail closed.
 const start=s.indexOf('    fileprivate func readEvidence('),end=s.indexOf('    fileprivate func handle(',start);
 assert.ok(start>0&&end>start);
 s=s.slice(0,start)+'    fileprivate func readEvidence(_ message: WKScriptMessage) { /* not installed */ }\n'+s.slice(end);
 const a='            let delay = store.reserveRetry(snapshot,failure:failure,currentID:current,document:doc,\n                appActive:UIApplication.shared.applicationState == .active)\n            reply(["ok":true,"retryAfter":delay ?? -1,"category":failure?.category ?? "no_read_failure"],nil)';
 const b='            _ = snapshot\n            // Unknown network evidence is NOT a license to replay requests.\n            reply(["ok":true,"retryAfter":-1,"category":"native_read_evidence_unavailable"],nil)';
 return one(s,a,b);
});
change('Resources/NativeConversationClient.js',s=>one(s,
 "    call('observe',{observation:{...snapshot(),kind:'submit'}}).then(r=>{if(r?.record?.status){records.set(current,r.record);paint(current)}});",
 "    const submittedID=current;\n    call('observe',{observation:{...snapshot(),kind:'submit'}}).then(r=>{if(r?.record?.status){records.set(submittedID,r.record);paint(submittedID)}});"));
change('safari/chatgpt-safari.user.js',s=>{
 s=one(s,'// @version      0.4.43','// @version      0.4.44');
 s=one(s,"  const VERSION = '0.4.43';","  const VERSION = '0.4.44';");
 s=one(s,'  const RESULT_ONLY_MODE =\n    EXTREME_NATIVE_MODE;',
 '  const NATIVE_PARITY = IS_NATIVE_IOS && window.__CHATGPT_NATIVE_PARITY__ === true;\n  const RESULT_ONLY_MODE =\n    EXTREME_NATIVE_MODE && !NATIVE_PARITY;');
 s=one(s,'    setupObservers();\n    invalidateTurnCache();',
 '    if (NATIVE_PARITY) {\n      // Native state/observers own this path. Keep menu/hot update/telemetry,\n      // but do not re-enable historical pruning or duplicate state watchers.\n      scheduleControlRecovery(0);\n      if (state.settings.telemetryEnabled) startTelemetryRuntime();\n      return;\n    }\n\n    setupObservers();\n    invalidateTurnCache();');
 for(const [name,result] of [['bindScopedObservers','return;'],['setupConversationStateSync','return;'],['evaluateNativeConversationState','return;'],['scheduleInitialBottomScroll','return false;'],['registerConversationLinks','return {ids:new Set(),indexChanged:false};']]){
   const re=new RegExp('(  function '+name+'\\([^)]*\\) \\{)');
   assert.ok(re.test(s),name);s=s.replace(re,'$1\n    if (NATIVE_PARITY) '+result);
 }
 return s;
});
change('package.json',s=>one(s,'"version": "0.4.43"','"version": "0.4.44"'));
change('project.yml',s=>{assert.equal(s.split('MARKETING_VERSION: 0.4.43').length-1,2);return s.replaceAll('MARKETING_VERSION: 0.4.43','MARKETING_VERSION: 0.4.44')});
console.log('Integrated native parity v0.4.44; PC extension/retired scripts untouched');
