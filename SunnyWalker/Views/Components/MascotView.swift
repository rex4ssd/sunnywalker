// SunnyWalker — MascotView.swift
// Drop-in replacement for SunnyAvatar() that respects the user's mascot theme setting.
// Use MascotView() everywhere instead of SunnyAvatar() directly.

import SwiftUI

struct MascotView: View {
    /// When true, tapping the mascot plays a cheerful greeting + a little bounce. Off by default so
    /// the mascot on the recording screens never steals the audio session (they use .playAndRecord).
    var tappable: Bool = false
    /// false ＝ 暫停 24fps 呼吸／眨眼（首頁被 sheet 蓋住時省下 GPU，讓上面的清單捲得順）。
    var animated: Bool = true
    var scene: DaytimeScene? = nil
    /// 多人鬧鐘：覆寫要顯示的吉祥物（首頁每個群組各自的吉祥物）。nil → 用全域 settings.mascotTheme。
    var themeOverride: MascotTheme? = nil

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false

    /// 實際顯示的吉祥物：優先用 themeOverride（群組指定），否則全域設定。
    private var effectiveTheme: MascotTheme { themeOverride ?? settings.mascotTheme }

    var body: some View {
        if tappable {
            livingAvatar
                .scaleEffect(bounce ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: bounce)
                .contentShape(Rectangle())
                .onTapGesture { greet() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("點一下，吉祥物會跟你打招呼"))
        } else {
            livingAvatar
        }
    }

    private var effectiveScene: DaytimeScene {
        scene ?? DaytimeScene.current(hour: Calendar.current.component(.hour, from: Date()))
    }

    private var livingAvatar: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion || !animated)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let pace = effectiveScene == .dusk || effectiveScene == .night ? 0.72 : 1.0
            let breath = reduceMotion ? 1.0 : 1.0 + sin(t * .pi / 2 * pace) * 0.018
            let sleepyNod = effectiveScene == .night && !reduceMotion ? sin(t * 1.1) * 2.2 : 0
            // Drive blinking from this shared timeline so child avatar state cannot be reset by
            // TimelineView redraws. A 0.42s closed phase makes the hand-drawn arc clearly visible.
            let blinkPhase = t.truncatingRemainder(dividingBy: 3.2)
            let forceBlink = !reduceMotion && blinkPhase < 0.42

            avatar(forceBlink: forceBlink)
                .scaleEffect(x: 1, y: breath, anchor: .bottom)
                .rotationEffect(.degrees(sleepyNod), anchor: .bottom)
                .saturation(effectiveScene == .night ? 0.72 : 1)
                .brightness(effectiveScene == .night ? -0.12 : effectiveScene == .dusk ? -0.03 : 0)
                .overlay(alignment: .topTrailing) {
                    if effectiveScene == .night && !reduceMotion {
                        sleepyMarks(time: t)
                    }
                }
        }
    }

    private func sleepyMarks(time: TimeInterval) -> some View {
        let phase = time.truncatingRemainder(dividingBy: 4.4) / 4.4
        return Text("z")
            .font(SunnyFonts.title(18))
            .foregroundStyle(SunnyColors.starGold)
            .offset(x: CGFloat(8 + phase * 12), y: CGFloat(-8 - phase * 28))
            .opacity(sin(phase * .pi))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func avatar(forceBlink: Bool) -> some View {
        switch effectiveTheme {
        case .sunnyAlarm: SunnyAlarmAvatar(forceBlink: forceBlink)
        case .sunny:   SunnyAvatar(forceBlink: forceBlink)
        case .giraffe: GiraffeAvatar(forceBlink: forceBlink)
        case .bunny:   BunnyAvatar(forceBlink: forceBlink)
        case .bear:    BearAvatar(forceBlink: forceBlink)
        case .flower:  SunflowerAvatar(forceBlink: forceBlink)
        }
    }

    private func greet() {
        MascotVoice.shared.playRandomGreeting()
        bounce = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { bounce = false }
    }
}

// MARK: - MascotVoice (tap-to-greet playback)

/// Plays a random bundled greeting clip when the mascot is tapped. Clips are produced by
/// `Scripts/generate_mascot_voices.command` and must be added to the app target, named
/// `mascot_greet_*.m4a` (e.g. `mascot_greet_01.m4a`). No-ops gracefully if none are bundled yet,
/// so the tap is safe to ship before the audio exists.
@MainActor
final class MascotVoice {
    static let shared = MascotVoice()
    private let player = AudioPlayer()
    private var lastIndex = -1

