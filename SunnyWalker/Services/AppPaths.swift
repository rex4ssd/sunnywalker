// SunnyWalker — AppPaths.swift  |  全 app 檔案落點的唯一正本
//
// 為什麼要有這個檔：`Documents/Recordings/<name>.m4a` 與 `Library/Sounds/<file>.caf` 這兩條路徑
// 原本散在 11 個地方各拼一次（Alarm.ringtoneURL、RecordingView、AlarmEditorView 試聽、
// TodoBadgesView、VoiceClipRecorderSheet、BackgroundListeningManager、AudioImporter、
// AlarmSoundExporter ×2、ChimeSoundComposer、AlarmScheduler…）。拼法一致純屬運氣——
// 少一個 `isDirectory:`、多一個副檔名，就是「試聽有聲、真的響時沒聲」。集中到這裡，
// 之後要搬到 App Group（家族 app 互傳鬧鐘）也只改一處。
//
// ⚠️ 兩個目錄都不能改名：既有用戶的錄音檔都在 Recordings，iOS 只從 Library/Sounds 讀自訂通知音。

import Foundation

enum AppPaths {

    /// 家長錄音（m4a）落點：`Documents/Recordings/`。
    nonisolated static var recordingsDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    /// `Documents/Recordings/<name>.m4a`（`name` 不含副檔名）。
    nonisolated static func recordingURL(named name: String) -> URL {
        recordingsDirectory.appendingPathComponent("\(name).m4a")
    }

    /// 錄音檔是否存在（空字串一律 false）。
    nonisolated static func recordingExists(named name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: recordingURL(named: name).path)
    }

    /// iOS 唯一會讀「自訂鬧鐘／通知音」的容器目錄：`Library/Sounds/`。
    /// 呼叫 `ensureSoundsDirectory()` 可順便建立。
    nonisolated static var soundsDirectory: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// `Library/Sounds/<fileName>`（fileName 含副檔名，例 `alarm_xxx_1700000000.caf`）。
    nonisolated static func soundURL(named fileName: String) -> URL {
        soundsDirectory.appendingPathComponent(fileName)
    }

    /// 建好 Library/Sounds（已存在時 no-op）並回傳它。
    @discardableResult
    nonisolated static func ensureSoundsDirectory() -> URL {
        let dir = soundsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
