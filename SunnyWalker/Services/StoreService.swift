// SunnyWalker — StoreService.swift  |  Pro IAP (StoreKit 2)
//
// One Non-Consumable: "SunnyWalker Pro" — NT$50 lifetime unlock of every cap in `FeatureLimits`.
// Plan & compliance: 03_todo_fectures/03.todo_Premium_Features_fable_260612.md.
//
// THIS TYPE IS THE *SOLE WRITER* of the UserDefaults key "isProUnlocked", which `FeatureLimits.isPro`
// reads. Effective Pro is the OR of two independent sources:
//   1. A verified, non-revoked StoreKit entitlement for `proProductID` (purchase / restore /
//      Family Sharing / Ask-to-Buy approval), resolved by `refreshEntitlement()`.
//   2. The sticky "proGrandfathered" flag — granted ONCE, free, to anyone who already had
//      SunnyWalker installed before this (the first paid) build. See `resolveGrandfatheredEntitlement`.
//
// OR-ing the grandfather flag inside `refreshEntitlement()` is essential: a grandfathered user has
// NO StoreKit transaction, so a naive entitlement refresh would set isProUnlocked = false and revoke
// their free lifetime grant on the next launch. The OR keeps them Pro forever.

import Foundation
import StoreKit

@MainActor
final class StoreService: ObservableObject {
    static let shared = StoreService()

    // These are immutable Sendable String constants read from nonisolated contexts (FeatureLimits's
    // get/set, the grandfather resolver, tests), so they must be `nonisolated` — otherwise they
    // inherit the class's @MainActor isolation and Swift 6 rejects the cross-context reference.

    /// Must match the Product ID created in App Store Connect and the StoreKit config file, byte-for-byte.
    nonisolated static let proProductID = "app.rexcode.sunnywalker.pro.lifetime"

