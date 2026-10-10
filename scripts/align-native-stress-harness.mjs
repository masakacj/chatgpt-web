import fs from 'node:fs';
import assert from 'node:assert/strict';
function one(s,a,b){assert.equal(s.split(a).length-1,1,'unique harness patch '+a.slice(0,90));return s.replace(a,b)}
let path='App/ChatGPTWebView.swift',s=fs.readFileSync(path,'utf8');
if(!s.includes('let nativeParity = values["nativeParity"]')){
 s=one(s,'                    baselineNodes:\n                      Number(baseline.nodes || 0),','                    nativeParity: window.__CHATGPT_NATIVE_PARITY__ === true,\n                    nativeReady: document.documentElement.getAttribute(\n                      "data-native-parity-ready"\n                    ) === "true",\n                    baselineNodes:\n                      Number(baseline.nodes || 0),');
 const a='                let pass =\n                    baselineActivity >= 109 &&\n                    baselineMcp >= 96 &&\n                    baselineThinking >= 3 &&\n                    activity == 10 &&\n                    mcp == 0 &&\n                    thinking == 0 &&\n                    sentinel &&\n                    !runtime.isEmpty &&\n                    pruned >= 99 &&\n                    reduction >= 0.40';
 const b='                let nativeParity = values["nativeParity"] as? Bool == true\n                let nativeReady = values["nativeReady"] as? Bool == true\n                let baselineValid = baselineActivity >= 109 && baselineMcp >= 96\n                    && baselineThinking >= 3 && sentinel && !runtime.isEmpty\n                // New native mode must preserve history and finish a real\n                // isolated-world -> Swift -> isolated-world handshake.\n                let pass = baselineValid && (nativeParity\n                    ? (nativeReady && activity == baselineActivity && mcp == baselineMcp\n                        && thinking == baselineThinking && pruned == 0)\n                    : (activity == 10 && mcp == 0 && thinking == 0\n                        && pruned >= 99 && reduction >= 0.40))';
 s=one(s,a,b);fs.writeFileSync(path,s);
}
path='Resources/NativeConversationClient.js';s=fs.readFileSync(path,'utf8');
if(!s.includes("setAttribute('data-native-parity-ready'")){
 s=one(s,'    ready=true;route(true);',"    ready=true;document.documentElement.setAttribute('data-native-parity-ready','true');route(true);");
 fs.writeFileSync(path,s);
}
console.log('Real WKWebView gate requires preserved MCP DOM and native handshake');
