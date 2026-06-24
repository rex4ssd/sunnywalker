// SunnyWalker — ProUpgradeView.swift  |  Pro IAP purchase sheet
//
// Presented from the last Settings section (always behind the parental gate, per Kids Category
// Guideline 1.3). Honest, calm upsell — NO countdowns, fake discounts, rating prompts, or external
// links (Made for Kids forbids them). Buy / Restore / pending (Ask-to-Buy) / purchased states.
// All numbers come from `FeatureLimits` constants; the price is always `product.displayPrice`
// (Apple-localized per storefront) and is hidden when the product hasn't loaded (offline).

import SwiftUI
import StoreKit

struct ProUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoreService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    WatercolorCard {
                        VStack(alignment: .leading, spacing: 14) {
                            benefit(icon: "alarm.fill",
                                    text: L("pro_benefit_alarms %lld", FeatureLimits.freeMaxAlarms))
                            benefit(icon: "music.note.list",
                                    text: L("pro_benefit_clips %lld", FeatureLimits.freeMaxVoiceClips))
                            benefit(icon: "waveform",
                                    text: L("pro_benefit_clip_len %lld %lld",
                                            Int(FeatureLimits.freeMaxVoiceClipSeconds),
                                            Int(FeatureLimits.proMaxVoiceClipSeconds)))
                        }
                        .padding(20)
                    }

                    actionArea
                }
                .padding(20)
            }
            .navigationTitle(Text("pro_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .font(SunnyFonts.caption())
                }
            }
            .task {
                // Retry the product load if it failed earlier (e.g. the app launched offline).
                if store.product == nil { await store.loadProduct() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 52))
                .foregroundStyle(SunnyColors.wheatGold)
            Text("pro_headline")
                .font(SunnyFonts.title())
                .foregroundStyle(SunnyColors.nightIndigo)
                .multilineTextAlignment(.center)
            Text("pro_subtitle")
                .font(SunnyFonts.caption())
                .foregroundStyle(SunnyColors.sunnyGray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func benefit(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(SunnyColors.leafFresh)
                .frame(width: 26)
            Text(verbatim: text)
                .font(SunnyFonts.caption())   // match Settings list rows (16pt); body(22) looked oversized
                .foregroundStyle(SunnyColors.nightIndigo)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Action area (state machine)

    @ViewBuilder
    private var actionArea: some View {
        if store.isPro {
            // Already unlocked (purchased, restored, Family Sharing, or grandfathered).
            VStack(spacing: 8) {
                Label("pro_unlocked_thanks", systemImage: "checkmark.seal.fill")
                    .font(SunnyFonts.button())
                    .foregroundStyle(SunnyColors.forestDeep)
            }
            .padding(.vertical, 8)
        } else {
            switch store.purchaseState {
            case .pendingAskToBuy:
                Label("pro_pending_ask_to_buy", systemImage: "hourglass")
                    .font(SunnyFonts.body())
                    .foregroundStyle(SunnyColors.sunnyGray)
                    .multilineTextAlignment(.center)

            case .purchasing:
                ProgressView()
                    .padding(.vertical, 12)

            default:
                VStack(spacing: 12) {
                    SunnyButton(buyTitle, color: SunnyColors.lanternOrange) {
                        Task { await store.purchase() }
                    }

                    Button {
                        Task { await store.restore() }
                    } label: {
                        Text("pro_restore")
                            .font(SunnyFonts.caption())
                            .foregroundStyle(SunnyColors.sunnyGray)
                    }

                    if case .failed(let message) = store.purchaseState {
                        Text(verbatim: message)
                            .font(SunnyFonts.caption(13))
                            .foregroundStyle(SunnyColors.lanternOrange)
                            .multilineTextAlignment(.center)
                    }

                    Text("pro_apple_note")
                        .font(SunnyFonts.caption(12))
                        .foregroundStyle(SunnyColors.sunnyGray.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// Buy button title. Shows the localized price only when the product loaded; otherwise a neutral
    /// label (never a hardcoded "NT$50" or a "0").
    private var buyTitle: LocalizedStringKey {
        if let price = store.product?.displayPrice {
            // Interpolation builds the key "pro_buy_with_price %@" with `price` as the arg, so the
            // String Catalog localizes it per-locale (no manual L(), no resolved-string-as-key smell).
            return "pro_buy_with_price \(price)"
        }
        return "pro_buy"
    }
}

#Preview {
    ProUpgradeView()
}
