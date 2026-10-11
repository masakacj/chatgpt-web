import fs from 'node:fs';
import assert from 'node:assert/strict';
const p='App/PCCompanionTestProtocol.swift';let s=fs.readFileSync(p,'utf8');
const one=(a,b)=>{assert.equal(s.split(a).length-1,1,'fixture patch '+a.slice(0,90));s=s.replace(a,b)};
if(!s.includes('private static var projectExpanded')){
 one('    private static let conversation = "11111111-1111-4111-8111-111111111111"',`    private static let firstConversation = "11111111-1111-4111-8111-111111111111"
    private static var conversation = firstConversation
    private static var projectExpanded = false`);
 one('        expired = false; receiptID = ""; sentText = ""; version = 1','        expired = false; receiptID = ""; sentText = ""; version = 1\n        conversation = firstConversation; projectExpanded = false');
 one('let answer = expired ? "会话重建成功" : readFailed ? "重连后答案" : "联调初始答案"','let answer = conversation != firstConversation ? "目录切换成功" : expired ? "会话重建成功" : readFailed ? "重连后答案" : "联调初始答案"');
 one('    private static func envelope() -> [String: Any] {',`    private static func library() -> [String: Any] {
        let project = "g-p-aaaaaaaaaaaaaaaa"
        var chats: [[String: Any]] = [["id":firstConversation,"title":"联调测试会话","current":conversation == firstConversation,"status":"completed","readState":"read","tabId":1]]
        if projectExpanded { chats.append(["id":"22222222-2222-4222-8222-222222222222","title":"第二个项目对话","projectId":project,"current":false,"status":"completed","readState":"unread"]) }
        return ["ok":true,"sourceTabId":1,"projects":[["id":project,"title":"Project Alpha","collapsed":!projectExpanded,"hasMore":false]],
            "chats":chats,"tabs":[["tabId":1,"title":"联调测试会话","conversationId":conversation,"active":true]],"partial":true,"sidebarAvailable":true]
    }
    private static func envelope() -> [String: Any] {`);
 one('        } else if path == "/v1/tabs" {',`        } else if path == "/v1/library" { json = Self.library()
        } else if path == "/v1/library/actions" && method == "POST" {
            if payload["action"] as? String == "project" { Self.projectExpanded = true; json = Self.library() }
            else {
                Self.conversation = payload["conversationId"] as? String ?? Self.firstConversation; Self.version += 1
                json = ["ok":true,"tab":["tabId":1,"title":"第二个项目对话","conversationId":Self.conversation,"active":true]]
            }
        } else if path == "/v1/tabs" {`);
 one('            } else if action == "send" {\n                Self.sends += 1;',`            } else if action == "send" && args.contains("--pc-fixture-not-sent") {
                Self.sends += 1; Self.receiptID = id
                json = ["ok":false,"commandId":id,"state":"failed","result":["status":"not_sent","error":"send_unavailable","documentId":"fixture-document"]]
            } else if action == "send" {
                Self.sends += 1;`);
 fs.writeFileSync(p,s);
}
console.log('Isolated native sidebar and unsent fixture prepared; no live ChatGPT calls');
