import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlass(cornerRadius: CGFloat = 24, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    func transientClearGlass() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.clear, in: .circle)
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
        }
    }
}

struct AdaptiveGlassButton<Label: View>: View {
    let prominent: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(prominent: Bool = false, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.prominent = prominent
        self.action = action
        self.label = label
    }

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent {
                Button(action: action, label: label).buttonStyle(.glassProminent)
            } else {
                Button(action: action, label: label).buttonStyle(.glass)
            }
        } else {
            if prominent {
                Button(action: action, label: label)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(action: action, label: label)
                    .buttonStyle(.bordered)
            }
        }
    }
}
