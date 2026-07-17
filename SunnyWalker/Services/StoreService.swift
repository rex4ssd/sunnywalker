// SunnyWalker — StoreService.swift  |  Pro IAP (StoreKit 2)
//
// One Non-Consumable: "SunnyWalker Pro" — NT$50 lifetime unlock of every cap in `FeatureLimits`.
// Plan & compliance: 03_todo_fectures/03.todo_Premium_Features_fable_260612.md.
//
// THIS TYPE IS THE *SOLE WRITER* of the UserDefaults key "isProUnlocked", which `FeatureLimits.isPro`
// reads. Effective Pro is the OR of two independent sources:
//   1. A verified, non-revoked StoreKit entitlement for `proProductID` (purchase / restore /
//      Family Sharing / Ask-to-Buy approval), resolved by `refreshEntitlement()`.
//   2. The sticky "proGrandfathered" flag — granted ONCE, free, to anyone whose Apple ID first
//      downloaded SunnyWalker BEFORE the first paid build (build 11), determined from Apple's
//      signed `AppTransaction.originalAppVersion`. See `resolveGrandfatherIfNeeded`.
//
// OR-ing the grandfather flag inside `refreshEntitlement()` is essential: a grandfathered user has
// NO StoreKit transaction, so a naive entitlement refresh would set isProUnlocked = false and revoke
// their free lifetime grant on the next launch. The OR keeps them Pro forever.
//
// Why AppTransaction (not a local file/UserDefaults heuristic): the grant must follow the *Apple ID*,
// not the device container. originalAppVersion is account-bound and Apple-signed, so it survives
// delete-&-reinstall and new devices — a returning pre-paid customer keeps their free Pro. A local
// "did this container run before?" check would falsely DENY those customers on a clean reinstall.

import Foundation
import StoreKit

/// DEBUG-only logger for the Pro / entitlement flow. `@autoclosure` + `#if DEBUG` means the message
/// string isn't even constructed in Release, so these traces add zero cost to the shipped app.
@inline(__always)
private func proLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

@MainActor
final class StoreService: ObservableObject {
    static let shared = StoreService()

    // These are immutable Sendable String constants read from nonisolated contexts (FeatureLimits's
    // get/set, the grandfather resolver, tests), so they must be `nonisolated` — otherwise they
    // inherit the class's @MainActor isolation and Swift 6 rejects the cross-context reference.

    /// Must match the Product ID created in App Store Connect and the StoreKit config file, byte-for-byte.
    nonisolated static let proProductID = "app.rexcode.sunnywalker.pro.lifetime2"

    // MARK: UserDefaults keys
    /// Effective Pro flag read by `FeatureLimits.isPro`. Written ONLY here.
    nonisolated static let proUnlockedKey   = "isProUnlocked"
    /// Sticky: this Apple ID owned SunnyWalker before the paid build → lifetime Pro, free. Never cleared.
    nonisolated static let grandfatheredKey = "proGrandfathered"
    /// One-shot gate: frozen ONLY once Apple gives a definitive AppTransaction answer (so a transient
    /// offline failure never permanently denies a genuine pre-paid customer — it just retries).
    nonisolated static let resolvedKey      = "proEntitlementResolved"

    /// First build (CFBundleVersion) that shipped the paid Pro IAP. Anyone whose Apple ID first
    /// downloaded SunnyWalker at a build BELOW this was a free-era user → lifetime Pro, free.
    /// History (project.yml): builds 1–10 = free era (1.0–1.2); build 11 (1.3.20260614) = first paid build.
    nonisolated static let firstPaidBuild = 11

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
            proLog("🔑[Pro] StoreService.start() → resolve grandfather → refresh entitlement → load product")
            await resolveGrandfatherIfNeeded()   // sets the sticky flag before we compute effective Pro
            await refreshEntitlement()
            await loadProduct()
            proLog("🔑[Pro] start() done — isPro=\(isPro) product=\(product?.displayPrice ?? "nil")")
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
        proLog("🔑[Pro] refreshEntitlement: storeEntitled=\(storeEntitled) grandfathered=\(grandfathered) → isPro=\(storeEntitled || grandfathered)")
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

    // MARK: - Grandfathering (free-era installs upgrade to lifetime Pro, free)

