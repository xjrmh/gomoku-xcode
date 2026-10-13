import SwiftUI

/// Small vector pieces shared by the game board, previews, and exported boards.
enum ThemePieceDrawing {
    static func draw(context: inout GraphicsContext, rect: CGRect, player: Player, theme: BoardTheme) {
        guard theme != .standard, rect.width > 0, rect.height > 0 else { return }
        context.drawLayer { layer in
            layer.addFilter(.shadow(
                color: .black.opacity(0.22),
                radius: max(0.6, rect.width * 0.055),
                x: 0,
                y: max(0.5, rect.height * 0.045)
            ))
            let piece = PieceCanvas(context: layer, rect: rect.insetBy(dx: rect.width * 0.025, dy: rect.height * 0.025))
            let first = player == .black
            switch theme {
            case .standard: break
            case .halloween: first ? piece.pumpkin() : piece.ghost()
            case .christmas: first ? piece.tree() : piece.snowman()
            case .easter: first ? piece.egg() : piece.bunny()
            case .valentines: first ? piece.heart() : piece.letter()
            case .lunarNewYear: first ? piece.lantern() : piece.coin()
            case .space: first ? piece.moon() : piece.star()
            case .nature: first ? piece.leaf() : piece.flower()
            case .pets: first ? piece.cat() : piece.dog()
            case .ocean: first ? piece.shell() : piece.starfish()
            case .flatre: first ? piece.house() : piece.key()
            }
        }
    }
}

private struct PieceCanvas {
    let context: GraphicsContext
    let rect: CGRect

    private var ink: Color { Color(red: 0.13, green: 0.16, blue: 0.2) }
    private var cream: Color { Color(red: 1, green: 0.98, blue: 0.91) }
    private var orange: Color { Color(red: 0.97, green: 0.43, blue: 0.1) }
    private var gold: Color { Color(red: 1, green: 0.77, blue: 0.22) }
    private var green: Color { Color(red: 0.12, green: 0.44, blue: 0.3) }
    private var red: Color { Color(red: 0.86, green: 0.17, blue: 0.28) }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private func mapped(_ path: Path) -> Path {
        path.applying(CGAffineTransform(a: rect.width, b: 0, c: 0, d: rect.height, tx: rect.minX, ty: rect.minY))
    }

    private func path(_ draw: (inout Path) -> Void) -> Path {
        var path = Path()
        draw(&path)
        return path
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        path {
            guard let first = points.first else { return }
            $0.move(to: first)
            for point in points.dropFirst() { $0.addLine(to: point) }
            $0.closeSubpath()
        }
    }

