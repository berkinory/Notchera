import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct MusicSlotConfigurationView: View {
    @Default(.musicControlSlots) private var musicControlSlots
    @Default(.musicControlSlotLimit) private var musicControlSlotLimit
    @Default(.matchAlbumArtColor) private var matchAlbumArtColor
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var selectedSlotIndex = 3
    @State private var draggedSlotIndex: Int?

    private let fixedSlotCount: Int = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            slotRow
            controlPalette
        }
        .onAppear {
            ensureSlotCapacity(fixedSlotCount)
            ensureSlotLimit(fixedSlotCount)
            normalizeSelectedSlotIndex()
        }
        .onChange(of: musicControlSlots) {
            normalizeSelectedSlotIndex()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Controls layout")
                .font(.headline)
                .foregroundStyle(Color.secondary.opacity(0.9))

            Spacer(minLength: 12)

            Button("Reset") {
                withAnimation(.smooth(duration: 0.18)) {
                    musicControlSlots = MusicControlButton.defaultLayout
                    musicControlSlotLimit = fixedSlotCount
                    selectedSlotIndex = 3
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var slotRow: some View {
        GeometryReader { geometry in
            let totalSpacing = CGFloat(fixedSlotCount - 1) * 4
            let totalHorizontalPadding: CGFloat = 16
            let availableWidth = geometry.size.width - totalSpacing - totalHorizontalPadding
            let slotSize = floor(max(min(availableWidth / CGFloat(fixedSlotCount), 44), 38))

            HStack(spacing: 4) {
                ForEach(0 ..< fixedSlotCount, id: \.self) { index in
                    MusicControlSlotCard(
                        slot: slotValue(at: index),
                        iconColor: previewIconColor(for: slotValue(at: index)),
                        isHiddenDuringDrag: draggedSlotIndex == index,
                        size: slotSize,
                        onSelect: {
                            selectedSlotIndex = index
                        },
                        onDragStart: {
                            draggedSlotIndex = index
                        },
                        onDragEnd: {
                            draggedSlotIndex = nil
                        },
                        onSwap: { fromIndex in
                            swapSlots(from: fromIndex, to: index)
                            draggedSlotIndex = nil
                        },
                        onAssign: { control in
                            assignControl(control, to: index)
                            selectedSlotIndex = index
                            draggedSlotIndex = nil
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(slotRowBackground)
        }
        .frame(height: 54)
    }

    private var controlPalette: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            HStack(spacing: 4) {
                ForEach(availableControls, id: \.self) { control in
                    MusicControlPickerCard(
                        control: control,
                        iconColor: previewIconColor(for: control),
                        action: {
                            assignControl(control, to: selectedSlotIndex)
                        }
                    )
                }
            }
            .padding(5)
            .background(slotRowBackground)
            .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                handlePaletteDrop(providers)
            }

            Spacer(minLength: 0)
        }
    }

    private var availableControls: [MusicControlButton] {
        let assignedControls = Set(musicControlSlots.filter { $0 != .none })
        return MusicControlButton.pickerOptions.filter { !assignedControls.contains($0) }
    }

    private var slotRowBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.035))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.8)
            }
    }

    private var activeControlColor: Color {
        matchAlbumArtColor
            ? Color(nsColor: musicManager.avgColor)
            : .white
    }

    private func previewIconColor(for slot: MusicControlButton) -> Color {
        .primary
    }

    private func normalizeSelectedSlotIndex() {
        if !(0 ..< fixedSlotCount).contains(selectedSlotIndex) {
            selectedSlotIndex = 0
        }
    }

    private func ensureSlotCapacity(_ target: Int) {
        guard target > musicControlSlots.count else { return }
        let missing = target - musicControlSlots.count
        musicControlSlots.append(contentsOf: Array(repeating: .none, count: missing))
    }

    private func ensureSlotLimit(_ target: Int) {
        guard musicControlSlotLimit < target else { return }
        musicControlSlotLimit = target
    }

    private func slotValue(at index: Int) -> MusicControlButton {
        guard musicControlSlots.indices.contains(index) else { return .none }
        return musicControlSlots[index]
    }

    private func swapSlots(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex else { return }
        guard musicControlSlots.indices.contains(fromIndex), musicControlSlots.indices.contains(toIndex) else { return }
        var slots = musicControlSlots
        slots.swapAt(fromIndex, toIndex)
        musicControlSlots = slots
    }

    private func assignControl(_ control: MusicControlButton, to index: Int) {
        var slots = musicControlSlots

        if index >= slots.count {
            slots.append(contentsOf: Array(repeating: .none, count: index - slots.count + 1))
        }

        if let existingIndex = slots.firstIndex(of: control), existingIndex != index {
            slots[existingIndex] = .none
        }

        slots[index] = control
        musicControlSlots = slots
    }

    private func removeSlot(at index: Int) {
        guard musicControlSlots.indices.contains(index) else { return }
        var slots = musicControlSlots
        slots[index] = .none
        musicControlSlots = slots
        draggedSlotIndex = nil
    }

    private func handlePaletteDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let rawValue = item as? String ?? (item as? NSString as String?) else { return }
                DispatchQueue.main.async {
                    guard rawValue.hasPrefix("slotIndex:") else { return }
                    let indexRawValue = rawValue.replacingOccurrences(of: "slotIndex:", with: "")
                    guard let fromIndex = Int(indexRawValue), fromIndex >= 0 else { return }
                    removeSlot(at: fromIndex)
                }
            }
            return true
        }

        return false
    }
}

