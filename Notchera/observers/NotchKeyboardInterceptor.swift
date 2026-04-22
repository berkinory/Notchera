import AppKit
import ApplicationServices
import KeyboardShortcuts

final class NotchKeyboardInterceptor {
    static let shared = NotchKeyboardInterceptor()

    enum Mode {
        case dismissOnly
        case commandPalette
        case clipboard
    }

    private enum DispatchAction {
        case none
        case moveUp
        case moveDown
        case confirm
        case cancel
        case append(String)
        case backspace(clearAll: Bool)
        case paste
    }

    private let stateQueue = DispatchQueue(label: "com.notchera.keyboard-interceptor")

    private var mode: Mode?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    func start(mode: Mode) {
        stateQueue.sync {
            self.mode = mode
        }

        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let interceptor = Unmanaged<NotchKeyboardInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handle(type: type, cgEvent: cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func stop() {
        stateQueue.sync {
            mode = nil
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
    }

    private func currentMode() -> Mode? {
        stateQueue.sync {
            mode
        }
    }

    private func shouldPassThroughShortcut(_ event: NSEvent) -> Bool {
        let shortcuts: [KeyboardShortcuts.Name] = [
            .commandPalette,
            .clipboardHistoryPanel,
            .toggleNotchOpen,
        ]

        let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        return shortcuts.contains { name in
            guard let shortcut = name.shortcut else { return false }
            return Int(shortcut.carbonKeyCode) == Int(event.keyCode)
                && shortcut.modifiers.intersection(.deviceIndependentFlagsMask) == eventFlags
        }
    }

    private func handle(type: CGEventType, cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(cgEvent)
        }

        guard type == .keyDown,
              let mode = currentMode(),
              let event = NSEvent(cgEvent: cgEvent)
        else {
            return Unmanaged.passRetained(cgEvent)
        }

        let action = dispatchAction(for: event, mode: mode)

        switch action {
        case .none:
            if mode == .dismissOnly || shouldPassThroughShortcut(event) {
                return Unmanaged.passRetained(cgEvent)
            }
            return nil
        default:
            DispatchQueue.main.async {
                self.dispatch(action, for: mode)
            }
            return nil
        }
    }

    private func dispatchAction(for event: NSEvent, mode: Mode) -> DispatchAction {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let control = flags.contains(.control)
        let option = flags.contains(.option)
        let function = flags.contains(.function)

        if mode == .dismissOnly {
            return Int(event.keyCode) == 53 ? .cancel : .none
        }

        switch Int(event.keyCode) {
        case 53:
            return .cancel
        case 125:
            return .moveDown
        case 126:
            return .moveUp
        case 36, 76:
            return .confirm
        case 51, 117:
            return .backspace(clearAll: command)
        default:
            break
        }

        if command, Int(event.keyCode) == 9 {
            return .paste
        }

        if command || control || option || function {
            return .none
        }

        guard let characters = event.characters,
              !characters.isEmpty,
              characters.unicodeScalars.contains(where: { !CharacterSet.controlCharacters.contains($0) })
        else {
            return .none
        }

        return .append(characters)
    }

    private func dispatch(_ action: DispatchAction, for mode: Mode) {
        switch action {
        case .none:
            return
        case .moveUp:
            NotificationCenter.default.post(name: .notchKeyboardMoveUp, object: mode)
        case .moveDown:
            NotificationCenter.default.post(name: .notchKeyboardMoveDown, object: mode)
        case .confirm:
            NotificationCenter.default.post(name: .notchKeyboardConfirm, object: mode)
        case .cancel:
            NotificationCenter.default.post(
                name: .endClipboardKeyboardNavigation,
                object: nil,
                userInfo: ["shouldCloseNotch": true]
            )
        case let .append(text):
            NotificationCenter.default.post(
                name: .notchKeyboardAppendText,
                object: mode,
                userInfo: ["text": text]
            )
        case let .backspace(clearAll):
            NotificationCenter.default.post(
                name: .notchKeyboardBackspace,
                object: mode,
                userInfo: ["clearAll": clearAll]
            )
        case .paste:
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
            NotificationCenter.default.post(
                name: .notchKeyboardAppendText,
                object: mode,
                userInfo: ["text": text]
            )
        }
    }
}