    private func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height))
    }

    private func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat = 0) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
    }

    private func fill(_ shape: Path, _ color: Color, outlined: Bool = true) {
        let shape = mapped(shape)
        context.fill(shape, with: .color(color))
        if outlined {
            context.stroke(shape, with: .color(ink.opacity(0.45)), lineWidth: max(0.5, rect.width * 0.032))
        }
    }

    private func stroke(_ shape: Path, _ color: Color, width: CGFloat = 0.045) {
        context.stroke(mapped(shape), with: .color(color), style: StrokeStyle(
            lineWidth: max(0.45, rect.width * width), lineCap: .round, lineJoin: .round
        ))
    }

    private func eyes(y: CGFloat, left: CGFloat = 0.36, right: CGFloat = 0.64, size: CGFloat = 0.075) {
        fill(ellipse(left - size / 2, y - size / 2, size, size * 1.2), ink, outlined: false)
        fill(ellipse(right - size / 2, y - size / 2, size, size * 1.2), ink, outlined: false)
    }

    private func starShape(center: CGPoint, radius: CGFloat, inner: CGFloat, points: Int = 5, rotation: Double = -.pi / 2) -> Path {
        polygon((0..<(points * 2)).map { index in
            let angle = rotation + Double(index) * .pi / Double(points)
            let r = index.isMultiple(of: 2) ? radius : inner
            return point(center.x + CGFloat(cos(angle)) * r, center.y + CGFloat(sin(angle)) * r)
        })
    }

    private func heartShape(_ x: CGFloat = 0.08, _ y: CGFloat = 0.11, _ size: CGFloat = 0.84) -> Path {
        func p(_ a: CGFloat, _ b: CGFloat) -> CGPoint { point(x + a * size, y + b * size) }
        return path {
            $0.move(to: p(0.5, 0.94))
            $0.addCurve(to: p(0.06, 0.4), control1: p(0.34, 0.77), control2: p(0.06, 0.61))
            $0.addCurve(to: p(0.5, 0.2), control1: p(-0.03, 0.06), control2: p(0.33, -0.08))
            $0.addCurve(to: p(0.94, 0.4), control1: p(0.67, -0.08), control2: p(1.03, 0.06))
            $0.addCurve(to: p(0.5, 0.94), control1: p(0.94, 0.61), control2: p(0.66, 0.77))
            $0.closeSubpath()
        }
    }

    func pumpkin() {
        fill(box(0.44, 0.06, 0.15, 0.23, radius: 0.035), green)
        let body = path {
            $0.move(to: point(0.5, 0.24))
            $0.addCurve(to: point(0.07, 0.58), control1: point(0.19, 0.13), control2: point(0.03, 0.34))
            $0.addCurve(to: point(0.5, 0.93), control1: point(0.04, 0.91), control2: point(0.31, 1))
            $0.addCurve(to: point(0.93, 0.58), control1: point(0.69, 1), control2: point(0.96, 0.91))
            $0.addCurve(to: point(0.5, 0.24), control1: point(0.97, 0.34), control2: point(0.81, 0.13))
            $0.closeSubpath()
        }
        fill(body, orange)
        stroke(path {
            $0.move(to: point(0.38, 0.28))
            $0.addQuadCurve(to: point(0.38, 0.9), control: point(0.21, 0.59))
            $0.move(to: point(0.62, 0.28))
            $0.addQuadCurve(to: point(0.62, 0.9), control: point(0.79, 0.59))
        }, Color(red: 0.61, green: 0.24, blue: 0.08).opacity(0.5), width: 0.025)
        fill(polygon([point(0.24, 0.53), point(0.37, 0.42), point(0.41, 0.56)]), ink, outlined: false)
        fill(polygon([point(0.59, 0.56), point(0.63, 0.42), point(0.76, 0.53)]), ink, outlined: false)
        stroke(path {
            $0.move(to: point(0.3, 0.7))
            $0.addQuadCurve(to: point(0.7, 0.7), control: point(0.5, 0.87))
        }, ink, width: 0.055)
    }

    func ghost() {
        fill(path {
            $0.move(to: point(0.14, 0.88))
            $0.addLine(to: point(0.14, 0.44))
            $0.addCurve(to: point(0.86, 0.44), control1: point(0.14, -0.05), control2: point(0.86, -0.05))
            $0.addLine(to: point(0.86, 0.88))
            $0.addQuadCurve(to: point(0.68, 0.83), control: point(0.78, 1.01))
            $0.addQuadCurve(to: point(0.5, 0.92), control: point(0.6, 0.99))
            $0.addQuadCurve(to: point(0.32, 0.83), control: point(0.39, 0.99))
            $0.addQuadCurve(to: point(0.14, 0.88), control: point(0.2, 1.01))
            $0.closeSubpath()
        }, cream)
        eyes(y: 0.43, size: 0.11)
        fill(ellipse(0.455, 0.59, 0.09, 0.12), ink, outlined: false)
    }

    func tree() {
        fill(box(0.43, 0.73, 0.14, 0.23, radius: 0.02), Color(red: 0.45, green: 0.27, blue: 0.15))
        fill(polygon([
            point(0.5, 0.08), point(0.77, 0.39), point(0.64, 0.39),
            point(0.87, 0.65), point(0.71, 0.65), point(0.96, 0.88),
            point(0.04, 0.88), point(0.29, 0.65), point(0.13, 0.65),
            point(0.36, 0.39), point(0.23, 0.39)
        ]), green)
        fill(starShape(center: point(0.5, 0.14), radius: 0.14, inner: 0.064), gold)
        fill(ellipse(0.43, 0.42, 0.11, 0.11), red, outlined: false)
        fill(ellipse(0.62, 0.64, 0.11, 0.11), gold, outlined: false)
        fill(ellipse(0.25, 0.71, 0.11, 0.11), red, outlined: false)
    }

    func snowman() {
        fill(ellipse(0.13, 0.46, 0.74, 0.49), cream)
        fill(ellipse(0.25, 0.17, 0.5, 0.45), cream)
        fill(box(0.31, 0.04, 0.38, 0.22, radius: 0.025), ink)
        fill(box(0.2, 0.23, 0.6, 0.055, radius: 0.018), ink)
        fill(box(0.27, 0.51, 0.46, 0.1, radius: 0.035), red)
        fill(box(0.6, 0.54, 0.1, 0.22, radius: 0.025), red)
        eyes(y: 0.36, left: 0.4, right: 0.59, size: 0.052)
        fill(polygon([point(0.47, 0.41), point(0.7, 0.44), point(0.47, 0.47)]), orange, outlined: false)
        fill(ellipse(0.46, 0.66, 0.08, 0.08), ink, outlined: false)
        fill(ellipse(0.46, 0.8, 0.08, 0.08), ink, outlined: false)
    }

    func egg() {
        fill(path {
            $0.move(to: point(0.5, 0.06))
            $0.addCurve(to: point(0.89, 0.64), control1: point(0.68, 0.06), control2: point(0.89, 0.42))
            $0.addCurve(to: point(0.11, 0.64), control1: point(0.89, 1.07), control2: point(0.11, 1.07))
            $0.addCurve(to: point(0.5, 0.06), control1: point(0.11, 0.42), control2: point(0.32, 0.06))
            $0.closeSubpath()
        }, Color(red: 0.34, green: 0.32, blue: 0.73))
        stroke(path {
            $0.move(to: point(0.2, 0.52))
            $0.addLine(to: point(0.35, 0.61))
            $0.addLine(to: point(0.5, 0.52))
            $0.addLine(to: point(0.65, 0.61))
            $0.addLine(to: point(0.8, 0.52))
        }, cream, width: 0.085)
        fill(ellipse(0.44, 0.28, 0.12, 0.12), Color(red: 1, green: 0.69, blue: 0.78), outlined: false)
        fill(ellipse(0.32, 0.76, 0.1, 0.1), gold, outlined: false)
        fill(ellipse(0.59, 0.76, 0.1, 0.1), gold, outlined: false)
    }

    func bunny() {
        fill(ellipse(0.21, 0.03, 0.23, 0.6), cream)
        fill(ellipse(0.56, 0.03, 0.23, 0.6), cream)
        fill(ellipse(0.285, 0.11, 0.08, 0.34), Color(red: 0.96, green: 0.65, blue: 0.71), outlined: false)
        fill(ellipse(0.635, 0.11, 0.08, 0.34), Color(red: 0.96, green: 0.65, blue: 0.71), outlined: false)
        fill(ellipse(0.11, 0.38, 0.78, 0.57), cream)
        eyes(y: 0.61)
        fill(polygon([point(0.43, 0.73), point(0.57, 0.73), point(0.5, 0.82)]), red.opacity(0.75), outlined: false)
    }

    func heart() {
        fill(heartShape(), red)
        stroke(path {
            $0.move(to: point(0.21, 0.4))
            $0.addQuadCurve(to: point(0.33, 0.25), control: point(0.2, 0.27))
        }, .white.opacity(0.5), width: 0.065)
    }

    func letter() {
        fill(box(0.06, 0.19, 0.88, 0.63, radius: 0.065), cream)
        stroke(path {
            $0.move(to: point(0.1, 0.25))
            $0.addLine(to: point(0.5, 0.57))
            $0.addLine(to: point(0.9, 0.25))
            $0.move(to: point(0.1, 0.76))
            $0.addLine(to: point(0.36, 0.52))
            $0.move(to: point(0.9, 0.76))
            $0.addLine(to: point(0.64, 0.52))
        }, Color(red: 0.71, green: 0.53, blue: 0.46), width: 0.035)
        fill(heartShape(0.33, 0.38, 0.34), red, outlined: false)
    }

    func lantern() {
        stroke(path {
            $0.move(to: point(0.5, 0.02))
            $0.addLine(to: point(0.5, 0.2))
            $0.move(to: point(0.5, 0.79))
            $0.addLine(to: point(0.5, 0.97))
        }, gold, width: 0.08)
        fill(ellipse(0.13, 0.2, 0.74, 0.61), red)
        stroke(path {
            $0.move(to: point(0.39, 0.23))
            $0.addQuadCurve(to: point(0.39, 0.78), control: point(0.26, 0.5))
            $0.move(to: point(0.61, 0.23))
            $0.addQuadCurve(to: point(0.61, 0.78), control: point(0.74, 0.5))
        }, gold.opacity(0.72), width: 0.03)
        fill(box(0.29, 0.14, 0.42, 0.1, radius: 0.025), gold)
        fill(box(0.29, 0.76, 0.42, 0.09, radius: 0.025), gold)
    }

    func coin() {
        fill(ellipse(0.07, 0.07, 0.86, 0.86), gold)
        stroke(ellipse(0.17, 0.17, 0.66, 0.66), Color(red: 0.71, green: 0.42, blue: 0.08), width: 0.035)
        fill(box(0.37, 0.37, 0.26, 0.26, radius: 0.015), Color(red: 0.4, green: 0.29, blue: 0.17))
        stroke(path {
            $0.move(to: point(0.22, 0.4))
            $0.addQuadCurve(to: point(0.45, 0.21), control: point(0.27, 0.23))
        }, cream.opacity(0.8), width: 0.055)
    }

    func moon() {
        fill(path {
            $0.move(to: point(0.71, 0.06))
            $0.addCurve(to: point(0.76, 0.9), control1: point(-0.1, -0.03), control2: point(-0.1, 1.08))
            $0.addCurve(to: point(0.71, 0.06), control1: point(0.32, 0.7), control2: point(0.32, 0.28))
            $0.closeSubpath()
        }, Color(red: 0.24, green: 0.42, blue: 0.77))
        stroke(path {
            $0.move(to: point(0.32, 0.27))
            $0.addQuadCurve(to: point(0.24, 0.62), control: point(0.17, 0.43))
        }, Color(red: 0.66, green: 0.83, blue: 1).opacity(0.72), width: 0.055)
    }

    func star() {
        fill(starShape(center: point(0.5, 0.52), radius: 0.48, inner: 0.22), gold)
        stroke(path {
            $0.move(to: point(0.5, 0.2))
            $0.addLine(to: point(0.43, 0.4))
            $0.addLine(to: point(0.23, 0.43))
        }, cream.opacity(0.8), width: 0.055)
    }

    func leaf() {
        fill(path {
            $0.move(to: point(0.13, 0.87))
            $0.addCurve(to: point(0.89, 0.1), control1: point(-0.08, 0.2), control2: point(0.55, 0.03))
            $0.addCurve(to: point(0.13, 0.87), control1: point(0.96, 0.73), control2: point(0.53, 1.05))
            $0.closeSubpath()
        }, green)
        stroke(path {
            $0.move(to: point(0.1, 0.92))
            $0.addLine(to: point(0.73, 0.27))
            $0.move(to: point(0.36, 0.65))
            $0.addLine(to: point(0.3, 0.37))
            $0.move(to: point(0.52, 0.49))
            $0.addLine(to: point(0.76, 0.52))
        }, Color(red: 0.66, green: 0.83, blue: 0.4), width: 0.04)
    }

    func flower() {
        var petals = Path()
        for index in 0..<6 {
            let angle = Double(index) * .pi / 3
            let x = 0.5 + CGFloat(cos(angle)) * 0.25
            let y = 0.5 + CGFloat(sin(angle)) * 0.25
            petals.addEllipse(in: CGRect(x: x - 0.21, y: y - 0.21, width: 0.42, height: 0.42))
        }
        fill(petals, Color(red: 0.96, green: 0.64, blue: 0.76))
        fill(ellipse(0.34, 0.34, 0.32, 0.32), gold)
    }

    func cat() {
        fill(path {
            $0.move(to: point(0.16, 0.45))
            $0.addLine(to: point(0.15, 0.08))
            $0.addLine(to: point(0.38, 0.26))
            $0.addQuadCurve(to: point(0.62, 0.26), control: point(0.5, 0.21))
            $0.addLine(to: point(0.85, 0.08))
            $0.addLine(to: point(0.84, 0.45))
            $0.addCurve(to: point(0.16, 0.45), control1: point(1.11, 1.1), control2: point(-0.11, 1.1))
            $0.closeSubpath()
        }, Color(red: 0.31, green: 0.34, blue: 0.42))
        fill(polygon([point(0.2, 0.19), point(0.22, 0.38), point(0.33, 0.29)]), Color(red: 0.91, green: 0.57, blue: 0.66), outlined: false)
        fill(polygon([point(0.8, 0.19), point(0.78, 0.38), point(0.67, 0.29)]), Color(red: 0.91, green: 0.57, blue: 0.66), outlined: false)
        fill(ellipse(0.28, 0.49, 0.12, 0.09), gold, outlined: false)
        fill(ellipse(0.6, 0.49, 0.12, 0.09), gold, outlined: false)
        fill(polygon([point(0.44, 0.66), point(0.56, 0.66), point(0.5, 0.74)]), cream, outlined: false)
    }

    func dog() {
        let brown = Color(red: 0.54, green: 0.32, blue: 0.19)
        fill(ellipse(0.04, 0.22, 0.3, 0.6), brown)
        fill(ellipse(0.66, 0.22, 0.3, 0.6), brown)
        fill(ellipse(0.18, 0.16, 0.64, 0.77), cream)
        fill(ellipse(0.58, 0.27, 0.21, 0.36), brown, outlined: false)
        eyes(y: 0.48, left: 0.35, right: 0.67, size: 0.075)
        fill(ellipse(0.415, 0.63, 0.17, 0.12), ink, outlined: false)
        stroke(path {
            $0.move(to: point(0.5, 0.72))
            $0.addLine(to: point(0.5, 0.8))
            $0.addQuadCurve(to: point(0.35, 0.78), control: point(0.41, 0.87))
            $0.move(to: point(0.5, 0.8))
            $0.addQuadCurve(to: point(0.65, 0.78), control: point(0.59, 0.87))
        }, ink, width: 0.03)
    }

    func shell() {
        fill(path {
            $0.move(to: point(0.39, 0.89))
            $0.addLine(to: point(0.08, 0.52))
            $0.addQuadCurve(to: point(0.19, 0.28), control: point(-0.02, 0.31))
            $0.addQuadCurve(to: point(0.38, 0.14), control: point(0.2, 0.09))
            $0.addQuadCurve(to: point(0.62, 0.14), control: point(0.5, -0.02))
            $0.addQuadCurve(to: point(0.81, 0.28), control: point(0.8, 0.09))
            $0.addQuadCurve(to: point(0.92, 0.52), control: point(1.02, 0.31))
            $0.addLine(to: point(0.61, 0.89))
            $0.closeSubpath()
        }, Color(red: 0.13, green: 0.57, blue: 0.63))
        stroke(path {
            $0.move(to: point(0.43, 0.79))
            $0.addLine(to: point(0.22, 0.33))
            $0.move(to: point(0.48, 0.79))
            $0.addLine(to: point(0.41, 0.22))
            $0.move(to: point(0.52, 0.79))
            $0.addLine(to: point(0.59, 0.22))
            $0.move(to: point(0.57, 0.79))
            $0.addLine(to: point(0.78, 0.33))
        }, Color(red: 0.65, green: 0.93, blue: 0.9), width: 0.035)
        fill(box(0.36, 0.82, 0.28, 0.11, radius: 0.04), Color(red: 0.47, green: 0.79, blue: 0.76))
    }

    func starfish() {
        fill(starShape(center: point(0.5, 0.52), radius: 0.48, inner: 0.235), Color(red: 0.99, green: 0.53, blue: 0.39))
        let dots = [point(0.5, 0.3), point(0.7, 0.45), point(0.62, 0.7), point(0.38, 0.7), point(0.3, 0.45)]
        for dot in dots {
            fill(ellipse(dot.x - 0.033, dot.y - 0.033, 0.066, 0.066), cream.opacity(0.9), outlined: false)
        }
    }

    func house() {
        let navy = Color(red: 7.0 / 255, green: 26.0 / 255, blue: 59.0 / 255)
        let blue = Color(red: 10.0 / 255, green: 140.0 / 255, blue: 1)
        let silhouette = polygon([
            point(0.06, 0.43), point(0.5, 0.07), point(0.94, 0.43),
            point(0.85, 0.53), point(0.79, 0.48), point(0.79, 0.93),
            point(0.21, 0.93), point(0.21, 0.48), point(0.15, 0.53)
        ])
        fill(silhouette, navy)
        // The blue edge keeps the navy silhouette visible in dark HUDs and share cards.
        stroke(silhouette, blue.opacity(0.85), width: 0.03)
        fill(box(0.28, 0.5, 0.17, 0.17, radius: 0.015), blue, outlined: false)
        fill(box(0.56, 0.61, 0.15, 0.32, radius: 0.015), cream, outlined: false)
    }

    func key() {
        // The ring is a real opening, so every board surface shows through it.
        var silhouette = path {
            $0.move(to: point(0.28 + 0.22 * CGFloat(cos(Double.pi / 6)), 0.39))
            $0.addLine(to: point(0.94, 0.86))
            $0.addLine(to: point(0.86, 0.94))
            $0.addLine(to: point(0.79, 0.87))
            $0.addLine(to: point(0.7, 0.96))
            $0.addLine(to: point(0.61, 0.87))
            $0.addLine(to: point(0.7, 0.78))
            $0.addLine(to: point(0.63, 0.71))
            $0.addLine(to: point(0.54, 0.8))
            $0.addLine(to: point(0.45, 0.71))
            $0.addLine(to: point(0.54, 0.62))
            $0.addLine(to: point(0.39, 0.28 + 0.22 * CGFloat(sin(Double.pi / 3))))
            $0.addArc(center: point(0.28, 0.28), radius: 0.22,
                      startAngle: .degrees(60), endAngle: .degrees(390), clockwise: false)
            $0.closeSubpath()
        }
        silhouette.addEllipse(in: CGRect(x: 0.17, y: 0.17, width: 0.22, height: 0.22))
        let shape = mapped(silhouette)
        context.fill(shape, with: .color(Color(red: 0.95, green: 0.73, blue: 0.31)), style: FillStyle(eoFill: true))
        context.stroke(shape, with: .color(ink.opacity(0.6)), style: StrokeStyle(
            lineWidth: max(0.5, rect.width * 0.032), lineJoin: .round
        ))
    }
}
