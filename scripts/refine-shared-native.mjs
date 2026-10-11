// Runs only in the isolated shared-tab CI branch. Keeps prepared Swift source
// in GitHub; no iOS checkout or source dump on MCP machines.
import fs from 'node:fs';
const edits = [
  ['App/SharedTabModel.swift',
   'guard envelope.revision >= revision else { return }; revision = envelope.revision',
   `guard envelope.revision >= revision else { return }
        if envelope.revision == revision && envelope.routeChanged != true && envelope.tabClosed != true { return }
        revision = envelope.revision`],
  ['UITests/SharedTabUITests.swift',
   'app.scrollViews["shared.transcript"].coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.72)).tap()',
   `// The accessibility frame can extend below keyboard/composer insets.
        // Tap actual visible blank transcript, not a point covered by the keyboard.
        let transcript = app.scrollViews["shared.transcript"].frame
        let keyboard = app.keyboards.firstMatch.frame
        let editor = composer(app).frame
        let answer = app.staticTexts["原生测试答案 A"].frame
        let copy = app.buttons["复制消息"].firstMatch.frame
        let top = max(transcript.minY + 12, max(answer.maxY, copy.maxY) + 16)
        let bottom = min(transcript.maxY, min(keyboard.minY, editor.minY)) - 16
        XCTAssertGreaterThan(bottom, top, "There must be visible blank transcript above the composer")
        let point = CGPoint(x: transcript.midX, y: (top + bottom) / 2)
        XCTAssertFalse(keyboard.contains(point))
        XCTAssertFalse(editor.contains(point))
        print("Keyboard acceptance geometry: transcript=\\(transcript), keyboard=\\(keyboard), editor=\\(editor), tap=\\(point)")
        let before = XCTAttachment(screenshot: app.screenshot()); before.name = "shared-before-blank-tap"; before.lifetime = .keepAlways; add(before)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY)).tap()`]
];
for (const [file, before, after] of edits) {
  const source = fs.readFileSync(file, 'utf8');
  if (source.includes(after)) continue;
  if (source.split(before).length !== 2) throw Error('unexpected_source:' + file);
  fs.writeFileSync(file, source.replace(before, after));
  console.log('Prepared ' + file);
}
