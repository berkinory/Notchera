import Defaults
import Foundation

struct TabModel: Identifiable {
    var id: NotchViews {
        view
    }

    let label: String
    let icon: String
    let view: NotchViews
}

var tabs: [TabModel] {
    var items = [
        TabModel(label: "Music", icon: "music.note", view: .home),
    ]

    if Defaults[.enableCalendar] {
        items.append(TabModel(label: "Calendar", icon: "calendar", view: .calendar))
    }

    if Defaults[.notchShelf] {
        items.append(TabModel(label: "Shelf", icon: "folder.fill", view: .shelf))
    }

    if Defaults[.enableClipboardHistory], !Defaults[.hideClipboardFromTabs] {
        items.append(TabModel(label: "Clipboard", icon: "doc.on.clipboard", view: .clipboard))
    }

    if Defaults[.enableCommandLauncher], !Defaults[.hideLauncherFromTabs] {
        items.append(TabModel(label: "Launcher", icon: "command", view: .commandPalette))
    }

    if Defaults[.enableAIUsage] {
        items.append(TabModel(label: "AI Usage", icon: "chart.bar.fill", view: .aiUsage))
    }

    return items
}
