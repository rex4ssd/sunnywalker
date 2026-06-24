import SwiftUI

/// 可愛溫暖的首頁：一格一格大圓角卡片，點一個就全螢幕開那個網址。
struct HomeView: View {
    @EnvironmentObject var store: SiteStore
    @State private var selected: Site?

    // 自適應格狀排版：iPhone 約 2 欄、iPad 多欄
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 20)]

    var body: some View {
        ZStack {
            // 柔和漸層背景
            LinearGradient(
                colors: [Color(hex: "#FFF4E6"), Color(hex: "#FFE8CC")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header

                    if store.sites.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(store.sites) { site in
                                SiteCard(site: site) { selected = site }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 24)
            }
        }
        // 全螢幕開網頁
        .fullScreenCover(item: $selected) { site in
            if let url = URL(string: site.url) {
                WebPage(site: site, url: url) { selected = nil }
                    .environmentObject(store)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("🌈")
                .font(.system(size: 56))
            Text("小小瀏覽器")
                .font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundColor(Color(hex: "#7C5E3C"))
            Text("點一個圖案開始學習吧！")
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundColor(Color(hex: "#A78A5E"))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🐣").font(.system(size: 48))
            Text("還沒有設定任何網頁")
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundColor(Color(hex: "#7C5E3C"))
            Text("請家長在「檔案 app → 小小瀏覽器 → sites.json」中加入網址")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(Color(hex: "#A78A5E"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 40)
    }
}

/// 單張可愛卡片
struct SiteCard: View {
    let site: Site
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                iconView
                    .frame(height: 64)
                Text(site.name)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundColor(Color(hex: "#5A4427"))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(Color(hex: site.color))
            .cornerRadius(28)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// icon 可以是 emoji，也可以是 SF Symbol 名稱
    @ViewBuilder private var iconView: some View {
        if let icon = site.icon, !icon.isEmpty {
            if icon.unicodeScalars.allSatisfy({ $0.properties.isEmoji }) {
                Text(icon).font(.system(size: 52))
            } else {
                Image(systemName: icon)
                    .font(.system(size: 46))
                    .foregroundColor(Color(hex: "#7C5E3C"))
            }
        } else {
            Text("⭐️").font(.system(size: 52))
        }
    }
}

/// 全螢幕網頁 + 大大的返回鈕
struct WebPage: View {
    @EnvironmentObject var store: SiteStore
    let site: Site
    let url: URL
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            WebView(url: url, store: store)
                .ignoresSafeArea(edges: .bottom)

            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "house.fill")
                    Text("回家").font(.system(.body, design: .rounded).weight(.bold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(hex: "#FFD8A8"))
                .foregroundColor(Color(hex: "#5A4427"))
                .cornerRadius(24)
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
            .padding(.leading, 16)
            .padding(.top, 8)
        }
    }
}
