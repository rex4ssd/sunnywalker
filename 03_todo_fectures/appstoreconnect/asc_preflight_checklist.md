# ASC 送審前 Preflight Checklist（v1 手動版）

> 來源：vein 的 Lode App Store 雷（2026-05）+ SunnyWalker 四退教訓（2026-07）。
> 用法：**每次按 Submit for Review 前逐條勾**。全綠才送。
> 適用：SunnyWalker / Lode / lode_iphone / Budling / LetCube。
> 本次重送（build 16）的專屬步驟另見 `app_review_reply_260717_fix.md`。

---

## A. 機檢（terminal 可跑）

### A1. Product ID 三處一致（code / .storekit / ASC）

```bash
# 在專案根目錄跑，所有出現的 product ID 應完全一致、一字不差
grep -rn "productID\|proProductID\|product_id" --include="*.swift" --include="*.storekit" .
```

- [ ] code 內宣告的 Product ID == `.storekit` 設定檔 == ASC 網頁上的商品 ID
- [ ] 換過 ID 的話，**文件也要同步**（IDENTIFIERS.md 這次就漏了）
- ⚠️ SunnyWalker 教訓：刪除的 Product ID 被 Apple 永久鎖定不可重用，換 ID = 必須上傳新 binary

### A2. IAP 型別：code 語意 vs ASC 宣告一致

- [ ] code 用 `Transaction.currentEntitlements` 持久解鎖 / Restore / Family Sharing → ASC 必須是 **Non-Consumable**
- [ ] `.storekit` 檔內的 type 與 ASC 相同
- ⚠️ **型別建立後不可改**，建錯只能刪掉重建（＝再賠一個 Product ID）。建立時看到「Family Sharing」開關 = 型別選對了（Consumable 沒有這個選項）
- ⚠️ 若上架成 Consumable：使用者付錢 → 重開 app Pro 消失、Restore 無效 → 這是收費事故不是退件而已

### A3. 上傳 ASC 的圖片：禁 alpha channel

```bash
# 任何要上傳 ASC 的 PNG（icon / IAP image / screenshot）先檢查
sips -g hasAlpha <file.png>   # 應為 no
```

- [ ] 全部 fully opaque RGB（不是 RGBA）。適用所有 image slot：Marketing Icon / IAP Image / Promotional Artwork / Screenshot
- 修法（PIL composite 到純色底）見 vein `20260602-234130-a269`

### A4. Screenshot 尺寸

```bash
sips -g pixelWidth -g pixelHeight <file.png>
```

- [ ] **iOS**：IAP review screenshot 寬鬆（320–3840px 任意）；main screenshots 照裝置規格
- [ ] **macOS**：main + IAP + Promotional **全部**只收 4 種 exact 尺寸：2880×1800 / 2560×1600 / 1440×900 / 1280×800（Lode 有 `fix_screenshots.sh` 可 pipe）

---

## B. 人檢（ASC 網頁上逐項看）

### B1. IAP 商品本體

- [ ] Type 正確（見 A2）
- [ ] Family Sharing 開關狀態 = 商店文案承諾的狀態
- [ ] Localizations 已填（Display Name ≤30 字、Description ≤45 字，超過被截斷）
- [ ] **Review Screenshot 已上傳**（空欄 = 商品卡 Missing Metadata = 永遠進不了審查隊列 = 2.1(b) 退件。SunnyWalker 第四退就是這條）
- [ ] IAP Review Notes 已填（怎麼在 app 內找到購買點，含家長閘步驟）
- [ ] IAP Image 雖標 Optional 但**社交上 mandatory**——上 solid 版 icon
- [ ] 商品狀態 = **Ready to Submit**（不是就還有欄位沒補，不要送）

### B2. 版本頁

- [ ] Build 區塊掛的是**新** build（換過 Product ID 一定要新 binary）
- [ ] **「App 內購買項目」區塊有把 IAP 商品加進本次送審**（⚠️ 最容易漏的一步——商品 Ready to Submit ≠ 已掛進版本）
- [ ] 商店 Description 的數字與 code 內 `FeatureLimits` 一致（免費額度改過要同步）
- [ ] 版本 Review Notes 更新（product ID / 家長閘步驟 / grandfather 說明「僅 production 生效，審查環境永遠看到正常購買流程」）

### B3. 送出前最後一眼

- [ ] 若 hotfix 分支累積了非最小 diff，自己過一次 app 主流程
- [ ] 有回信草稿的話貼進 Review 訊息串再按 Submit
- [ ] （過審後）真機正式 Apple ID sandbox 測：購買 + Restore + Family Sharing

---

## 歷史退件對照（為什麼有這些條目）

| 退件/事故 | 條目 |
|---|---|
| SunnyWalker 四退 2.1(b)：Review Screenshot 空欄 | B1 |
| SunnyWalker：ASC 誤建 Consumable、ID 永久鎖 | A1 / A2 |
| SunnyWalker：版本頁漏掛 IAP 商品 | B2 |
| Lode：icon 帶 alpha 被 upload 端拒 | A3 |
| Lode：macOS IAP screenshot 尺寸不 exact 被拒 | A4 |
| Lode：quarantine xattr 進 .pkg → 91109（macOS 限定，release script 已修） | — |
