

## 預計
- 第一版 免費
- 之後有下載量，有進階功能，可能收費，但基礎功能維持free，進階會是限量使用，超過再收費
--- 月訂 /年訂 / 終身之類(之後有進階功能再想)

## in-App Purchase (IAP) (App Store 專用的「App 內購買」機制)
- 不會有任何連外付費，直接付給 apple

## Pricing model (定價方案/機制)
- **iOS App（App Store）**：數位商品 / 訂閱一律走 Apple IAP（StoreKit 2）。
 違反 App Store Guideline 3.1.1 禁止使用第三方金流（LemonSqueezy / Stripe 等），送審直接退件。
- **macOS direct sale（App Store 以外）**：可使用 LemonSqueezy 付款 + license key。
  此路徑與 iOS App 完全分開，不適用 3.1.1。