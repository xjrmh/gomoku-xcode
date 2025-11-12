//
//  HintPulse.swift
//  gomoku
//
//  Created by Li Zheng on 11/11/25.
//

import SwiftUI

struct HintPulse: View {
    let color: Color = .red
    @State private var animate = false

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 3)
            .background(Circle().fill(color.opacity(0.20)))
            .scaleEffect(animate ? 1.2 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animate)
            .onAppear { animate = true }
    }
}
