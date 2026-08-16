import SwiftUI

extension Color {
    static let ink = Color(red: 11 / 255, green: 11 / 255, blue: 10 / 255)
    static let inkElevated = Color(red: 22 / 255, green: 22 / 255, blue: 20 / 255)
    static let inkHighest = Color(red: 34 / 255, green: 33 / 255, blue: 28 / 255)
    static let cream = Color(red: 244 / 255, green: 239 / 255, blue: 227 / 255)
    static let creamMuted = Color(red: 201 / 255, green: 195 / 255, blue: 180 / 255)
    static let cheddar = Color(red: 230 / 255, green: 184 / 255, blue: 74 / 255)
    static let cheddarDeep = Color(red: 196 / 255, green: 146 / 255, blue: 26 / 255)
    static let cheddarSoft = Color(red: 61 / 255, green: 50 / 255, blue: 24 / 255)
    static let liveCoral = Color(red: 1, green: 90 / 255, blue: 60 / 255)
    static let adultClay = Color(red: 232 / 255, green: 160 / 255, blue: 122 / 255)
    static let okSage = Color(red: 159 / 255, green: 203 / 255, blue: 122 / 255)
    static let paper = Color(red: 246 / 255, green: 241 / 255, blue: 230 / 255)
    static let paperElevated = Color(red: 1, green: 252 / 255, blue: 246 / 255)
    static let inkOnPaper = Color(red: 26 / 255, green: 25 / 255, blue: 22 / 255)
    static let mutedOnPaper = Color(red: 111 / 255, green: 106 / 255, blue: 94 / 255)
    static let cheddarSoftLight = Color(red: 243 / 255, green: 226 / 255, blue: 181 / 255)
    static let surfaceHighLight = Color(red: 243 / 255, green: 235 / 255, blue: 216 / 255)
    static let surfaceHighestLight = Color(red: 237 / 255, green: 228 / 255, blue: 206 / 255)
}

struct CrackerTheme {
    static func background(_ scheme: ColorScheme) -> Color {
        .ink
    }

    static func onBackground(_ scheme: ColorScheme) -> Color {
        .cream
    }

    static func muted(_ scheme: ColorScheme) -> Color {
        .creamMuted
    }

    static func card(_ scheme: ColorScheme) -> Color {
        .inkElevated
    }

    static func cardHigh(_ scheme: ColorScheme) -> Color {
        .inkHighest
    }

    static func wash(_ scheme: ColorScheme) -> Color {
        .ink
    }

    static func line(_ scheme: ColorScheme) -> Color {
        Color.white.opacity(0.08)
    }
}
