import AppKit
import SwiftUI

class SparkleNSView: NSView {
    private var emitterLayer: CAEmitterLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupEmitterLayer()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupEmitterLayer() {
        let emitterLayer = CAEmitterLayer()
        emitterLayer.emitterShape = .rectangle
        emitterLayer.emitterMode = .surface
        emitterLayer.renderMode = .oldestFirst

        let cell = CAEmitterCell()
        cell.contents = NSImage(named: "sparkle")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        cell.birthRate = 50
        cell.lifetime = 5
        cell.velocity = 10
        cell.velocityRange = 5
        cell.emissionRange = .pi * 2
        cell.scale = 0.2
        cell.scaleRange = 0.1
        cell.alphaSpeed = -0.5
        cell.yAcceleration = 10

        emitterLayer.emitterCells = [cell]

        layer?.addSublayer(emitterLayer)
        self.emitterLayer = emitterLayer

        updateEmitterForCurrentBounds()
    }

    private func updateEmitterForCurrentBounds() {
        guard let emitterLayer else { return }

        emitterLayer.frame = bounds
        emitterLayer.emitterSize = bounds.size
        emitterLayer.emitterPosition = CGPoint(x: bounds.width / 2, y: bounds.height / 2)

        let area = bounds.width * bounds.height
        let baseBirthRate: Float = 50
        let adjustedBirthRate = 20
        emitterLayer.emitterCells?.first?.birthRate = Float(adjustedBirthRate)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateEmitterForCurrentBounds()
    }
}

struct SparkleView: NSViewRepresentable {
    func makeNSView(context _: Context) -> SparkleNSView {
        SparkleNSView()
    }

    func updateNSView(_: SparkleNSView, context _: Context) {}
}