    private lazy var clips: [URL] = {
        var urls: [URL] = []
        for sub in [nil, "MascotSounds"] as [String?] {
            for ext in ["m4a", "caf", "wav", "aiff"] {
                let found = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: sub) ?? []
                urls += found.filter { $0.lastPathComponent.lowercased().hasPrefix("mascot_greet") }
            }
        }
        // de-dup by path, stable order so indices are predictable
        let unique = Array(Set(urls.map(\.path))).sorted().map { URL(fileURLWithPath: $0) }
        return unique
    }()

    /// Play a random greeting, avoiding an immediate repeat of the last one.
    func playRandomGreeting() {
        guard !clips.isEmpty else {
            print("🔊 MascotVoice: 沒有 mascot_greet_*.m4a — 先跑 Scripts/generate_mascot_voices.command，再把產生的檔案加進 app target。")
            return
        }
        var idx = Int.random(in: 0..<clips.count)
        if clips.count > 1 && idx == lastIndex { idx = (idx + 1) % clips.count }
        lastIndex = idx
        player.play(url: clips[idx], loop: false)
    }
}

// MARK: - SunflowerAvatar (custom mascot: a sunflower whose centre is the user's photo)

/// 自訂向日葵吉祥物：金色花瓣環 + 花心放使用者裁切好的照片（全 app 共用一張，存在
/// AppSettings.flowerImage）。沒有照片時用預設種子花心。沒有眼睛，breath/夜間效果由 MascotView 套用。
private struct SunflowerAvatar: View {
    var forceBlink = false   // 介面相容用：向日葵沒有眼睛，這個參數不使用
    @ObservedObject private var settings = AppSettings.shared

    private let petalGold = SunnyColors.wheatGold
    private let petalDeep = SunnyColors.lanternOrange
    private let seed = Color(red: 0.45, green: 0.30, blue: 0.16)

    var body: some View {
        ZStack {
            petals
            centerDisc
        }
        .frame(width: 132, height: 150)
        .accessibilityLabel(Text("向日葵"))
    }

    private var petals: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { i in
                Ellipse()
                    .fill(LinearGradient(colors: [petalGold, petalDeep],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 46)
                    .offset(y: -42)
                    .rotationEffect(.degrees(Double(i) / 16 * 360))
            }
        }
    }

    private var centerDisc: some View {
        ZStack {
            Circle().fill(seed.opacity(0.92)).frame(width: 86, height: 86)
            Group {
                if let img = settings.flowerImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    seedPattern
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())
            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: 3)
                .frame(width: 79, height: 79)
        }
    }

    // 預設花心：同心圓點點，像真的向日葵種子。
    private var seedPattern: some View {
        ZStack {
            Circle().fill(seed)
            ForEach(0..<3, id: \.self) { ring in
                let count = 8 + ring * 5
                ForEach(Array(0..<count), id: \.self) { i in
                    Circle()
                        .fill(Color.black.opacity(0.22))
                        .frame(width: 4, height: 4)
                        .offset(y: -CGFloat(9 + ring * 11))
                        .rotationEffect(.degrees(Double(i) / Double(count) * 360))
                }
            }
        }
    }
}

// MARK: - MascotThumb (compact mascot cell for pickers)

/// 小尺寸吉祥物縮圖，給設定頁的吉祥物選擇器用。內建吉祥物用 SF 圖示；向日葵若已設定照片則顯示
/// 圓形照片縮圖，否則顯示花朵圖示。
struct MascotThumb: View {
    let theme: MascotTheme
    var size: CGFloat = 34

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            if theme == .flower, let img = settings.flowerImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(systemName: theme.icon)
                    .font(.system(size: size * 0.52))
                    .foregroundStyle(SunnyColors.forestDeep)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(LocalizedStringKey(theme.displayName)))
    }
}

// MARK: - SunnyAlarmAvatar (app-icon mascot: a smiling sun-faced alarm clock with a mic)

