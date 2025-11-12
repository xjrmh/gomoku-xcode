//
//  Theme.swift
//  gomoku
//
//  Created by Li Zheng on 11/11/25.
//

import SwiftUI

struct GomokuTheme: Equatable {
    var name: String
    var boardWood: Color
    var cellLight: Color
    var cellDark: Color
    var stoneBorder: Color
    var text: Color
    var chrome: Color
    var buttonBG: Color
    var buttonBorder: Color
    var buttonShadow: Color

    static let classic = GomokuTheme(
        name: "Classic",
        boardWood: Color(hex: 0x8B4513),                    // matches CSS board background
        cellLight: Color(hex: 0xDEB887),                    // CSS .cell
        cellDark:  Color(hex: 0xD2A679),                    // CSS .cell.dark
        stoneBorder: Color(white: 0.6),
        text: Color(hex: 0x333333),
        chrome: Color(hex: 0xF8F8F8),
        buttonBG: Color(hex: 0xF9F9F9),
        buttonBorder: Color(hex: 0xE0E0E0),
        buttonShadow: Color.black.opacity(0.06)
    )

    static let night = GomokuTheme(
        name: "Night",
        boardWood: Color(hex: 0x3A2F2A),
        cellLight: Color(hex: 0x5E4B43),
        cellDark:  Color(hex: 0x4C3C36),
        stoneBorder: Color(white: 0.7),
        text: .white,
        chrome: Color(hex: 0x151515),
        buttonBG: Color(hex: 0x202020),
        buttonBorder: Color(hex: 0x2E2E2E),
        buttonShadow: Color.black.opacity(0.4)
    )
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8)  & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Safe convenience initializer for grayscale colors (works across iOS versions).
    init(white: Double, opacity: Double = 1.0) {
        self.init(.sRGB, red: white, green: white, blue: white, opacity: opacity)
    }
}
