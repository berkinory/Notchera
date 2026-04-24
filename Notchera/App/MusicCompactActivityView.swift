import SwiftUI

struct MusicCompactActivityView: View {
    @EnvironmentObject var vm: NotcheraViewModel
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID
    let hoverBoostActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            compactAlbumArt

            Rectangle()
                .fill(.black)
                .frame(
                    width: max(0, vm.closedNotchSize.width - 24)
                )

            MusicSpectrumIndicatorView(
                albumArtNamespace: albumArtNamespace,
                isPlaying: musicManager.isPlaying,
                avgColor: musicManager.avgColor,
                barWidth: 50,
                spectrumSize: CGSize(width: 16, height: 12),
                containerSize: CGSize(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                ),
                cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed
            )
        }
        .padding(.leading, 2)
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var compactAlbumArt: some View {
        ZStack {
            Image(nsImage: musicManager.compactAlbumArt)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                        style: .continuous
                    )
                )
                .blur(radius: musicManager.compactFlipProgress * 1.2)
                .saturation(1 - (musicManager.compactFlipProgress * 0.025))
                .scaleEffect(1 - (musicManager.compactFlipProgress * 0.012))

            RoundedRectangle(
                cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                style: .continuous
            )
            .fill(.black)
            .opacity(0)
            .blur(radius: 5)
        }
        .scaleEffect(hoverBoostActive ? 1.07 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.72, blendDuration: 0), value: hoverBoostActive)
        .frame(
            width: max(0, vm.effectiveClosedNotchHeight - 10),
            height: max(0, vm.effectiveClosedNotchHeight - 10)
        )
    }
}