    // MARK: UserDefaults keys
    /// Effective Pro flag read by `FeatureLimits.isPro`. Written ONLY here.
    nonisolated static let proUnlockedKey   = "isProUnlocked"
    /// Sticky: this device owned SunnyWalker before the paid build → lifetime Pro, free. Never cleared.
    nonisolated static let grandfatheredKey = "proGrandfathered"
    /// One-shot gate so the existing-install heuristic is evaluated exactly once (first paid-build launch).
    nonisolated static let resolvedKey      = "proEntitlementResolved"

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case pendingAskToBuy        // child Apple ID → Ask to Buy; waiting for parent approval
        case purchased
        case failed(String)
    }

    /// Drives UI live. Mirrors the persisted "isProUnlocked". `FeatureLimits.isPro` reads UserDefaults
    /// directly so non-SwiftUI code (AudioRecorder, schedulers) sees the same value off the main actor.
    @Published private(set) var isPro: Bool
    /// nil until the product loads (e.g. offline). UI hides the price rather than showing 0 / a hardcode.
    @Published private(set) var product: Product?
    @Published private(set) var purchaseState: PurchaseState = .idle

    private var updatesListener: Task<Void, Never>?

    private init() {
        self.isPro = UserDefaults.standard.bool(forKey: Self.proUnlockedKey)
    }

    // MARK: - Lifecycle

    /// Call once at app launch (from `SunnyWalkerApp`), BEFORE any UI. Opening the
    /// `Transaction.updates` listener early is mandatory — otherwise asynchronous transactions
    /// (Ask-to-Buy approval, Family Sharing, refund/revocation) that arrive while no listener is
    /// attached are missed.
    func start() {
        if updatesListener == nil {
            updatesListener = listenForTransactions()
        }
        Task {
            await refreshEntitlement()
            await loadProduct()
        }
    }

    /// Load the Pro product. On failure (offline) `product` stays nil; ProUpgradeView retries on open.
    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            self.product = products.first
        } catch {
            print("🛒 StoreService.loadProduct failed: \(error.localizedDescription)")
            self.product = nil
        }
    }

    // MARK: - Purchase / Restore

    func purchase() async {
        guard let product else {
            // No product loaded (offline). Try once more, then bail without changing state.
            await loadProduct()
            guard product != nil else { return }
            return await purchase()
        }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseState = .failed(L("pro_error_unverified"))
                    return
                }
                await transaction.finish()
                await refreshEntitlement()
                purchaseState = .purchased
            case .pending:
                // Ask-to-Buy: parent approval pending. `Transaction.updates` unlocks it later.
                purchaseState = .pendingAskToBuy
            case .userCancelled:
                purchaseState = .idle          // silent return — no nagging
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// Required for a Non-Consumable: re-sync App Store entitlements (new device, reinstall, Family Sharing).
    func restore() async {
        purchaseState = .purchasing
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            purchaseState = isPro ? .purchased : .idle
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Entitlement

    /// Recompute effective Pro = (verified, non-revoked StoreKit entitlement) OR (grandfathered).
    /// `currentEntitlements` is served from the on-device cache, so this works offline.
    func refreshEntitlement() async {
        var storeEntitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proProductID, transaction.revocationDate == nil {
                storeEntitled = true
            }
        }
        let grandfathered = UserDefaults.standard.bool(forKey: Self.grandfatheredKey)
        setProUnlocked(storeEntitled || grandfathered)
    }

    /// The ONE place that persists effective Pro + mirrors it into the @Published flag for SwiftUI.
    /// `FeatureLimits.isPro`'s setter writes UserDefaults("isProUnlocked") — the value off-main code reads.
    private func setProUnlocked(_ value: Bool) {
        FeatureLimits.isPro = value
        if isPro != value { isPro = value }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
    }

    // MARK: - Grandfathering (existing installs upgrade to lifetime Pro, free)

    /// Evaluate the existing-install heuristic EXACTLY ONCE, then freeze the result.
    /// Call as the first thing in `AppDelegate.didFinishLaunching`, before any first-launch writes
    /// (settings defaults, SwiftData container) could pollute the signals.
    ///
    /// `nonisolated` + UserDefaults/FileManager only → safe to call directly on the launch thread.
    nonisolated static func resolveGrandfatheredEntitlement() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: resolvedKey) else { return }   // already decided on a prior launch
        d.set(true, forKey: resolvedKey)

        if isExistingInstallFromPreviousVersion() {
            d.set(true, forKey: grandfatheredKey)
            d.set(true, forKey: proUnlockedKey)   // grant synchronously → no window where caps re-lock
            print("🎁 Grandfather: pre-paid install detected → lifetime SunnyWalker Pro granted, free")
        } else {
            print("🆕 Grandfather: clean first install → standard free tier (Pro available to purchase)")
        }
    }

    /// Settings keys a previous version persisted through normal use. Their presence on the FIRST
    /// paid-build launch means the app ran before. (A clean install's UserDefaults has none of these:
    /// `AppSettings`/`LocalizationManager` only WRITE them via `didSet`, which doesn't fire during
    /// `init`, so merely launching fresh leaves them unset.)
    nonisolated static let legacyInstallKeys = [
        "use24HourClock", "recordingGapSeconds", "alarmRingDurationMinutes",
        "mascotTheme", "parentalUnlockDurationMinutes", "parentalUnlockUntil",
        "backgroundListeningEnabled", "appLanguageCode",
    ]

    /// True if this device already ran a pre-paid version of SunnyWalker. No prior build stored its
    /// own version number, so existing ownership is inferred from persisted on-device state. Any ONE
    /// signal is sufficient; a genuinely clean install has none of them at first-launch time.
    nonisolated static func isExistingInstallFromPreviousVersion() -> Bool {
        hasPreviousDataFiles() || hasLegacyInstallSignal(in: .standard)
    }

    /// File-system evidence of a prior run.
    nonisolated static func hasPreviousDataFiles() -> Bool {
        let fm = FileManager.default
        // SwiftData store from a previous run (created lazily AFTER didFinishLaunching on a fresh
        // install, so its presence at launch-decision time means the app has run before).
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            for name in ["default.store", "default.sqlite", "default.store-wal", "default.store-shm"] {
                if fm.fileExists(atPath: appSupport.appendingPathComponent(name).path) { return true }
            }
        }
        // Recordings folder (parent voice clips / custom ringtones live in Documents/Recordings).
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            if fm.fileExists(atPath: docs.appendingPathComponent("Recordings").path) { return true }
        }
        return false
    }

    /// UserDefaults evidence of a prior run. Pure (defaults injected) so it is deterministically testable.
    nonisolated static func hasLegacyInstallSignal(in defaults: UserDefaults) -> Bool {
        for key in legacyInstallKeys where defaults.object(forKey: key) != nil { return true }
        return false
    }
}
