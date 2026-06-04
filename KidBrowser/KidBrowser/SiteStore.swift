import Foundation
import SwiftUI

/// 一個按鈕 = 一個網址。家長在 sites.json 裡編輯。
struct Site: Identifiable, Codable, Equatable {
    var id: String { url }          // 用網址當唯一 id
    var name: String                // 按鈕文字
    var url: String                 // 點下去要連的網址
    var icon: String?               // emoji 或 SF Symbol 名稱（可省略）
    var color: String?              // 卡片顏色，hex 例如 "#FFD8A8"（可省略）
}

struct SiteConfig: Codable {
    var sites: [Site]
}

/// 負責讀取／提供白名單設定。
/// 首次啟動會把 app 內附的 sites.json 複製到 Documents，
/// 之後家長就能用「檔案 app」直接編輯那一份。
final class SiteStore: ObservableObject {
    @Published private(set) var sites: [Site] = []

    /// 所有被允許開啟的確切網址（normalize 後）——嚴格白名單的核心。
    private(set) var allowedURLs: Set<String> = []

    static let fileName = "sites.json"

    init() {
        ensureUserConfigExists()
        reload()
    }

    /// Documents 裡那份家長可編輯的設定檔位置。
    private var userConfigURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(Self.fileName)
    }

    /// 第一次啟動：把 bundle 內的預設 sites.json 複製到 Documents。
    private func ensureUserConfigExists() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: userConfigURL.path) else { return }
        guard let bundled = Bundle.main.url(forResource: "sites", withExtension: "json") else { return }
        try? fm.copyItem(at: bundled, to: userConfigURL)
    }

    /// 重新讀取設定（家長改完檔案後可呼叫）。
    func reload() {
        let data: Data
        if let d = try? Data(contentsOf: userConfigURL) {
            data = d
        } else if let bundled = Bundle.main.url(forResource: "sites", withExtension: "json"),
                  let d = try? Data(contentsOf: bundled) {
            data = d
        } else {
            sites = []; allowedURLs = []; return
        }

        guard let config = try? JSONDecoder().decode(SiteConfig.self, from: data) else {
            sites = []; allowedURLs = []; return
        }
        sites = config.sites
        allowedURLs = Set(config.sites.map { Self.normalize($0.url) })
    }

    /// 嚴格比對用的網址正規化：小寫、去掉結尾斜線、去掉 fragment。
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hashIdx = s.firstIndex(of: "#") { s = String(s[..<hashIdx]) }
        if s.hasSuffix("/") { s.removeLast() }
        return s.lowercased()
    }

    /// 主框架導航是否被允許（只放行 JSON 裡列出的確切網址）。
    func isAllowed(_ url: URL) -> Bool {
        allowedURLs.contains(Self.normalize(url.absoluteString))
    }
}

/// 把 "#FFD8A8" 之類的 hex 轉成 Color；失敗就回傳柔和米色。
extension Color {
    init(hex: String?) {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else {
            self = Color(red: 1.0, green: 0.93, blue: 0.84); return
        }
        h.removeFirst()
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
