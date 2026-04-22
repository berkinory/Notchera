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
        TabModel(label: "Calendar", icon: "calendar", view: .calendar),
        TabModel(label: "Launcher", icon: "command", view: .commandPalette),
        TabModel(label: "Clipboard", icon: "doc.on.clipboard", view: .clipboard),
    ]

    if Defaults[.enableAIUsage] {
        items.append(TabModel(label: "AI Usage", icon: "chart.bar.fill", view: .aiUsage))
    }

    items.append(TabModel(label: "Shelf", icon: "folder.fill", view: .shelf))

    return items
}
