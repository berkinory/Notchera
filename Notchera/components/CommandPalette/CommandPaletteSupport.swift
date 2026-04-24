import AppKit
import SwiftUI

struct CommandPaletteRootRow: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let imageAssetName: String?
    let icon: String?
    let appItem: AppLauncherItem?
    let action: CommandPaletteAction?
    let usageKey: String?

    init(id: String, title: String, subtitle: String? = nil, imageAssetName: String? = nil, icon: String?, appItem: AppLauncherItem? = nil, action: CommandPaletteAction? = nil, usageKey: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.imageAssetName = imageAssetName
        self.icon = icon
        self.appItem = appItem
        self.action = action
        self.usageKey = usageKey
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.imageAssetName == rhs.imageAssetName
            && lhs.icon == rhs.icon
            && lhs.appItem?.id == rhs.appItem?.id
            && lhs.usageKey == rhs.usageKey
    }
}

struct CommandPaletteKeyboardHandler: NSViewRepresentable {
    let isEnabled: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onConfirm: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onMoveUp: onMoveUp, onMoveDown: onMoveDown, onConfirm: onConfirm)
    }

    func makeNSView(context: Context) -> CommandPaletteKeyMonitorHostView {
        let view = CommandPaletteKeyMonitorHostView()
        context.coordinator.start()
        return view
    }

    func updateNSView(_: CommandPaletteKeyMonitorHostView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onMoveUp = onMoveUp
        context.coordinator.onMoveDown = onMoveDown
        context.coordinator.onConfirm = onConfirm
    }

    static func dismantleNSView(_: CommandPaletteKeyMonitorHostView, coordinator: Coordinator) {
        coordinator.stop()
    }
}

final class CommandPaletteKeyMonitorHostView: NSView {}

struct CommandPaletteRowView: View, Equatable {
    let row: CommandPaletteRootRow
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row
            && lhs.isSelected == rhs.isSelected
            && lhs.isHovered == rhs.isHovered
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                iconView

                Text(row.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.54) : Color.secondary.opacity(0.58))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 44, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.leading, 6)
            .padding(.trailing, 6)
            .background(backgroundShape.fill(backgroundFill))
            .overlay {
                backgroundShape
                    .strokeBorder(borderColor, lineWidth: 0.6)
            }
            .contentShape(backgroundShape)
        }
        .buttonStyle(SelectionRowPressStyle())
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .onHover(perform: onHover)
    }

    private var trailingText: String? {
        guard row.appItem == nil else { return nil }

        if row.id == "action.prevent-sleep.toggle" {
            return row.subtitle
        }

        if let subtitle = row.subtitle, subtitle.count <= 14 {
            return subtitle
        }

        return nil
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    private var backgroundFill: Color {
        if isSelected {
            return Color.white.opacity(0.082)
        }

        if isHovered {
            return Color.white.opacity(0.055)
        }

        return Color.white.opacity(0.036)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.white.opacity(0.095)
        }

        if isHovered {
            return Color.white.opacity(0.06)
        }

        return Color.white.opacity(0.03)
    }

    @ViewBuilder
    private var iconView: some View {
        if let appItem = row.appItem {
            Image(nsImage: appItem.icon)
                .resizable()
                .frame(width: 16, height: 16)
        } else if let imageAssetName = row.imageAssetName {
            Image(imageAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 14)
        } else if let icon = row.icon {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.09) : Color.white.opacity(0.045))

                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary.opacity(0.62))
            }
            .frame(width: 18, height: 18)
        }
    }
}

extension CommandPaletteKeyboardHandler {
    final class Coordinator {
        var isEnabled: Bool
        var onMoveUp: () -> Void
        var onMoveDown: () -> Void
        var onConfirm: () -> Void

        private var monitor: Any?

        init(isEnabled: Bool, onMoveUp: @escaping () -> Void, onMoveDown: @escaping () -> Void, onConfirm: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onConfirm = onConfirm
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, isEnabled else { return event }

                switch Int(event.keyCode) {
                case 125:
                    onMoveDown()
                    return nil
                case 126:
                    onMoveUp()
                    return nil
                case 36, 76:
                    onConfirm()
                    return nil
                default:
                    return event
                }
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
