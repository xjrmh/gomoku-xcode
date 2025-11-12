//
//  FireworksView.swift
//  gomoku
//
//  Created by Li Zheng on 11/11/25.
//

#if canImport(UIKit)
import SwiftUI
import UIKit
import QuartzCore

struct FireworksView: UIViewRepresentable {
    @Binding var isActive: Bool

    func makeUIView(context: Context) -> FireworksContainer { FireworksContainer() }
    func updateUIView(_ uiView: FireworksContainer, context: Context) { uiView.setActive(isActive) }
}

final class FireworksContainer: UIView {
    private let emitter = CAEmitterLayer()
    private let rocket  = CAEmitterCell()
    private let burst   = CAEmitterCell()
    private let spark   = CAEmitterCell()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.masksToBounds = true
        emitter.emitterShape = .line
        layer.addSublayer(emitter)
        configureCells()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -10)
        emitter.emitterSize = CGSize(width: bounds.size.width, height: 1)
    }

    private func configureCells() {
        rocket.birthRate = 0
        rocket.lifetime = 1.3
        rocket.velocity = 350
        rocket.velocityRange = 80
        rocket.yAcceleration = 150
        rocket.emissionRange = .pi / 8
        rocket.color = UIColor.white.cgColor

        burst.birthRate = 0
        burst.velocity = 0
        burst.scale = 2.5
        burst.lifetime = 0.35

        spark.birthRate = 0
        spark.lifetime = 1.5
        spark.velocity = 125
        spark.emissionRange = 2 * .pi
        spark.yAcceleration = 80
        spark.scale = 0.2
        spark.alphaSpeed = -0.7

        emitter.emitterCells = [rocket]
        rocket.emitterCells = [burst]
        burst.emitterCells = [spark]
    }

    func setActive(_ on: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rocket.birthRate = on ? 2 : 0
        burst.birthRate  = on ? 1 : 0
        spark.birthRate  = on ? 200 : 0
        CATransaction.commit()
    }
}
#else
import SwiftUI

struct FireworksView: View {
    @Binding var isActive: Bool
    var body: some View {
        // Fallback for platforms without UIKit
        Color.clear
    }
}
#endif
