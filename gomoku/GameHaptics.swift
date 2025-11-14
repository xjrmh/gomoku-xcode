//
//  GameHaptics.swift
//  gomoku
//
//  Created by AI Assistant on 11/14/25.
//

import Foundation
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

enum GameHaptics {
    static func stonePlacement() {
        #if os(iOS)
        // Simulate the feel of a real stone touching the board:
        // 1) A crisp contact (rigid), then 2) a softer settling tick shortly after.
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        rigid.prepare()
        rigid.impactOccurred(intensity: 0.9)

        let soft = UIImpactFeedbackGenerator(style: .soft)
        soft.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            soft.impactOccurred(intensity: 0.5)
        }
        #elseif os(macOS)
        if #available(macOS 13.0, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
        #else
        // Other platforms: no-op
        #endif
    }

    static func reset() {
        #if os(iOS)
        // A confident confirmation
        let notif = UINotificationFeedbackGenerator()
        notif.notificationOccurred(.success)
        #elseif os(macOS)
        if #available(macOS 13.0, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
        #endif
    }

    static func undo() {
        #if os(iOS)
        // A subtle two-step nudge to suggest stepping back
        let sel = UISelectionFeedbackGenerator()
        sel.selectionChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sel.selectionChanged()
        }
        #elseif os(macOS)
        if #available(macOS 13.0, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        #endif
    }

    static func hint() {
        #if os(iOS)
        // Gentle nudge indicating guidance
        let light = UIImpactFeedbackGenerator(style: .light)
        light.impactOccurred(intensity: 0.6)
        #elseif os(macOS)
        if #available(macOS 13.0, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
        #endif
    }

    static func modeSwitch() {
        #if os(iOS)
        // Simulate a short slide with a couple of selection ticks then a soft settle
        let sel = UISelectionFeedbackGenerator()
        sel.selectionChanged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sel.selectionChanged()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            let soft = UIImpactFeedbackGenerator(style: .soft)
            soft.impactOccurred(intensity: 0.6)
        }
        #elseif os(macOS)
        if #available(macOS 13.0, *) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
        #endif
    }
}
