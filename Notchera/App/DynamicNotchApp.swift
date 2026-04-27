import AppKit
import ApplicationServices
import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            Text("Notchera \(Bundle.main.releaseVersionNumberPretty)")
                .foregroundStyle(.secondary)

            Divider()

            Button {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(self)
            } label: {
                Label("Quit", systemImage: "power")
            }
        } label: {
            MenuBarIconView()
        }
    }
}

private struct MenuBarIconView: View {
    private let size: CGFloat = 17

    var body: some View {
        Image(nsImage: MenuBarIconImageRenderer.make(size: size))
            .renderingMode(.original)
            .interpolation(.high)
            .antialiased(true)
            .frame(width: size, height: size)
            .padding(.vertical, 1)
            .accessibilityLabel("Notchera")
    }
}

private enum MenuBarIconImageRenderer {
    static func make(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        defer {
            image.unlockFocus()
            image.isTemplate = false
        }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius = size * 0.26
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        let cgPath = path.cgPath

        context.saveGState()
        context.addPath(cgPath)
        context.clip()

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let verticalColors = [
            NSColor(white: 0.52, alpha: 1).cgColor,
            NSColor(white: 0.94, alpha: 1).cgColor,
            NSColor(white: 0.52, alpha: 1).cgColor,
        ] as CFArray
        let verticalGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: verticalColors,
            locations: [0, 0.5, 1]
        )

        context.drawLinearGradient(
            verticalGradient!,
            start: CGPoint(x: size / 2, y: size),
            end: CGPoint(x: size / 2, y: 0),
            options: []
        )

        let horizontalGlowColors = [
            NSColor(calibratedWhite: 1, alpha: 0).cgColor,
            NSColor(calibratedWhite: 1, alpha: 0.22).cgColor,
            NSColor(calibratedWhite: 1, alpha: 0).cgColor,
        ] as CFArray
        let horizontalGlowGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: horizontalGlowColors,
            locations: [0, 0.5, 1]
        )

        context.drawLinearGradient(
            horizontalGlowGradient!,
            start: CGPoint(x: 0, y: size / 2),
            end: CGPoint(x: size, y: size / 2),
            options: []
        )

        let highlightInset = size * 0.08
        let highlightRect = rect.insetBy(dx: highlightInset, dy: highlightInset)
        let highlightPath = NSBezierPath(
            roundedRect: highlightRect,
            xRadius: max(0, cornerRadius - highlightInset),
            yRadius: max(0, cornerRadius - highlightInset)
        )

        context.addPath(highlightPath.cgPath)
        context.clip()

        let highlightColors = [
            NSColor(calibratedWhite: 1, alpha: 0.48).cgColor,
            NSColor(calibratedWhite: 1, alpha: 0.02).cgColor,
        ] as CFArray
        let highlightGradient = CGGradient(colorsSpace: colorSpace, colors: highlightColors, locations: [0, 1])
        context.drawLinearGradient(
            highlightGradient!,
            start: CGPoint(x: 0, y: size),
            end: CGPoint(x: size, y: 0),
            options: []
        )

        context.restoreGState()

        NSColor.white.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 0.65
        path.stroke()

        return image
    }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0 ..< elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}
