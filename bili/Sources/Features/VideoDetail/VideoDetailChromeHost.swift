import SwiftUI
import UIKit

struct VideoDetailChromeState {
    let hidesSystemChrome: Bool
    let showsPerformanceOverlay: Bool
}

private struct VideoDetailChromeHostModifier: ViewModifier {
    @ObservedObject var viewModel: VideoDetailViewModel
    let state: VideoDetailChromeState
    let retryPlaybackLoad: () -> Void

    func body(content: Content) -> some View {
        content
            .preference(
                key: VideoDetailChromeHiddenPreferenceKey.self,
                value: state.hidesSystemChrome
            )
            .statusBar(hidden: state.hidesSystemChrome)
            .persistentSystemOverlays(state.hidesSystemChrome ? .hidden : .automatic)
            .overlay(alignment: .top) {
                VideoDetailChromeStatusBarBackdrop(isHidden: state.hidesSystemChrome)
            }
            .background {
                VideoDetailChromeStatusBarStyleBridge(
                    style: .lightContent,
                    isHidden: state.hidesSystemChrome
                )
            }
            .overlay {
                VideoDetailChromeFailureOverlay(
                    placeholderStore: viewModel.playbackRenderStore.placeholderStore,
                    retry: retryPlaybackLoad
                )
            }
            .overlay(alignment: .topLeading) {
                VideoDetailChromePerformanceOverlay(
                    store: viewModel.networkDiagnosticsRenderStore,
                    isPresented: state.showsPerformanceOverlay,
                    hidesSystemChrome: state.hidesSystemChrome
                )
            }
    }
}

extension View {
    func videoDetailChrome(
        viewModel: VideoDetailViewModel,
        state: VideoDetailChromeState,
        retryPlaybackLoad: @escaping () -> Void
    ) -> some View {
        modifier(
            VideoDetailChromeHostModifier(
                viewModel: viewModel,
                state: state,
                retryPlaybackLoad: retryPlaybackLoad
            )
        )
    }
}
