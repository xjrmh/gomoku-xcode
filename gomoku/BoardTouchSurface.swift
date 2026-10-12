#if os(iOS)
import SwiftUI
import UIKit

/// Native board gestures let a quick swipe pass through to the enclosing scroll view.
struct BoardTouchSurface: UIViewRepresentable {
    let interactive: Bool
    let onTap: (CGPoint) -> Void
    let onPrecisionChanged: (CGPoint) -> Void
    let onPrecisionEnded: (CGPoint?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true

        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.precisionChanged(_:)))
        hold.minimumPressDuration = 0.25
        hold.allowableMovement = 10
        hold.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        tap.require(toFail: hold)

        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(tap)
        context.coordinator.hold = hold
        context.coordinator.tap = tap
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.owner = self
        if !interactive { context.coordinator.cancelPrecision() }
        uiView.isUserInteractionEnabled = interactive
        if context.coordinator.hold?.isEnabled != interactive {
            context.coordinator.hold?.isEnabled = interactive
        }
        if context.coordinator.tap?.isEnabled != interactive {
            context.coordinator.tap?.isEnabled = interactive
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.cancelPrecision()
        for recognizer in uiView.gestureRecognizers ?? [] {
            recognizer.isEnabled = false
            recognizer.delegate = nil
            recognizer.removeTarget(coordinator, action: nil)
            uiView.removeGestureRecognizer(recognizer)
        }
        coordinator.hold = nil
        coordinator.tap = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: BoardTouchSurface
        weak var hold: UILongPressGestureRecognizer?
        weak var tap: UITapGestureRecognizer?
        private var precisionActive = false

        init(owner: BoardTouchSurface) { self.owner = owner }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard owner.interactive, recognizer.state == .ended, let view = recognizer.view else { return }
            owner.onTap(recognizer.location(in: view))
        }

        @objc func precisionChanged(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                guard owner.interactive, let view = recognizer.view else { return }
                precisionActive = true
                owner.onPrecisionChanged(recognizer.location(in: view))
            case .ended:
                guard precisionActive else { return }
                precisionActive = false
                let location = owner.interactive ? recognizer.view.map { recognizer.location(in: $0) } : nil
                owner.onPrecisionEnded(location)
            case .cancelled, .failed:
                cancelPrecision()
            default:
                break
            }
        }

        func cancelPrecision() {
            guard precisionActive else { return }
            precisionActive = false
            owner.onPrecisionEnded(nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard owner.interactive, let view = gestureRecognizer.view else { return false }
            return view.bounds.contains(touch.location(in: view))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === hold,
                  owner.interactive,
                  let view = gestureRecognizer.view,
                  let scrollView = otherGestureRecognizer.view as? UIScrollView,
                  otherGestureRecognizer === scrollView.panGestureRecognizer else { return false }
            // The ancestor pan waits for this hold to fail. Movement beyond ten
            // points releases scrolling; a recognized hold keeps placement steady.
            // This requirement is evaluated per attempt, with no retained parent pan.
            return view.isDescendant(of: scrollView)
        }
    }
}
#endif
