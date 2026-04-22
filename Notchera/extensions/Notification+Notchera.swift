import Foundation

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let endClipboardKeyboardNavigation = Notification.Name("endClipboardKeyboardNavigation")
    static let notchKeyboardMoveUp = Notification.Name("notchKeyboardMoveUp")
    static let notchKeyboardMoveDown = Notification.Name("notchKeyboardMoveDown")
    static let notchKeyboardConfirm = Notification.Name("notchKeyboardConfirm")
    static let notchKeyboardAppendText = Notification.Name("notchKeyboardAppendText")
    static let notchKeyboardBackspace = Notification.Name("notchKeyboardBackspace")
}
