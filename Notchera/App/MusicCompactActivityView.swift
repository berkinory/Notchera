import SwiftUI

struct MusicCompactActivityView: View {
    @EnvironmentObject var vm: NotcheraViewModel
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID
    let hoverBoostActive: Bool

    var body: some View {
        HStack {
            compactAlbumArt

            Rectangle()
                .fill(.black)
                .frame(
                    width: vm.closedNotchSize.width
                        + -cornerRadiusInsets.closed.top
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
                .blur(radius: musicManager.compactIsFlipping ? 2.2 : 0)
                .saturation(musicManager.compactIsFlipping ? 0.965 : 1)
                .scaleEffect(musicManager.compactIsFlipping ? 0.982 : 1)

            RoundedRectangle(
                cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                style: .continuous
            )
            .fill(.black)
            .opacity(musicManager.isPlaying ? 0 : 0.45)
            .blur(radius: 5)
        }
        .scaleEffect(musicManager.isPlaying ? (hoverBoostActive ? 1.07 : 1) : (hoverBoostActive ? 0.97 : 0.92))
        .animation(.spring(response: 0.22, dampingFraction: 0.72, blendDuration: 0), value: hoverBoostActive)
        .animation(.timingCurve(0.22, 0.88, 0.32, 1, duration: 0.26), value: musicManager.compactIsFlipping)
        .frame(
            width: max(0, vm.effectiveClosedNotchHeight - 10),
            height: max(0, vm.effectiveClosedNotchHeight - 10)
        )
    }
}