/// Vector mascot that echoes the app icon — a golden sun whose face is an alarm clock, with two
/// blue bells + handle on top, rosy cheeks, clock ticks, little blue feet, and a tiny microphone.
/// Built from primitive shapes (same approach as the other avatars) so it scales crisply and needs
/// no asset. Blinks on a timer; the bells give a gentle idle "ring" wiggle.
private struct SunnyAlarmAvatar: View {
    var forceBlink = false
    @State private var isBlinking = false
    @State private var ring = false
    private let blinkTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    private let ringTimer  = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    // Palette (theme-aligned)
    private let gold     = SunnyColors.wheatGold
    private let goldDeep = SunnyColors.lanternOrange
    private let cream    = Color(red: 0.99, green: 0.93, blue: 0.72)
    private let blue     = SunnyColors.skyBlue
    private let blueDeep = Color(red: 0.42, green: 0.66, blue: 0.80)
    private let cheek    = Color(red: 0.97, green: 0.69, blue: 0.66)
    private let ink      = SunnyColors.nightIndigo

    var body: some View {
        ZStack {
            sunPetals
            bells
            clockBody
            tickMarks
            face
            microphone
            feet
        }
        .frame(width: 132, height: 150)
        .accessibilityLabel("小鬧晴")
        .onReceive(blinkTimer) { _ in
            withAnimation(.easeIn(duration: 0.07)) { isBlinking = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeOut(duration: 0.07)) { isBlinking = false }
            }
        }
        .onReceive(ringTimer) { _ in
            withAnimation(.easeInOut(duration: 0.12).repeatCount(6, autoreverses: true)) {
                ring.toggle()
            }
        }
    }

    // 12 rounded sun petals radiating behind the clock.
    private var sunPetals: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(gold)
                    .frame(width: 17, height: 28)
                    .offset(y: -50)
                    .rotationEffect(.degrees(Double(i) / 12 * 360))
            }
        }
        .offset(y: 2)
    }

    // Two bells + an arc handle peeking above the clock; wiggles on the ring timer.
    private var bells: some View {
        ZStack {
            // handle (top half-circle bridging the bells)
            Circle()
                .trim(from: 0.5, to: 1.0)
                .stroke(blueDeep, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 60, height: 44)
                .offset(y: -58)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse()
                    .fill(blue)
                    .frame(width: 30, height: 26)
                    .overlay(
                        Ellipse().fill(Color.white.opacity(0.35))
                            .frame(width: 12, height: 9).offset(x: -4, y: -5)
                    )
                    .offset(x: 30 * side, y: -56)
                    .rotationEffect(.degrees(ring ? 4 * side : 0), anchor: .bottom)
            }
        }
    }

    private var clockBody: some View {
        ZStack {
            Circle().fill(goldDeep.opacity(0.55)).frame(width: 104, height: 104).offset(y: 2)
            Circle().fill(gold).frame(width: 96, height: 96)
            Circle().fill(cream).frame(width: 80, height: 80)
        }
    }

    private var tickMarks: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(blue.opacity(0.85))
                    .frame(width: 3, height: 7)
                    .offset(y: -33)
                    .rotationEffect(.degrees(Double(i) / 12 * 360))
            }
        }
    }

    private var face: some View {
        ZStack {
            HStack(spacing: 20) {
                eye
                eye
            }
            .offset(y: -6)

            HStack(spacing: 30) {
                Circle().fill(cheek).frame(width: 13, height: 13)
                Circle().fill(cheek).frame(width: 13, height: 13)
            }
            .offset(y: 7)

            // smile (bottom arc)
            Circle()
                .trim(from: 0.10, to: 0.40)
                .stroke(ink.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 26, height: 22)
                .offset(y: 11)
        }
    }

    @ViewBuilder
    private var eye: some View {
        if isBlinking || forceBlink {
            ClosedEye(color: ink.opacity(0.86), width: 14, height: 8, lineWidth: 2.4)
        } else {
            Capsule()
                .fill(ink)
                .frame(width: 11, height: 13)
                .overlay(
                Circle().fill(Color.white.opacity(0.9))
                    .frame(width: 3.5, height: 3.5)
                    .offset(x: 2, y: -3)
                )
        }
    }

    // Tiny mic held to the lower-right — the icon's signature prop.
    private var microphone: some View {
        ZStack {
            Capsule().fill(SunnyColors.sunnyGray.opacity(0.85))
                .frame(width: 7, height: 18)
            Circle().fill(SunnyColors.sunnyGray)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(blueDeep, lineWidth: 2))
                .offset(y: -11)
        }
        .rotationEffect(.degrees(28))
        .offset(x: 44, y: 30)
    }

    private var feet: some View {
        HStack(spacing: 26) {
            foot
            foot
        }
        .offset(y: 62)
    }

    private var foot: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(blue)
            .frame(width: 20, height: 14)
    }
}

