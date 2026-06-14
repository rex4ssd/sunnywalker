// SunnyWalker — DaytimeScene.swift  |  Day 2  |  time-of-day scene enum (spec §3.4)

import SwiftUI

enum DaytimeScene: Equatable {
    case dawn    // 5–7  : pink sunrise, wheat field
    case morning // 7–11 : blue sky, forest
    case noon    // 11–15: bright blue, sunflower field
    case dusk    // 15–19: orange sunset, red lanterns
    case night   // 19–5 : deep indigo, stars

    static func current(hour: Int) -> DaytimeScene {
        switch hour {
        case 5..<7:   return .dawn
        case 7..<11:  return .morning
        case 11..<15: return .noon
        case 15..<19: return .dusk
        default:      return .night
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .dawn:
            return [SunnyColors.lanternOrange.opacity(0.78), SunnyColors.wheatGold.opacity(0.82), SunnyColors.cloudWhite]
        case .morning:
            return [SunnyColors.skyDeep, SunnyColors.skyBlue, SunnyColors.cloudWhite]
        case .noon:
            return [SunnyColors.skyDeep.opacity(0.9), SunnyColors.noonSky, SunnyColors.cloudWhite]
        case .dusk:
            return [Color(red: 0.88, green: 0.48, blue: 0.24), SunnyColors.lanternOrange, SunnyColors.wheatGold]
        case .night:
            return [Color(red: 0.14, green: 0.16, blue: 0.33), SunnyColors.nightIndigo, SunnyColors.nightDeep]
        }
    }

    var colorGrade: Color {
        switch self {
        case .night: return Color(red: 0.47, green: 0.55, blue: 0.82)
        case .dusk: return SunnyColors.lanternOrange
        default: return SunnyColors.wheatGold
        }
    }

    var colorGradeOpacity: Double {
        switch self {
        case .night: return 0.08
        case .dusk: return 0.10
        default: return 0.06
        }
    }

    var silhouetteColor: Color {
        switch self {
        case .dawn: return SunnyColors.forestDeep.opacity(0.55)
        case .morning, .noon: return SunnyColors.forestDeep.opacity(0.68)
        case .dusk: return SunnyColors.nightIndigo.opacity(0.55)
        case .night: return Color(red: 0.08, green: 0.11, blue: 0.24).opacity(0.88)
        }
    }

    var clockTextColor: Color {
        self == .night ? SunnyColors.starGold : SunnyColors.nightIndigo
    }
}
