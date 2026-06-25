// SunnyWalker — AppSettings.swift  |  Day 30  |  Shared app preferences

import Foundation
import SwiftUI
import UIKit   // UIImage — 自訂向日葵花心照片的儲存/載入

// MARK: - Feature limits (free vs Pro)

/// Single source of truth for every monetizable cap in the app. The free tier enforces these;
/// the paid (Pro) version unlocks them by flipping `isPro` to true — ideally wired to StoreKit /
/// a purchased entitlement later. KEEP ALL CAPS HERE so adding Pro is a one-switch change and so
/// code review can see the whole free/paid boundary in one place. See 03_todo_fectures.md.
///
/// Semantics: `Int.max` / `.infinity` mean "effectively unlimited" — call sites that schedule a
/// timer or pass a duration MUST check `.isFinite` before using the recording caps.
enum FeatureLimits {
    /// Whether the user owns Pro. Backed by UserDefaults("isProUnlocked"), which is set from the
    /// StoreKit entitlement OR the one-time grandfather grant for pre-paid installs. See `StoreService`.
    /// WRITE ONLY through `StoreService` (the sole owner of entitlement state); tests may toggle it.
    /// Read here (not @Published) so off-main code — AudioRecorder, schedulers — sees the same value.
    static var isPro: Bool {
        get { UserDefaults.standard.bool(forKey: StoreService.proUnlockedKey) }
        set { UserDefaults.standard.set(newValue, forKey: StoreService.proUnlockedKey) }
    }

    // Free-tier baselines + the one finite Pro value. Named so the caps below AND the Pro upsell
    // copy (ProUpgradeView) read the same numbers — no literal cap is hardcoded in any view.
    // 免費版「全部設定」總量上限＝10：鬧鐘與待辦是同一種 Alarm 物件，所以這個數字同時涵蓋
    // 「鬧鐘 + 待辦」的總和（不分群組、不分類別）。Pro 版無上限。2026-06-22 從 6 提升到 10（促銷）。
    static let freeMaxAlarms = 10
    static let freeMaxVoiceClips = 5
    static let freeMaxVoiceClipSeconds: Double = 5
    static let proMaxVoiceClipSeconds: Double = 30
    static let freeMaxAlarmRecordingSeconds: TimeInterval = 180

    /// Max number of alarms a parent can keep at once.
    static var maxAlarms: Int { isPro ? .max : freeMaxAlarms }

    /// Max number of saved voice clips in the library ("自定鈴聲").
    static var maxVoiceClips: Int { isPro ? .max : freeMaxVoiceClips }

    /// Max length of a single library voice clip, in seconds.
    static var maxVoiceClipSeconds: Double { isPro ? proMaxVoiceClipSeconds : freeMaxVoiceClipSeconds }

    /// Max length of a per-alarm parent recording, in seconds. `.infinity` for Pro (no auto-stop).
    static var maxAlarmRecordingSeconds: TimeInterval { isPro ? .infinity : freeMaxAlarmRecordingSeconds }
}

// MARK: - Mascot theme

enum MascotTheme: String, CaseIterable, Identifiable {
    case sunnyAlarm = "sunnyAlarm"
    case sunny    = "sunny"
    case giraffe  = "giraffe"
    case bunny    = "bunny"
    case bear     = "bear"
    /// 自訂向日葵：花心放使用者的一張照片（全 app 共用，由 FlowerCenterEditorView 設定）。
    case flower   = "flower"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sunnyAlarm: return "小鬧晴"
        case .sunny:   return "小晴（灰色精靈）"
        case .giraffe: return "長頸鹿"
        case .bunny:   return "小兔子"
        case .bear:    return "小熊"
        case .flower:  return "向日葵（自訂照片）"
        }
    }

    var icon: String {
        switch self {
        case .sunnyAlarm: return "alarm.fill"
        case .sunny:   return "moon.stars.fill"
        case .giraffe: return "pawprint.fill"
        case .bunny:   return "hare.fill"
        case .bear:    return "teddybear.fill"
        case .flower:  return "camera.macro"
        }
    }
}

