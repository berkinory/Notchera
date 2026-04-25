import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI
import SwiftUIIntrospect

struct AboutSettingsView: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: AppUpdaterController?
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                }

                #if canImport(Sparkle)
                if ReleaseChannel.usesSparkleUpdates, let updaterController {
                    UpdaterSettingsView(updater: updaterController.updater)
                } else {
                    BrewUpdaterSettingsView()
                }
                #endif

                HStack(spacing: 10) {
                    AboutSocialCard(title: "GitHub", imageName: "Github") {
                        if let url = URL(string: "https://github.com/berkinory/Notchera") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    AboutSocialCard(title: "Twitter", imageName: "X") {
                        if let url = URL(string: "https://x.com/berkinory") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct AboutSocialCard: View {
    let title: String
    let imageName: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(imageName)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.88))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(background)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isHovering ? Color.white.opacity(0.045) : Color.white.opacity(0.025))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isHovering ? Color.white.opacity(0.06) : Color.white.opacity(0.03), lineWidth: 0.8)
            }
    }
}
