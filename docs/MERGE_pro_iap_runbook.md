# Merge runbook — feature/pro-iap-lifetime → main（在 Mac 上做）

> 目標：把 Pro IAP 併進 main，發 1.3.20260614 (build 11)。
> ⚠️ 不要在 Cowork sandbox 做：sandbox 刪不掉 `.git/*.lock`、也沒有 Xcode/xcodegen。
> 此 merge 有 **6 個衝突檔**，其中 `project.pbxproj` / `Localizable.xcstrings` 必須用 Xcode/xcodegen 重生。

---

## 步驟 1 — 啟動 merge（在 Mac 終端機）

```bash
cd ~/Documents/SunnyWalker
rm -f .git/index.lock .git/HEAD.lock .git/objects/maintenance.lock   # 清 sandbox 殘留 lock
git checkout main && git status            # 必須乾淨；目前 main 領先 origin 3 個 commit
git merge --no-ff --no-commit feature/pro-iap-lifetime
```

## 步驟 2 — 逐檔解 6 個衝突

| 衝突檔 | 怎麼解 |
|---|---|
| `project.yml` | **兩邊都留**：保留 pro 的 StoreKit/IAP 設定 + main 其他設定；版本改成 **`MARKETING_VERSION: "1.3.20260614"`、`CURRENT_PROJECT_VERSION: 11`** |
| `SunnyWalker.xcodeproj/project.pbxproj` | **別手解**。`git checkout --theirs SunnyWalker.xcodeproj/project.pbxproj`，解完 `project.yml` 後跑 `xcodegen generate` 整個重生，再 `git add` |
| `SunnyWalker/Localizable.xcstrings` | `git checkout --theirs SunnyWalker/Localizable.xcstrings`（pro 含全部 `pro_*` key），再用 Xcode build 一次讓字串抽取補回 main 端 key，確認每個 key 中(zh-Hant)英(en)都齊 |
| `SunnyWalker/Views/Home/HomeView.swift` | **手解**：同時保留 main 的吉卜力改動（`MascotView(scene:)` 等）＋ pro 的 `showingPro` / 設定頁 Pro 列 / `ProUpgradeView` sheet / `StoreService` 注入 |
| `SunnyWalker/Views/Settings/VoiceLibraryView.swift` | **手解**：main 已先併入 pro 的非 IAP 部分（commit 9ce1dfb），衝突多半是「到上限」的付費判斷 → 保留 pro 走 `FeatureLimits` 的版本，別讓 UI 重複 |
| `SunnyWalker/Services/AudioPlayer.swift` | main 已併入 pro 的暫停/續播（9ce1dfb），衝突多半瑣碎 → 確認暫停/續播只留一份 |

> 看衝突全貌：`git diff --name-only --diff-filter=U`（列出未解的檔）。

## 步驟 3 — 重生專案 + 驗收 + commit

```bash
xcodegen generate                  # 從解好的 project.yml 重生 pbxproj
git add -A
bash scripts/verify_pro_iap.sh     # 清 lock → xcodegen → build → unit tests → xcstrings/FeatureLimits 掃描
# Xcode → Scheme → Run → Options → StoreKit Configuration = Configuration.storekit（本機測購買）
git commit                          # 保留 merge commit 訊息
```

## 步驟 4 — 出問題就退回

```bash
git merge --abort                  # 解到一半想重來，乾淨回到 merge 前
```

---

## 解完之後

- 版本 / 送審細節 → `release_note/apple_store.md` 的 `1.3.20260614 (build 11)` 段。
- App Store Connect 文案 + IAP 設定 + 審查備註 → `03_todo_fectures/appstoreconnect/20260614_Pro_IAP_appstoreconnect.md`。

驗收重點（真機）：設定 → **家長驗證後**才看得到「SunnyWalker Pro」→ 購買 → 上限解除；Restore 可還原；裝過舊版的機子更新應**自動免費**為 Pro，全新安裝才看到付費頁。