private struct MusicControlSlotCard: View {
    let slot: MusicControlButton
    let iconColor: Color
    let isHiddenDuringDrag: Bool
    let size: CGFloat
    let onSelect: () -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    let onSwap: (Int) -> Void
    let onAssign: (MusicControlButton) -> Void
    @State private var isDropTargeted = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isDropTargeted ? 0.055 : 0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: isDropTargeted ? 1 : 0.8)
                    }

                if slot == .none || isHiddenDuringDrag {
                    RoundedRectangle(cornerRadius: max(size * 0.18, 7), style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.22))
                        .frame(width: size * 0.58, height: size * 0.58)
                } else {
                    Image(systemName: slot.iconName)
                        .font(.system(size: slot.prefersLargeScale ? size * 0.39 : size * 0.34, weight: .medium))
                        .foregroundStyle(iconColor)
                        .frame(width: size * 0.58, height: size * 0.58)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onDrag {
            guard slot != .none else {
                return NSItemProvider(object: NSString(string: "slot:-1"))
            }
            onDragStart()
            return NSItemProvider(object: NSString(string: "slotIndex:\(MusicManagerSlotLookup.index(for: slot) ?? -1)"))
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var borderColor: Color {
        isDropTargeted
            ? Color(red: 0.62, green: 0.76, blue: 1).opacity(0.95)
            : Color.white.opacity(0.05)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let rawValue = item as? String ?? (item as? NSString as String?) else { return }
                DispatchQueue.main.async {
                    if rawValue.hasPrefix("control:") {
                        let controlRawValue = rawValue.replacingOccurrences(of: "control:", with: "")
                        guard let control = MusicControlButton(rawValue: controlRawValue) else {
                            onDragEnd()
                            return
                        }
                        onAssign(control)
                        return
                    }

                    if rawValue.hasPrefix("slotIndex:") {
                        let indexRawValue = rawValue.replacingOccurrences(of: "slotIndex:", with: "")
                        guard let fromIndex = Int(indexRawValue), fromIndex >= 0 else {
                            onDragEnd()
                            return
                        }
                        onSwap(fromIndex)
                        return
                    }

                    onDragEnd()
                }
            }
            return true
        }

        return false
    }
}

private enum MusicManagerSlotLookup {
    static func index(for control: MusicControlButton) -> Int? {
        Defaults[.musicControlSlots].firstIndex(of: control)
    }
}

private struct MusicControlPickerCard: View {
    let control: MusicControlButton
    let iconColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.045), lineWidth: 0.8)
                    }

                Image(systemName: control.iconName)
                    .font(.system(size: control.prefersLargeScale ? 14 : 12, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 20, height: 20)
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .onDrag {
            NSItemProvider(object: NSString(string: "control:\(control.rawValue)"))
        }
    }
}
