import SwiftUI

struct EmojiFireworksOverlay: View {
    @Binding var isActive: Bool
    let startPointGlobal: CGPoint

    @State private var particles: [Particle] = []
    @State private var startLocal: CGPoint = .zero
    @State private var time: Double = 0

    private let duration: Double = 3.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isActive = false }

                ForEach(particles) { p in
                    Text(p.emoji)
                        .font(.system(size: p.size))
                        .position(position(for: p, in: geo.size))
                        .rotationEffect(.degrees(rotation(for: p)))
                        .scaleEffect(scale(for: p))
                        .opacity(opacity(for: p))
                }
            }
            .onAppear {
                // Convert global start point to local coordinates
                let origin = geo.frame(in: .global).origin
                startLocal = CGPoint(x: startPointGlobal.x - origin.x, y: startPointGlobal.y - origin.y)
                spawnParticles(in: geo.size)
                animate()
            }
            .onChange(of: isActive) { _, newValue in
                if newValue == false { particles.removeAll() }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Animation helpers
    private func animate() {
        time = 0
        withAnimation(.linear(duration: duration)) {
            time = duration
        }
        // Auto stop after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            isActive = false
        }
    }

    private func spawnParticles(in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let emojis = ["🏆", "🎉", "✨", "🔥", "🏅"]
        var created: [Particle] = []
        let count = 28
        for i in 0..<count {
            let emoji = emojis[i % emojis.count]
            let initialSpread: CGFloat = 24
            let angle = Double.random(in: 0..<(2 * .pi))
            let radius = CGFloat.random(in: 0...initialSpread)
            let start = CGPoint(x: startLocal.x + CGFloat(cos(angle)) * radius,
                                y: startLocal.y + CGFloat(sin(angle)) * radius)
            // Control points to create a nice arcing curve toward center
            let mid1 = CGPoint(
                x: (start.x + center.x) / 2 + CGFloat.random(in: -80...80),
                y: min(start.y, center.y) - CGFloat.random(in: 60...140)
            )
            let mid2 = CGPoint(
                x: (start.x + center.x) / 2 + CGFloat.random(in: -80...80),
                y: (start.y + center.y) / 2 + CGFloat.random(in: -40...40)
            )
            let particle = Particle(
                id: UUID(),
                emoji: emoji,
                start: start,
                c1: mid1,
                c2: mid2,
                end: center,
                size: CGFloat.random(in: 22...36),
                rotation: Double.random(in: -90...90),
                rotationDelta: Double.random(in: -120...120)
            )
            created.append(particle)
        }
        particles = created
    }

    private func position(for p: Particle, in size: CGSize) -> CGPoint {
        let t = CGFloat(max(0, min(1, time / duration)))
        // Cubic Bezier interpolation
        let x = cubicBezier(t, p.start.x, p.c1.x, p.c2.x, p.end.x)
        let y = cubicBezier(t, p.start.y, p.c1.y, p.c2.y, p.end.y)
        return CGPoint(x: x, y: y)
    }

    private func rotation(for p: Particle) -> Double {
        let t = max(0, min(1, time / duration))
        return p.rotation + p.rotationDelta * t
    }

    private func scale(for p: Particle) -> CGFloat {
        let t = CGFloat(max(0, min(1, time / duration)))
        // Slight pop then settle smaller
        return CGFloat(1.0 + 0.3 * sin(t * .pi) - 0.2 * t)
    }

    private func opacity(for p: Particle) -> Double {
        let t = max(0, min(1, time / duration))
        // Fade out toward the end
        return Double(1.0 - max(0, t - 0.6) / 0.4)
    }

    private func cubicBezier(_ t: CGFloat, _ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat, _ p3: CGFloat) -> CGFloat {
        let t1: CGFloat = (1 - t)
        let a: CGFloat = t1 * t1 * t1
        let b: CGFloat = 3 * t1 * t1 * t
        let c: CGFloat = 3 * t1 * t * t
        let d: CGFloat = t * t * t
        return a * p0 + b * p1 + c * p2 + d * p3
    }

    struct Particle: Identifiable {
        let id: UUID
        let emoji: String
        let start: CGPoint
        let c1: CGPoint
        let c2: CGPoint
        let end: CGPoint
        let size: CGFloat
        let rotation: Double
        let rotationDelta: Double
    }
}

