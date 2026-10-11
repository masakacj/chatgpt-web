import fs from 'node:fs';
import assert from 'node:assert/strict';
const p='App/NativeConversationScreen.swift';let s=fs.readFileSync(p,'utf8');
const one=(a,b)=>{assert.equal(s.split(a).length-1,1,'composer refinement '+a.slice(0,80));s=s.replace(a,b)};
if(!s.includes('showInputOptions')){
 one('    @State private var showLibrary = false','    @State private var showLibrary = false\n    @State private var showInputOptions = false');
 one('            .sheet(item: $interaction) { selected in interactionConfirmation(selected) }',`            .sheet(item: $interaction) { selected in interactionConfirmation(selected) }
            .confirmationDialog("输入选项", isPresented: $showInputOptions, titleVisibility: .visible) {
                Button("同步草稿") { Task { await model.syncDraft() } }.disabled(!model.canWrite)
                Button("采用 PC 草稿") { confirmDraft = true }.disabled(model.working || model.snapshot == nil)
                Button("取消", role: .cancel) {}
            }`);
 one(`                    Menu {
                        Button("同步草稿") { Task { await model.syncDraft() } }.disabled(!model.canWrite)
                        Button("采用 PC 草稿") { confirmDraft = true }.disabled(model.working || model.snapshot == nil)
                    } label: { Image(systemName: "plus").font(.system(size: 22)).frame(width: 36, height: 36) }.accessibilityLabel("输入选项")`,
 `                    Button { editing = false; showInputOptions = true } label: {
                        Image(systemName: "plus").font(.system(size: 22)).frame(width: 36, height: 36)
                    }.accessibilityLabel("输入选项")`);
 one('    private var composer: some View {',`    private var composerHeight: CGFloat {
        let width = max(180, UIScreen.main.bounds.width - 72)
        let font = UIFont.preferredFont(forTextStyle: .body)
        let bounds = (model.draft.text as NSString).boundingRect(with: CGSize(width: width, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        return min(110, max(40, ceil(bounds.height) + 16))
    }
    private var composer: some View {`);
 one('.frame(minHeight: 40, maxHeight: 105).padding(.horizontal, 8).padding(.top, 5)','.frame(height: composerHeight).padding(.horizontal, 8).padding(.top, 5)');
 fs.writeFileSync(p,s);
}
console.log('Native input options are explicit UIKit-backed actions; empty composer stays compact');
