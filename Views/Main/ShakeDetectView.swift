import SwiftUI
import UIKit

/// デバイスのシェイクを検知する（内部ビューが first responder になる）。
struct ShakeDetectView: UIViewRepresentable {
    var onShake: () -> Void

    func makeUIView(context: Context) -> ShakeUIView {
        let v = ShakeUIView()
        v.onShake = { onShake() }
        return v
    }

    func updateUIView(_ uiView: ShakeUIView, context: Context) {
        uiView.onShake = { onShake() }
    }

    final class ShakeUIView: UIView {
        var onShake: () -> Void = {}

        override var canBecomeFirstResponder: Bool { true }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                DispatchQueue.main.async { [weak self] in
                    _ = self?.becomeFirstResponder()
                }
            }
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            if motion == .motionShake {
                onShake()
            }
        }
    }
}
