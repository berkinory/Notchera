import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
let openNotchSize: CGSize = .init(width: 370, height: 180)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 34, bottom: 34), closed: (top: 8, bottom: 18))
let expandedShellHorizontalPadding: CGFloat = 31
let windowSize: CGSize = .init(
    width: openNotchSize.width + (expandedShellHorizontalPadding * 2),
    height: openNotchSize.height + shadowPadding
)

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 12, closed: 4)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    if let screen = selectedScreen {
        return screen.frame
    }

    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    var notchHeight: CGFloat = 32
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    if let screen = selectedScreen {
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        if screen.safeAreaInsets.top > 0 {
            notchHeight = Defaults[.notchHeightMode] == .matchRealNotchSize
                ? screen.safeAreaInsets.top
                : screen.frame.maxY - screen.visibleFrame.maxY
        } else {
            notchHeight = Defaults[.nonNotchHeightMode] == .matchMenuBar
                ? screen.frame.maxY - screen.visibleFrame.maxY
                : 32
        }

        notchWidth = snapToDevicePixels(notchWidth, on: screen)
        notchHeight = snapToDevicePixels(notchHeight, on: screen)
    }

    return .init(width: notchWidth, height: notchHeight)
}

@MainActor func snapToDevicePixels(_ value: CGFloat, on screen: NSScreen) -> CGFloat {
    let scale = max(screen.backingScaleFactor, 1)
    return (value * scale).rounded() / scale
}

@MainActor func notchWindowSize(on screen: NSScreen) -> CGSize {
    let maxWidth = max(320, screen.frame.width - 40)
    let width = snapToDevicePixels(min(windowSize.width, maxWidth), on: screen)
    let height = snapToDevicePixels(windowSize.height, on: screen)
    return .init(width: width, height: height)
}

@MainActor func notchWindowFrame(on screen: NSScreen) -> CGRect {
    let size = notchWindowSize(on: screen)
    let x = snapToDevicePixels(screen.frame.midX - (size.width / 2), on: screen)
    let y = snapToDevicePixels(screen.frame.maxY - size.height, on: screen)
    return CGRect(x: x, y: y, width: size.width, height: size.height)
}
