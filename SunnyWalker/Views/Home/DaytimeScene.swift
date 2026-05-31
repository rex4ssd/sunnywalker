// SunnyWalker — DaytimeScene.swift  |  Day 2  |  time-of-day scene enum (spec §3.4)

import SwiftUI

enum DaytimeScene {
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
        case .dawn:    return [GhibliColors.lanternOrange, GhibliColors.wheatGold]
        case .morning: return [GhibliColors.skyBlue, GhibliColors.cloudWhite]
        case .noon:    return [GhibliColors.noonSky, GhibliColors.cloudWhite]
        case .dusk:    return [GhibliColors.lanternOrange.opacity(0.9), GhibliColors.wheatGold.opacity(0.7)]
        case .night:   return [GhibliColors.nightIndigo, GhibliColors.nightDeep]
        }
    }

    var clockTextColor: Color {
        self == .night ? GhibliColors.starGold : GhibliColors.nightIndigo
    }
}
