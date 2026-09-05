// SunnyWalker — SheetPresenceTracker.swift  |  「上面有 sheet 蓋著」的計數器
//
// 為什麼：首頁底下有三層常駐動畫（CloudBackground 30fps Canvas、MascotView 24fps、紙紋）。
// 家長開「新增鬧鐘 → 自定鈴聲 → 新增錄音」時，這三層還在被 sheet 蓋住的地方全速重繪，
// 跟 sheet 裡的 List 捲動、錄音頁的 Mascot 搶 GPU／主執行緒——這是「選音檔／錄音頁滑動有點頓」
// 的主要來源之一。SwiftUI 的 sheet 不會把底下的 view 標成 inactive，得自己算。
//
// 用法：在每個從首頁彈出的 sheet 內容根 view 加 `.countsAsPresentedSheet()`；
// HomeView 讀 `SheetPresenceTracker.shared.isCovered` 決定要不要暫停動畫。
// 計數（不是布林）：sheet 疊 sheet（編輯器 → 鈴聲庫 → 錄音）時，內層關掉外層還在。

import SwiftUI

@MainActor
final class SheetPresenceTracker: ObservableObject {
    static let shared = SheetPresenceTracker()
    private init() {}

    @Published private(set) var count = 0

    var isCovered: Bool { count > 0 }

    fileprivate func enter() { count += 1 }
    fileprivate func leave() { count = max(0, count - 1) }
}

private struct SheetPresenceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { SheetPresenceTracker.shared.enter() }
            .onDisappear { SheetPresenceTracker.shared.leave() }
    }
}

extension View {
    /// 標記「這個 view 是蓋在首頁上的 sheet 內容」——出現時首頁動畫暫停、消失時恢復。
    func countsAsPresentedSheet() -> some View {
        modifier(SheetPresenceModifier())
    }
}
