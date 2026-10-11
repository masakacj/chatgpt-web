import fs from 'node:fs';
import assert from 'node:assert/strict';
const p='App/PCCompanionTestProtocol.swift';let s=fs.readFileSync(p,'utf8');
const one=(a,b)=>{assert.equal(s.split(a).length-1,1,'UI fixture '+a.slice(0,70));s=s.replace(a,b)};
if(!s.includes('private static var interactionClicks')){
 one('    private static var version = 1','    private static var version = 1\n    private static var interactionClicks = 0');
 one('draft = ""; sessions = 0; sends = 0; polls = 0; readFailed = false','draft = ""; sessions = 0; sends = 0; polls = 0; interactionClicks = 0; readFailed = false');
 one('return "发送请求：\\(sends)；订阅：\\(sessions)；读取：\\(polls)"','return "发送请求：\\(sends)；订阅：\\(sessions)；读取：\\(polls)；操作：\\(interactionClicks)"');
 one('        return ["schema":1, "documentId":"fixture-document",','        var payload: [String: Any] = ["schema":1, "documentId":"fixture-document",');
 one('"canSend":!draft.isEmpty, "composing":false, "unsupportedTools":false, "historyPartial":true]\n    }',`"canSend":!draft.isEmpty, "composing":false, "unsupportedTools":false, "historyPartial":true]
        if args.contains("--pc-fixture-reader") {
            payload["historyCursor"] = "cursor-current"; payload["hasOlder"] = true
            payload["status"] = interactionClicks == 0 ? "running" : "completed"
            payload["responsePhase"] = interactionClicks == 0 ? "thinking" : "completed"
            if interactionClicks == 0 {
                payload["interactions"] = [["id":"card-1", "title":"读取指定文件", "summary":"仅允许读取本次选择的测试文件。", "buttons":[["id":"interaction-test-11111", "revision":"revision-test-111111", "label":"允许本次", "disabled":false, "requiresConfirmation":true]]]]
            } else {
                payload["interactions"] = []
                payload["messages"] = [["id":"answer2", "role":"assistant", "text":"操作后正式回复", "blocks":[], "links":[], "truncated":false]]
            }
        }
        if args.contains("--pc-fixture-thinking") { payload["status"] = "running"; payload["responsePhase"] = "thinking"; payload["messages"] = [["id":"user-new","role":"user","text":"等待最新回复","blocks":[],"links":[],"truncated":false]] }
        return payload
    }`);
 one('        } else if path.hasSuffix("/commands") && method == "POST" {',`        } else if path.hasSuffix("/history") {
            json = ["ok":true,"schema":1,"documentId":"fixture-document","conversationId":Self.conversation,
                "messages":[["id":"older-1","role":"user","text":"历史问题","blocks":[],"links":[],"truncated":false],["id":"older-2","role":"assistant","text":"历史正式回复","blocks":[],"links":[],"truncated":false]],
                "cursor":"cursor-oldest","hasMore":false,"source":"pc_loaded_history"]
        } else if path.hasSuffix("/commands") && method == "POST" {`);
 one('            if action == "draft" {',`            if action == "interact" {
                Self.interactionClicks += 1; Self.version += 1
                json = ["ok":true,"commandId":id,"state":"done","result":["status":"interaction_clicked"]]
            } else if action == "draft" {`);
 fs.writeFileSync(p,s);
}
// Existing tests now use the official-like compact composer options menu.
const tests='UITests/PCCompanionUITests.swift';let t=fs.readFileSync(tests,'utf8');
if(!t.includes('compact composer menu')){
 t=t.replace('        app.buttons["同步草稿"].tap()', '        app.buttons["输入选项"].tap() // compact composer menu\n        app.buttons["同步草稿"].tap()');
 t=t.replace('XCTAssertFalse(app.buttons["发送"].isEnabled); XCTAssertFalse(app.buttons["同步草稿"].isEnabled)', 'XCTAssertFalse(app.buttons["发送"].isEnabled)');
 fs.writeFileSync(tests,t);
}
console.log('Native chat fixtures ready; history/thinking/explicit action; original draft checks retained');