private struct BunnyAvatar: View {
    var forceBlink = false
    @State private var isBlinking = false
    private let blinkTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.94, green: 0.90, blue: 0.98))
                .frame(width: 98, height: 116)

            Ellipse()
                .fill(Color.white.opacity(0.9))
                .frame(width: 58, height: 66)
                .offset(y: 16)

            HStack(spacing: 24) {
                bunnyEar
                bunnyEar
            }
            .offset(y: -76)

            HStack(spacing: 18) {
                eye
                eye
            }
            .offset(y: -14)

            Circle()
                .fill(Color(red: 0.98, green: 0.73, blue: 0.80))
                .frame(width: 10, height: 10)
                .offset(y: 4)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.75))
                .frame(width: 18, height: 3)
                .offset(y: 18)
        }
        .frame(width: 120, height: 150)
        .accessibilityLabel("小兔子")
        .onReceive(blinkTimer) { _ in
            withAnimation(.easeIn(duration: 0.07)) { isBlinking = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeOut(duration: 0.07)) { isBlinking = false }
            }
        }
    }

    @ViewBuilder
    private var eye: some View {
        if isBlinking || forceBlink {
            ClosedEye(color: Color.black.opacity(0.72), width: 15, height: 8, lineWidth: 2.2)
        } else {
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .overlay(
                Circle()
                    .fill(Color.black)
                    .frame(width: 7, height: 7)
                )
        }
    }

    private var bunnyEar: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(red: 0.94, green: 0.90, blue: 0.98))
            .frame(width: 20, height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.98, green: 0.78, blue: 0.85))
                    .frame(width: 10, height: 36)
            )
    }
}

private struct BearAvatar: View {
    var forceBlink = false
    @State private var isBlinking = false
    private let blinkTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.62, green: 0.45, blue: 0.32))
                .frame(width: 100, height: 100)

            HStack(spacing: 56) {
                Circle()
                    .fill(Color(red: 0.62, green: 0.45, blue: 0.32))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(Color(red: 0.62, green: 0.45, blue: 0.32))
                    .frame(width: 28, height: 28)
            }
            .offset(y: -42)

            HStack(spacing: 56) {
                Circle()
                    .fill(Color(red: 0.83, green: 0.69, blue: 0.57))
                    .frame(width: 14, height: 14)
                Circle()
                    .fill(Color(red: 0.83, green: 0.69, blue: 0.57))
                    .frame(width: 14, height: 14)
            }
            .offset(y: -42)

            Ellipse()
                .fill(Color(red: 0.88, green: 0.75, blue: 0.63))
                .frame(width: 52, height: 38)
                .offset(y: 20)

            HStack(spacing: 18) {
                eye
                eye
            }
            .offset(y: -4)

            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: 9, height: 9)
                .offset(y: 14)
        }
        .frame(width: 120, height: 140)
        .accessibilityLabel("小熊")
        .onReceive(blinkTimer) { _ in
            withAnimation(.easeIn(duration: 0.07)) { isBlinking = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                withAnimation(.easeOut(duration: 0.07)) { isBlinking = false }
            }
        }
    }

    @ViewBuilder
    private var eye: some View {
        if isBlinking || forceBlink {
            ClosedEye(color: Color.black.opacity(0.78), width: 15, height: 8, lineWidth: 2.2)
        } else {
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .overlay(
                Circle()
                    .fill(Color.black)
                    .frame(width: 7, height: 7)
                )
        }
    }
}

/// A soft downward arc used by every mascot so a blink reads clearly as a hand-drawn closed eye.
struct ClosedEye: View {
    let color: Color
    var width: CGFloat = 16
    var height: CGFloat = 8
    var lineWidth: CGFloat = 2.2

    var body: some View {
        ClosedEyeShape()
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: width, height: height)
    }
}

private struct ClosedEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.maxY)
            )
        }
    }
}

#Preview {
    VStack(spacing: 32) {
        MascotView()
        Text("吉祥物會隨設定切換")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(40)
    .background(SunnyColors.skyBlue)
}
