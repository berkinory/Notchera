import AppKit
import Cocoa
import SwiftUI

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private let barCount = 4
    private var isPlaying: Bool = true
    private var animationTimer: Timer?
    private var hasStartedAnimation = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    override func layout() {
        super.layout()
        layoutBars()
    }

    private func setupBars() {
        guard barLayers.isEmpty else { return }

        for _ in 0 ..< barCount {
            let barLayer = CAShapeLayer()
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.fillColor = NSColor.white.cgColor
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barLayers.append(barLayer)
            barScales.append(0.35)
            layer?.addSublayer(barLayer)
        }

        layoutBars()
    }

    private func layoutBars() {
        guard !barLayers.isEmpty else { return }

        let size = bounds.size == .zero ? CGSize(width: 16, height: 14) : bounds.size
        let barWidth = max(2, floor(size.width / 8))
        let spacing = barWidth
        let contentWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let startX = (size.width - contentWidth) / 2

        for (index, barLayer) in barLayers.enumerated() {
            let x = startX + CGFloat(index) * (barWidth + spacing) + barWidth / 2
            barLayer.bounds = CGRect(x: 0, y: 0, width: barWidth, height: size.height)
            barLayer.position = CGPoint(x: x, y: size.height / 2)
            barLayer.path = NSBezierPath(
                roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: size.height),
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).cgPath
        }
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateBars()
        }

        if !hasStartedAnimation {
            hasStartedAnimation = true
            updateBars()
        }
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }

    private func updateBars() {
        for (i, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[i]
            let targetScale = CGFloat.random(in: 0.35 ... 1.0)
            barScales[i] = targetScale
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = 0.3
            animation.autoreverses = true
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            if #available(macOS 13.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
            }
            barLayer.add(animation, forKey: "scaleY")
        }
    }

    private func resetBars() {
        for (i, barLayer) in barLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barScales[i] = 0.35
        }
    }

    func setPlaying(_ playing: Bool) {
        guard isPlaying != playing || (playing && animationTimer == nil) else { return }

        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool

    func makeNSView(context _: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }

    func updateNSView(_ nsView: AudioSpectrum, context _: Context) {
        nsView.setPlaying(isPlaying)
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
