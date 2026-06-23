// SunnyWalker — TodoPlayRecord.swift  |  待辦語音提醒的「兒童有沒有聽」紀錄
//
// 每當兒童在主頁長按待辦圖示、播放了該則提醒語音，就寫一筆紀錄。家長在「待辦紀錄」頁可看到
// 哪一則待辦在什麼時候被聽過 —— 用來確認孩子有沒有去看當天的注意事項。

import SwiftData
import Foundation

@Model
final class TodoPlayRecord {
    @Attribute(.unique) var id: UUID
    /// 對應的待辦鬧鐘 id。
    var todoID: UUID
    /// 當下的待辦標籤（冗餘存一份，待辦被刪後紀錄仍可讀）。
    var todoLabel: String
    /// 兒童按下播放的時間。
    var playedAt: Date
    /// 該則待辦當天排定的時刻（顯示用：讓家長知道是哪一個時段的提醒）。
    var scheduledHour: Int
    var scheduledMinute: Int

    init(todoID: UUID, todoLabel: String, playedAt: Date = .now,
         scheduledHour: Int, scheduledMinute: Int) {
        self.id = UUID()
        self.todoID = todoID
        self.todoLabel = todoLabel
        self.playedAt = playedAt
        self.scheduledHour = scheduledHour
        self.scheduledMinute = scheduledMinute
    }
}