    /// Resolve the one-time grandfather grant from Apple's signed `AppTransaction`. Account-bound, so
    /// it survives delete-&-reinstall / new device, and reads the on-device receipt (works offline
    /// once provisioned). Sets the sticky `grandfatheredKey` exactly once; the result is frozen
    /// (`resolvedKey`) ONLY on a definitive Apple answer, so a transient offline failure just retries
    /// next launch instead of permanently denying a genuine pre-paid customer.
    func resolveGrandfatherIfNeeded() async {
        let d = UserDefaults.standard
        proLog("🔑[Pro] resolveGrandfather START — grandfathered=\(d.bool(forKey: Self.grandfatheredKey)) resolved=\(d.bool(forKey: Self.resolvedKey)) isProUnlocked=\(d.bool(forKey: Self.proUnlockedKey)) firstPaidBuild=\(Self.firstPaidBuild)")

        #if DEBUG
        // Test lever (DEBUG only, never ships): scheme env var SW_FORCE_NEW_USER=1 forces the paid-era
        // (purchase) state even though StoreKit testing reports originalAppVersion "1.0".
        let forced = ProcessInfo.processInfo.environment["SW_FORCE_NEW_USER"]
        proLog("🔑[Pro] DEBUG SW_FORCE_NEW_USER=\(forced ?? "<unset>") SW_FAKE_ORIGINAL_BUILD=\(ProcessInfo.processInfo.environment["SW_FAKE_ORIGINAL_BUILD"] ?? "<unset>")")
        if forced == "1" {
            d.set(false, forKey: Self.grandfatheredKey)
            // Do NOT freeze resolvedKey — flipping the env var back off must re-resolve cleanly.
            proLog("🧪[Pro] SW_FORCE_NEW_USER=1 → NOT grandfathered (testing purchase UI)")
            return
        }
        #endif

        if d.bool(forKey: Self.grandfatheredKey) {
            proLog("🎁[Pro] already granted (sticky) → Pro.")
            return   // sticky, never re-check
        }
        #if !DEBUG
        // Release freezes once Apple answers; DEBUG re-resolves every launch so toggling the env var /
        // StoreKit config takes effect without reinstalling.
        if d.bool(forKey: Self.resolvedKey) {
            proLog("🆕[Pro] already resolved as paid-era user (no free grant)")
            return
        }
        #endif

        proLog("🔑[Pro] querying AppTransaction.shared …")
        do {
            let result = try await AppTransaction.shared
            switch result {
            case .unverified(let appTx, let err):
                proLog("🛒[Pro] AppTransaction UNVERIFIED: originalAppVersion=\"\(appTx.originalAppVersion)\" err=\(err) — not freezing, will retry")
                return
            case .verified(let appTx):
                var raw = appTx.originalAppVersion
                // Sandbox / Xcode environments ALWAYS report originalAppVersion "1.0" (Apple-documented),
                // so it carries no real install history there — it must never drive the grandfather grant.
                // App Review runs in sandbox: builds 14 was rejected (2026-06-27 & 07-07) precisely because
                // the reviewer's device was mis-grandfathered to Pro, hiding the purchase row and price.
                var environmentTrusted = appTx.environment == .production
                #if DEBUG
                // StoreKit LOCAL TESTING reports the CURRENT build as originalAppVersion (e.g. "13"),
                // which can't represent an old install. To test the grandfather path on a dev build,
                // set scheme env SW_FAKE_ORIGINAL_BUILD to any value < firstPaidBuild (e.g. "5") —
                // it also marks the environment as trusted so the .xcode env doesn't block the test.
                // (Production uses the real AppTransaction value, so this never affects shipping.)
                if let fake = ProcessInfo.processInfo.environment["SW_FAKE_ORIGINAL_BUILD"], !fake.isEmpty {
                    proLog("🧪[Pro] SW_FAKE_ORIGINAL_BUILD=\(fake) overrides StoreKit-testing originalAppVersion=\"\(raw)\"")
                    raw = fake
                    environmentTrusted = true
                }
                #endif
                let parsed = Self.leadingInt(raw)
                let grant = Self.shouldGrandfather(originalAppVersion: raw,
                                                   isProductionEnvironment: environmentTrusted)
                proLog("🔑[Pro] AppTransaction VERIFIED: env=\(appTx.environment.rawValue) trusted=\(environmentTrusted) originalAppVersion=\"\(raw)\" parsedBuild=\(parsed.map(String.init) ?? "nil") cutoff=\(Self.firstPaidBuild) grandfather=\(grant)")
                if grant {
                    d.set(true, forKey: Self.grandfatheredKey)
                    d.set(true, forKey: Self.proUnlockedKey)   // grant immediately; refreshEntitlement mirrors it
                    proLog("🎁[Pro] GRANTED lifetime Pro (free, grandfathered)")
                } else {
                    proLog("🆕[Pro] paid-era user → free tier (Pro available to purchase)")
                }
                // Freeze only on a definitive PRODUCTION answer. A sandbox answer is throwaway:
                // freezing it would permanently deny a genuine free-era customer who once ran a
                // TestFlight build in this container — they must re-resolve on the App Store copy.
                if environmentTrusted {
                    d.set(true, forKey: Self.resolvedKey)
                }
            }
        } catch {
            proLog("🛒[Pro] AppTransaction THREW: \(error) — will retry next launch")
        }
    }

    /// Pure & testable: the ONE grandfather decision. `originalAppVersion` is only meaningful in the
    /// production environment — sandbox (App Review, TestFlight) and Xcode always report "1.0",
    /// which would falsely grandfather every reviewer/tester. Outside production: never grant.
    nonisolated static func shouldGrandfather(originalAppVersion: String,
                                              isProductionEnvironment: Bool) -> Bool {
        guard isProductionEnvironment else { return false }
        return isGrandfatheredOriginalVersion(originalAppVersion)
    }

    /// Pure & testable. `AppTransaction.originalAppVersion` on iOS is the ORIGINAL `CFBundleVersion`
    /// (build number) the Apple ID first downloaded — an integer string in production (e.g. "10").
    /// Parse its leading integer and grandfather everything below the first paid build.
    /// Unparseable → fail safe (NO free grant): never give away Pro on a value we can't trust.
    nonisolated static func isGrandfatheredOriginalVersion(_ originalAppVersion: String) -> Bool {
        guard let build = leadingInt(originalAppVersion) else { return false }
        return build < firstPaidBuild
    }

    /// Leading run of digits as an Int (tolerates StoreKit-testing values like "1.0" → 1). nil if none.
    nonisolated static func leadingInt(_ s: String) -> Int? {
        let digits = s.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}
