import Foundation

let suite = "NativeParityTest-" + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var clock = 1_791_600_000_000.0
let a = "11111111-1111-4111-8111-111111111111"
let b = "22222222-2222-4222-8222-222222222222"
let store = ConversationResilienceStore(defaults: defaults, now: {clock})
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(),label); checks += 1
}
expect(ConversationResilienceStore.conversationID(URL(string:"https://chatgpt.com/g/project/c/"+a)) == a,"project URL")
expect(ConversationResilienceStore.conversationID(URL(string:"https://other.invalid/c/"+a)) == nil,"origin scope")
let active: [String:Any] = ["id":a,"nativeState":"running","currentTurn":true,"turnKey":"first"]
expect(store.observe(active,currentID:a)?.status == "running","observed running")
let reopened = ConversationResilienceStore(defaults:defaults,now:{clock})
expect(reopened.records[a]?.status == "running","native restart keeps state")
clock += 100_000
expect(reopened.records[a]?.display(at:clock) == "uncertain","stale evidence")
expect(reopened.observe(["id":a,"loadError":true],currentID:a)?.status == "running","error preserves record")
let completed: [String:Any] = ["id":a,"nativeState":"complete","currentTurn":true,"answerReady":true,"turnKey":"final"]
expect(reopened.observe(completed,currentID:a)?.status == "completed","verified completion")
expect(reopened.observe(completed,currentID:b) == nil,"cross-route rejected")
let again = ConversationResilienceStore(defaults:defaults,now:{clock})
expect(again.records[a]?.status == "completed","completion survives restart")
let sent: [String:Any] = ["id":a,"kind":"submit","turnKey":"final"]
_ = again.observe(sent,currentID:a)
clock += 1000
expect(again.observe(completed,currentID:a)?.status == "running","old answer cannot finish new send")
var fresh = completed;fresh["turnKey"]="new-final"
expect(again.observe(fresh,currentID:a)?.status == "completed","new final turn verified")
var safe: [String:Any] = ["id":a,"visible":true,"loadError":true,"canRetry":true,
    "hasDraft":false,"running":false,"waiting":false,"hasAnswer":false,"recoveryCanceled":false]
let failure = ConversationResilienceStore.Failure(id:a,category:"transient_http",at:clock,document:"doc")
for key in ["hasDraft","running","waiting","hasAnswer","recoveryCanceled"] {
    var unsafe=safe;unsafe[key]=true
    expect(again.reserveRetry(unsafe,failure:failure,currentID:a,document:"doc",appActive:true) == nil,key)
}
expect(again.reserveRetry(safe,failure:nil,currentID:a,document:"doc",appActive:true) == nil,"no network evidence")
expect(again.reserveRetry(safe,failure:failure,currentID:a,document:"other",appActive:true) == nil,"old document")
expect(again.reserveRetry(safe,failure:failure,currentID:a,document:"doc",appActive:false) == nil,"background")
expect(again.reserveRetry(safe,failure:failure,currentID:a,document:"doc",appActive:true) == 1.6,"first attempt")
let retryReopened = ConversationResilienceStore(defaults:defaults,now:{clock})
expect(retryReopened.reserveRetry(safe,failure:failure,currentID:a,document:"doc",appActive:true) == 4.2,"second across restart")
expect(retryReopened.reserveRetry(safe,failure:failure,currentID:a,document:"doc",appActive:true) == nil,"limit across reload")
for code in [401,403,429,404,410] {
    let f = ConversationResilienceStore.Failure(id:a,category:ConversationResilienceStore.failureCategory(code:code)!,at:clock,document:"doc")
    expect(retryReopened.reserveRetry(safe,failure:f,currentID:a,document:"doc",appActive:true) == nil,"auth/rate/missing")
}
expect(ConversationResilienceStore.failureCategory(code:0,networkError:true) == "unclassified_network","network error is not blindly transient")
expect(retryReopened.importLegacy([["id":b,"record":["status":"completed","at":clock]]]) == 1,"legacy migration")
expect(ConversationResilienceStore(defaults:defaults,now:{clock}).records[b]?.status == "completed","migration stored natively")
print("Native parity policy PASS: \(checks) assertions; native UserDefaults reload verified")
