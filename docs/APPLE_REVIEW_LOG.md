# SunnyWalker — Apple Review Log

> 送審／退件／過審一版一節，最新在最下面；舊節不改寫。完整範例：`~/Documents/lode/docs/APPLE_REVIEW_LOG.md`。
> 狀態真相以 `family_status.py` 拉的為準；這裡記「發生了什麼、為什麼、學到什麼」。

## 2026-09-06 — 建檔（家族 layout 一致化，事實自 ASC 拉取）

- 架上：**1.3.20260615**，ASC 版本記錄建立 2026-06-15
- 2026-08 之前的送審備忘（含各版 What's New）：`release_note/legacy/apple_store.md`

之後每次送審／退件／過審在下方加一節：日期時間、版本 (build)、事件、reviewer 原文重點、回應、學到。

## 2026-09-20 — 1.4.20260920 (build 18) 上傳，準備送審

- 00:17 `altool` 上傳成功（Delivery UUID 1f19ce17-b09e-402e-8814-aae7fcfca5d0），00:2x 處理完成 VALID。
- ASC 建立版本 1.4.20260920（`asc_push.py --create-version --apply`）：中英 What's New／Promotional Text、Review Notes 推上去；
  build 18 已掛；狀態 **PREPARE_FOR_SUBMISSION**。重跑 plan 零差異。
- 截圖全換：en-US 與 zh-Hant 各 15 張（6.9" x5、6.5" x5、13" iPad x5）。原本架上只有 en-US 的 6.5"＋12.9" 各 10 張。
- 這是 1.4 第一次上傳；`v1.4.20260814` 從未送審，功能全併入本版。
- 學到：
  - 260814 那份 Promo 有「免費／free」，`asc_copy_validate` 擋下（2.3.7）——價格字眼連「免費」都不行。
  - Xcode 沒登入帳號 → 家族 `archive_upload.sh` 會 `exportArchive No Accounts`；改用
    `xcodebuild archive / -exportArchive -allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID` 手動走通。
  - `asc_api.reexec_in_venv_if_needed` 在這個 session 找不到 venv（`is_file()` 判斷失敗），直接用
    `~/Documents/py/venv/bin/python3` 跑就好。
- **尚未 Submit for Review**（等 Rex 確認）。送審籃只能有 1 個項目（app 版本）；IAP `pro.lifetime2` 早已上架，不要加進去。

## 2026-09-20 21:50 — 1.4.20260920 (build 18) 送審，Waiting for Review

- Rex 試用後授權送審。送出前最後核對：build 18 VALID 已掛、中英各 15 張截圖全 COMPLETE、Review Notes 2152 字元、
  聯絡資訊齊、無其他進行中的送審；發佈方式沿用「過審後自動上架」（AFTER_APPROVAL）。
- 用 API 送：`POST /reviewSubmissions` → `POST /reviewSubmissionItems`（只放 app 版本，籃內 1 項，IAP 沒帶）→
  `PATCH submitted=true`。⚠️ `asc_api` 的 `post/patch` 會自己包外層 `{"data": …}`，傳進去的 dict 不要再包一層（第一次 422 就是這個）。
- 送審前補的一個檢查：實際合成最長的報時／倒數句子量長度（`ChimeRenderTests`）——中英最長都 < 3s，
  低於 iOS 自訂通知音的安全長度（~4.6s，超過會被換成預設音）。

## 2026-09-21 06:18 — 1.4.20260920 (build 18) 過審

- Apple 通知「Review of your submission is complete … eligible for distribution」；送出（09-20 21:50）到通過約 8.5 小時，一次過、無退件。
- 發佈方式是 AFTER_APPROVAL，過審即自動上架，取代架上的 1.3.20260615 (17)。
- 這版帶上去的合規敏感點都沒被問：MetricKit 本機診斷（Review Notes 1）、家長閘可改 4 位數密碼（2）、Pro 購買列移到家長頁尾段（3）、
  語音報時走本機通知（4）。Promo 拿掉「免費／free」後也沒有 2.3.7 的問題。