/// App-wide preferences stored in UserDefaults.
/// Observed by views via @ObservedObject so UI reacts to changes live.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private init() {
        // 12h/24h: default to the device's own clock convention
        if let stored = UserDefaults.standard.object(forKey: "use24HourClock") as? Bool {
            self.use24HourClock = stored
        } else {
            // Probe the system locale's hour cycle
            let probe = DateFormatter()
            probe.dateStyle = .none
            probe.timeStyle = .short
            probe.locale = Locale.current
            self.use24HourClock = probe.dateFormat.contains("H")
        }
        self.recordingGapSeconds = UserDefaults.standard.object(forKey: "recordingGapSeconds") as? Int ?? 2
        self.alarmRingDurationMinutes = UserDefaults.standard.object(forKey: "alarmRingDurationMinutes") as? Int ?? 5
        self.backgroundListeningEnabled = UserDefaults.standard.object(forKey: "backgroundListeningEnabled") as? Bool ?? false
        let raw = UserDefaults.standard.string(forKey: "mascotTheme") ?? MascotTheme.sunny.rawValue
        self.mascotTheme = MascotTheme(rawValue: raw) ?? .sunny
        self.parentalUnlockDurationMinutes = UserDefaults.standard.object(forKey: "parentalUnlockDurationMinutes") as? Int ?? 5
        // 多人鬧鐘分組設定
        self.groupEnabled = UserDefaults.standard.object(forKey: "groupEnabled") as? Bool ?? false
        let storedCount = UserDefaults.standard.object(forKey: "groupCount") as? Int ?? 1
        self.groupCount = min(max(storedCount, 1), AppSettings.maxGroups)
        let storedNames = UserDefaults.standard.stringArray(forKey: "groupNames") ?? []
        // 永遠補齊到 maxGroups 長度，空字串＝沿用在地化預設名（群組 A / Group A）。
        self.groupNames = (0..<AppSettings.maxGroups).map { i in
            i < storedNames.count ? storedNames[i] : ""
        }
        // 每組吉祥物（MascotTheme rawValue，空字串＝沿用全域 mascotTheme）。
        let storedMascots = UserDefaults.standard.stringArray(forKey: "groupMascots") ?? []
        self.groupMascots = (0..<AppSettings.maxGroups).map { i in
            i < storedMascots.count ? storedMascots[i] : ""
        }
        // 每組的開關狀態（首頁點群組橫幅切換；off＝該組鬧鐘暫停響＋清單變灰）。預設全部 on。
        let storedActive = (UserDefaults.standard.array(forKey: "groupActiveStates") as? [Bool]) ?? []
        self.groupActiveStates = (0..<AppSettings.maxGroups).map { i in
            i < storedActive.count ? storedActive[i] : true
        }
        // 每組的「報時」開關（設定頁群組列最右側的鈴鐺切換）。on＝這組的鬧鐘改成報時鬧鐘
        // （新增鬧鐘時鈴聲欄會換成「報時次數」）。預設全部 off。
        let storedChime = (UserDefaults.standard.array(forKey: "groupChimeStates") as? [Bool]) ?? []
        self.groupChimeStates = (0..<AppSettings.maxGroups).map { i in
            i < storedChime.count ? storedChime[i] : false
        }
        // 每組的「待辦(todo)」開關（群組列上鈴鐺旁的圖示切換）。on＝這組的鬧鐘變成待辦語音提醒。
        // 與報時互斥（同一組不能同時報時又待辦）。預設全部 off。
        let storedTodo = (UserDefaults.standard.array(forKey: "groupTodoStates") as? [Bool]) ?? []
        self.groupTodoStates = (0..<AppSettings.maxGroups).map { i in
            i < storedTodo.count ? storedTodo[i] : false
        }
        // 自訂向日葵花心照片：開機載入一次到記憶體，避免 mascot 24fps 重繪時反覆讀檔。
        self.flowerImage = AppSettings.loadFlowerImageFromDisk()
        let unlockedUntil = UserDefaults.standard.double(forKey: "parentalUnlockUntil")
        if unlockedUntil > Date().timeIntervalSince1970 {
            self.parentalUnlockUntil = Date(timeIntervalSince1970: unlockedUntil)
        } else {
            self.parentalUnlockUntil = nil
        }
    }

    // MARK: - Time format

    /// true = show 14:05 · false = show 2:05 PM
    @Published var use24HourClock: Bool {
        didSet { UserDefaults.standard.set(use24HourClock, forKey: "use24HourClock") }
    }

    // MARK: - Recording playback

    /// Seconds of silence between recording loops (gives child a moment to speak).
    /// Range 0–5; stored so parent can tune it in Settings.
    @Published var recordingGapSeconds: Int {
        didSet { UserDefaults.standard.set(recordingGapSeconds, forKey: "recordingGapSeconds") }
    }

    // MARK: - Alarm ring duration

    /// How long the alarm keeps ringing before it auto-stops and lets the screen sleep.
    /// Range 1–10 minutes. Prevents the battery draining if the child isn't there to wake.
    @Published var alarmRingDurationMinutes: Int {
        didSet { UserDefaults.standard.set(alarmRingDurationMinutes, forKey: "alarmRingDurationMinutes") }
    }

    // MARK: - Background listening (experimental, OFF by default)

    /// When ON, the app keeps a microphone session alive (foreground-started) so the child can
    /// voice-stop the alarm while the screen is off / app is backgrounded — like a recorder app.
    /// ⚠️ Keeps the orange mic indicator lit and uses the mic continuously; off by default.
    @Published var backgroundListeningEnabled: Bool {
        didSet { UserDefaults.standard.set(backgroundListeningEnabled, forKey: "backgroundListeningEnabled") }
    }

    // MARK: - Mascot theme

    @Published var mascotTheme: MascotTheme {
        didSet { UserDefaults.standard.set(mascotTheme.rawValue, forKey: "mascotTheme") }
    }

    @Published var parentalUnlockDurationMinutes: Int {
        didSet { UserDefaults.standard.set(parentalUnlockDurationMinutes, forKey: "parentalUnlockDurationMinutes") }
    }

    // MARK: - 多人鬧鐘分組（Groups）

    /// 群組數量上限。群組索引 0…maxGroups-1 對應 A…E。
    static let maxGroups = 5

    /// 是否啟用多人鬧鐘分組。關閉時整個 app 只當作單一群組 A（首頁不分頁、新增鬧鐘不顯示群組選擇）。
    /// 關閉並不會清掉鬧鐘原本的 groupIndex——只是暫時隱藏 B–E 的鬧鐘，重新啟用即恢復。
    @Published var groupEnabled: Bool {
        didSet { UserDefaults.standard.set(groupEnabled, forKey: "groupEnabled") }
    }

    /// 啟用後可用的群組數（1…maxGroups）。didSet 會 clamp，避免外部寫入越界值。
    @Published var groupCount: Int {
        didSet {
            let clamped = min(max(groupCount, 1), Self.maxGroups)
            if clamped != groupCount { groupCount = clamped; return }   // 二次寫入帶回合法值後即返回
            UserDefaults.standard.set(groupCount, forKey: "groupCount")
        }
    }

    /// 每個群組的自訂名稱（長度固定 maxGroups）。空字串＝沿用在地化預設名（群組 A / Group A）。
    /// 顯示請用 `groupDisplayName(_:)`，不要直接讀這個陣列。
    @Published var groupNames: [String] {
        didSet { UserDefaults.standard.set(groupNames, forKey: "groupNames") }
    }

    /// 每個群組的吉祥物（MascotTheme rawValue，長度固定 maxGroups）。空字串＝沿用全域 mascotTheme。
    /// 讀取請用 `groupMascot(_:)`，設定請用 `setGroupMascot(_:_:)`。
    @Published var groupMascots: [String] {
        didSet { UserDefaults.standard.set(groupMascots, forKey: "groupMascots") }
    }

    /// 第 index 組要顯示的吉祥物：該組未指定（空字串/越界）→ 回全域 mascotTheme。
    func groupMascot(_ index: Int) -> MascotTheme {
        guard index >= 0, index < groupMascots.count,
              !groupMascots[index].isEmpty,
              let theme = MascotTheme(rawValue: groupMascots[index]) else {
            return mascotTheme
        }
        return theme
    }

    /// 設定第 index 組的吉祥物（補齊陣列長度後寫入）。
    func setGroupMascot(_ index: Int, _ theme: MascotTheme) {
        guard index >= 0, index < Self.maxGroups else { return }
        var arr = groupMascots
        while arr.count < Self.maxGroups { arr.append("") }
        arr[index] = theme.rawValue
        groupMascots = arr
    }

    /// 每組的開關狀態（首頁群組橫幅的 on/off）。off＝該組鬧鐘暫停（HomeView 會把成員 isEnabled 連動關掉）
    /// ＋首頁清單變灰。這跟設定頁「調整群組數量」是兩回事——這裡只是暫時開關，不會刪掉群組或鬧鐘。
    @Published var groupActiveStates: [Bool] {
        didSet { UserDefaults.standard.set(groupActiveStates, forKey: "groupActiveStates") }
    }

    /// 第 index 組是否開啟（越界視為開啟，維持既有行為）。
    func isGroupActive(_ index: Int) -> Bool {
        guard index >= 0, index < groupActiveStates.count else { return true }
        return groupActiveStates[index]
    }

    /// 設定第 index 組的開關（補齊陣列長度後寫入）。
    func setGroupActive(_ index: Int, _ active: Bool) {
        guard index >= 0, index < Self.maxGroups else { return }
        var arr = groupActiveStates
        while arr.count < Self.maxGroups { arr.append(true) }
        arr[index] = active
        groupActiveStates = arr
    }

    /// 每組的「報時」開關（長度固定 maxGroups，預設全 false）。on＝這組的鬧鐘變成報時鬧鐘：
    /// 新增/編輯鬧鐘時把「鈴聲」欄換成「報時次數」，時間到時用系統語音念出時刻 N 次。
    /// 讀取請用 `isGroupChimeEnabled(_:)`，設定請用 `setGroupChimeEnabled(_:_:)`。
    @Published var groupChimeStates: [Bool] {
        didSet { UserDefaults.standard.set(groupChimeStates, forKey: "groupChimeStates") }
    }

    /// 第 index 組是否啟用報時（越界視為未啟用）。
    func isGroupChimeEnabled(_ index: Int) -> Bool {
        guard index >= 0, index < groupChimeStates.count else { return false }
        return groupChimeStates[index]
    }

    /// 設定第 index 組的報時開關（補齊陣列長度後寫入）。開啟報時會自動關掉同組的待辦（兩者互斥）。
    func setGroupChimeEnabled(_ index: Int, _ enabled: Bool) {
        guard index >= 0, index < Self.maxGroups else { return }
        var arr = groupChimeStates
        while arr.count < Self.maxGroups { arr.append(false) }
        arr[index] = enabled
        groupChimeStates = arr
        if enabled { setGroupTodoEnabledRaw(index, false) }   // 報時 / 待辦互斥
    }

    /// 每組的「待辦(todo)」開關（長度固定 maxGroups，預設全 false）。on＝這組的鬧鐘變成待辦語音提醒：
    /// 新增/編輯時改成「錄一段提醒語音 + 選圖示 + 顯示時長」，時間到時在主頁吉祥物旁冒出小圖示，
    /// 兒童長按播放。與報時互斥。讀取請用 `isGroupTodoEnabled(_:)`，設定請用 `setGroupTodoEnabled(_:_:)`。
    @Published var groupTodoStates: [Bool] {
        didSet { UserDefaults.standard.set(groupTodoStates, forKey: "groupTodoStates") }
    }

    /// 第 index 組是否啟用待辦（越界視為未啟用）。
    func isGroupTodoEnabled(_ index: Int) -> Bool {
        guard index >= 0, index < groupTodoStates.count else { return false }
        return groupTodoStates[index]
    }

    /// 設定第 index 組的待辦開關。開啟待辦會自動關掉同組的報時（兩者互斥）。
    func setGroupTodoEnabled(_ index: Int, _ enabled: Bool) {
        setGroupTodoEnabledRaw(index, enabled)
        if enabled, index >= 0, index < Self.maxGroups {
            var arr = groupChimeStates
            while arr.count < Self.maxGroups { arr.append(false) }
            arr[index] = false
            groupChimeStates = arr
        }
    }

    /// 只寫待辦狀態、不連動報時（內部用，避免互斥連動互相遞迴）。
    private func setGroupTodoEnabledRaw(_ index: Int, _ enabled: Bool) {
        guard index >= 0, index < Self.maxGroups else { return }
        var arr = groupTodoStates
        while arr.count < Self.maxGroups { arr.append(false) }
        arr[index] = enabled
        groupTodoStates = arr
    }

    /// 響鈴閘（firing gate）：某顆鬧鐘的「群組」是否允許它響。規則：
    ///   1. 沒啟用分組 → 一律允許（維持單一群組的舊行為）。
    ///   2. 群組索引超出目前 groupCount（被「縮小數量」隱藏）→ 不響。
    ///   3. 該組被首頁橫幅關掉（groupActiveStates[idx] == false）→ 不響。
    /// **nonisolated + 直接讀 UserDefaults**，讓 AlarmScheduler / AlarmKitService（可能不在 main actor）
    /// 也能在排程決策時呼叫。注意這是「群組層」的閘，鬧鐘本身的 `isEnabled` 仍要另外判斷。
    nonisolated static func groupAllowsFiring(_ groupIndex: Int) -> Bool {
        let d = UserDefaults.standard
        let enabled = d.object(forKey: "groupEnabled") as? Bool ?? false
        guard enabled else { return true }
        let count = min(max(d.object(forKey: "groupCount") as? Int ?? 1, 1), maxGroups)
        let idx = min(max(groupIndex, 0), maxGroups - 1)
        guard idx < count else { return false }
        let active = (d.array(forKey: "groupActiveStates") as? [Bool]) ?? []
        return idx < active.count ? active[idx] : true
    }

    /// 目前實際生效的群組數：未啟用分組時固定為 1（只有群組 A）。
    var effectiveGroupCount: Int { groupEnabled ? min(max(groupCount, 1), Self.maxGroups) : 1 }

    /// 群組顯示名稱：使用者改過名 → 用自訂名；否則回在地化預設「群組 A」/「Group A」。
    func groupDisplayName(_ index: Int) -> String {
        guard index >= 0, index < Self.maxGroups else { return "" }
        let custom = (index < groupNames.count ? groupNames[index] : "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        let letter = String(Character(UnicodeScalar(UInt8(65 + index))))   // A, B, C, D, E
        return L("group_default_prefix") + " " + letter         // 群組 A / Group A
    }

    /// 綁定到第 index 個群組名稱輸入框（給 SettingsView 的 TextField 用）。
    func groupNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < self.groupNames.count ? self.groupNames[index] : "" },
            set: { newValue in
                guard index >= 0, index < Self.maxGroups else { return }
                var names = self.groupNames
                while names.count < Self.maxGroups { names.append("") }
                names[index] = newValue
                self.groupNames = names
            }
        )
    }

    // MARK: - 自訂向日葵花心照片（全 app 共用一張）

    /// 已裁切好的花心照片（已是正方形，SunflowerAvatar 會再 clip 成圓）。開機載入一次後常駐記憶體，
    /// 寫入時同步更新，避免吉祥物 24fps 重繪時反覆讀檔。
    @Published private(set) var flowerImage: UIImage?

    var hasFlowerImage: Bool { flowerImage != nil }

    /// 花心照片在 Documents 的固定位置（全 app 一張，覆寫即可）。
    static var flowerImageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mascot_flower_center.jpg")
    }

    static func loadFlowerImageFromDisk() -> UIImage? {
        let url = flowerImageURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 花心照片儲存上限邊長（px）。花心在畫面上最大也才 ~132px，512 已綽綽有餘，存全解析度只是
    /// 白佔磁碟 + 常駐記憶體（flowerImage 整個 app 生命週期持有）。
    static let flowerImageMaxDimension: CGFloat = 512

    /// 存下使用者裁切好的花心照片（已套用拖曳/縮放的正方形圖），同步更新記憶體中的 flowerImage。
    /// 存檔前先縮到 ≤512px：避免一張數 MB 的原圖既佔磁碟、又常駐記憶體（mascot 24fps 重繪會反覆取用）。
    func saveFlowerImage(_ image: UIImage) {
        let thumb = Self.downscaled(image, maxDimension: Self.flowerImageMaxDimension)
        if let data = thumb.jpegData(compressionQuality: 0.9) {
            try? data.write(to: Self.flowerImageURL, options: .atomic)
        }
        flowerImage = thumb
    }

    /// 等比例縮圖到最長邊 ≤ maxDimension（已夠小就原樣回傳）。輸出 scale=1 → 512 就是 512 實際像素，
    /// 不會再乘上裝置 @3x 把記憶體膨脹回去。
    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 移除自訂花心照片（SunflowerAvatar 會回到預設的種子花心）。
    func clearFlowerImage() {
        try? FileManager.default.removeItem(at: Self.flowerImageURL)
        flowerImage = nil
    }

    @Published private(set) var parentalUnlockUntil: Date? {
        didSet {
            let timestamp = parentalUnlockUntil?.timeIntervalSince1970 ?? 0
            UserDefaults.standard.set(timestamp, forKey: "parentalUnlockUntil")
        }
    }

    func beginParentalUnlockWindow() {
        parentalUnlockUntil = Date().addingTimeInterval(Double(parentalUnlockDurationMinutes * 60))
    }

    /// End the temporary unlock immediately ("立即上鎖") — next Settings / New Alarm re-shows the gate.
    func endParentalUnlockWindow() {
        parentalUnlockUntil = nil
    }

    func clearExpiredParentalUnlockIfNeeded(referenceDate: Date = .now) {
        if let unlockedUntil = parentalUnlockUntil, unlockedUntil <= referenceDate {
            parentalUnlockUntil = nil
        }
    }

    func isParentalGateUnlocked(referenceDate: Date = .now) -> Bool {
        clearExpiredParentalUnlockIfNeeded(referenceDate: referenceDate)
        return remainingParentalUnlockSeconds(referenceDate: referenceDate) > 0
    }

    func remainingParentalUnlockSeconds(referenceDate: Date = .now) -> Int {
        guard let unlockedUntil = parentalUnlockUntil else { return 0 }
        return max(0, Int(unlockedUntil.timeIntervalSince(referenceDate)))
    }
}
