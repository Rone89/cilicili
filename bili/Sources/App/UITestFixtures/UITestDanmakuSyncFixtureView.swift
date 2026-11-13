import AVFoundation
import Combine
import OSLog
import SwiftUI

private let danmakuSyncProbeLog = Logger(subsystem: "cc.bili", category: "DanmakuSyncProbe")

/// 临时诊断探针：真实 AVPlayer + 同步层弹幕后端的端到端可视化验证页。
/// 仅 DEBUG 构建可通过 --ui-test-fixture danmakuSync 进入。
@MainActor
struct UITestDanmakuSyncFixtureView: View {
    @State private var controller: PlayerController?

    @MainActor
    final class PlayerController: ObservableObject {
        let player: AVPlayer
        let host = DanmakuRendererHostView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        private var timeObserver: Any?
        private var endObserver: NSObjectProtocol?
        private let probeLog = Logger(subsystem: "cc.bili", category: "DanmakuSyncProbe")

        init() {
            let item = AVPlayerItem(url: Self.makeLocalVideoURL())
            player = AVPlayer(playerItem: item)
            let host = self.host
            let items = Self.makeProbeItems()
            host.selectRenderer(preference: .synchronizedLayer)
            host.setPlaybackPlayer(player)
            let configuration = DanmakuOverlayConfiguration(
                items: items,
                itemsRevision: 1,
                currentTime: 0,
                isPlaying: true,
                playbackRate: 1,
                isEnabled: true,
                hasPresentedPlayback: true,
                isLoadShedding: false,
                settings: DanmakuSettings(danmakuKit: .init(displayArea: .full)),
                topInset: 28,
                bottomInset: 84
            )
            host.apply(configuration: configuration)
            danmakuSyncProbeLog.info("probe configured items=\(items.count, privacy: .public)")
            var windowRevision = 1
            let allItems = items
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1, preferredTimescale: 10),
                queue: .main
            ) { time in
                let seconds = time.seconds
                Task { @MainActor in
                    host.synchronizePlaybackTime(seconds)
                    // 模拟生产链路的窗口滑动：每秒重发窗口切片，验证飞行中弹幕跨窗口存活。
                    windowRevision += 1
                    let windowed = allItems.filter { abs($0.time - seconds) < 10 }
                    let configuration = DanmakuOverlayConfiguration(
                        items: windowed,
                        itemsRevision: windowRevision,
                        currentTime: seconds,
                        isPlaying: true,
                        playbackRate: 1,
                        isEnabled: true,
                        hasPresentedPlayback: true,
                        isLoadShedding: false,
                        settings: DanmakuSettings(danmakuKit: .init(displayArea: .full)),
                        topInset: 28,
                        bottomInset: 84
                    )
                    host.apply(configuration: configuration)
                    if let syncView = host.debugActiveRenderer as? DanmakuSynchronizedLayerView {
                        danmakuSyncProbeLog.info(
                            "probe t=\(String(format: "%.1f", seconds), privacy: .public) windowed=\(windowed.count, privacy: .public) \(syncView.debugLayerSummary, privacy: .public)"
                        )
                    }
                }
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                Task { @MainActor [weak player] in
                    player?.seek(to: .zero)
                    player?.play()
                }
            }
            player.play()
        }

        static func makeProbeItems() -> [DanmakuItem] {
            let colors: [UInt32] = [0xFFFFFF, 0x55D6FF, 0xFFD6E7, 0xB7FF8A]
            var items: [DanmakuItem] = []
            for index in 0..<45 {
                let mode: Int
                if index % 9 == 0 {
                    mode = 5
                } else if index % 9 == 4 {
                    mode = 4
                } else {
                    mode = 1
                }
                let time = Double(index % 45) * 0.55 + 0.4
                let text = "同步层探针弹幕 \(index) 🐶 ABC 123 密集压力测试"
                items.append(DanmakuItem(
                    id: "probe-\(index)",
                    time: time,
                    mode: mode,
                    fontSize: 25,
                    color: colors[index % 4],
                    text: text
                ))
            }
            return items
        }

        static func makeLocalVideoURL() -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("danmaku-sync-probe.mov")
            try? FileManager.default.removeItem(at: url)
            let writer = try! AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 640,
                AVVideoHeightKey: 360,
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                    kCVPixelBufferWidthKey as String: 640,
                    kCVPixelBufferHeightKey as String: 360,
                ]
            )
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            for frame in 0..<120 {
                while !input.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                let buffer = Self.makeFrame(adaptor: adaptor, frameIndex: frame)
                let seconds = Double(frame) / 30.0
                let presentationTime = CMTime(seconds: seconds, preferredTimescale: 600)
                adaptor.append(buffer, withPresentationTime: presentationTime)
            }
            input.markAsFinished()
            let semaphore = DispatchSemaphore(value: 0)
            writer.finishWriting {
                semaphore.signal()
            }
            semaphore.wait()
            return url
        }

        private static func makeFrame(adaptor: AVAssetWriterInputPixelBufferAdaptor, frameIndex: Int) -> CVPixelBuffer {
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixelBuffer = buffer!
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let base = CVPixelBufferGetBaseAddress(pixelBuffer)!
            for y in 0..<height {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    let offset = x * 4
                    row[offset] = 40
                    row[offset + 1] = UInt8((x * 255 / width) & 0xFF)
                    row[offset + 2] = UInt8((y * 255 / height) & 0xFF)
                    row[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return pixelBuffer
        }

        func tearDown() {
            if let timeObserver {
                player.removeTimeObserver(timeObserver)
            }
            endObserver.map { NotificationCenter.default.removeObserver($0) }
            player.pause()
            host.stop()
        }
    }

    var body: some View {
        Group {
            if let controller {
                ProbeContent(controller: controller)
            } else {
                Color.black
                    .task { controller = PlayerController() }
            }
        }
        .ignoresSafeArea()
        .onDisappear {
            controller?.tearDown()
        }
    }

    private struct ProbeContent: View {
        @ObservedObject var controller: PlayerController

        var body: some View {
            ZStack {
                Color.black
                PlayerLayerView(player: controller.player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HostEmbeddingView(host: controller.host)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                VStack {
                    Text("danmaku-sync probe")
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("ui.danmakuSync.ready")
                    Spacer()
                }
            }
        }
    }

    private final class PlayerLayerHostView: UIView {
        let playerLayer = AVPlayerLayer()

        init(player: AVPlayer) {
            super.init(frame: .zero)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            playerLayer.frame = bounds
            layer.addSublayer(playerLayer)
            accessibilityIdentifier = "ui.danmakuSync.playerLayer"
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }

    private struct PlayerLayerView: UIViewRepresentable {
        let player: AVPlayer

        func makeUIView(context: Context) -> PlayerLayerHostView {
            PlayerLayerHostView(player: player)
        }

        func updateUIView(_ uiView: PlayerLayerHostView, context: Context) {
            uiView.setNeedsLayout()
        }
    }

    private struct HostEmbeddingView: UIViewRepresentable {
        let host: DanmakuRendererHostView

        func makeUIView(context: Context) -> DanmakuRendererHostView {
            host
        }

        func updateUIView(_ uiView: DanmakuRendererHostView, context _: Context) {}
    }
}
