import AVFoundation
import Combine
import Darwin
import Foundation
import UIKit

@MainActor
final class PlayerRecoveryTestDriver: PlaybackRecoveryTestDriving {
    private weak var player: PlayerStateViewModel?
    private let metricsID: String
    private var cancellables = Set<AnyCancellable>()
    private var interruptionCancellables = Set<AnyCancellable>()
    private var originalIdleTimerDisabled: Bool?
    var onMetric: (@MainActor (String, String) -> Void)?
    var onInterrupt: (@MainActor (String) -> Void)?

    init(player: PlayerStateViewModel, metricsID: String) {
        self.player = player
        self.metricsID = metricsID
        PlayerPerformanceStore.shared.updates
            .filter { $0.metricsID == metricsID }
            .sink { [weak self] _ in
                guard let self,
                      let event = PlayerPerformanceStore.shared.events.last,
                      event.metricsID == metricsID
                else { return }
                let kind: String
                switch event.kind {
                case .manualResumeRecovery: kind = "manualResume"
                case .seek: kind = "seek"
                case .seekRecovery: kind = "seekRecovery"
                case .failed: kind = "failure"
                default: return
                }
                self.onMetric?(kind, event.message ?? "")
            }
            .store(in: &cancellables)
    }

    var observation: PlaybackRecoveryTestObservation {
        guard let player else { return PlaybackRecoveryTestObservation(issue: "播放器已退出") }
        return player.recoveryTestObservation()
    }

    var reportContext: [String: String] {
        guard let player else { return [:] }
        let diagnostics = player.engineDiagnostics
        let session = PlayerPerformanceStore.shared.session(for: metricsID)
        var system = utsname()
        uname(&system)
        let hardware = withUnsafeBytes(of: &system.machine) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        return [
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-",
            "hardwareIdentifier": hardware,
            "deviceModel": UIDevice.current.model,
            "systemVersion": UIDevice.current.systemVersion,
            "metricsID": metricsID,
            "engine": diagnostics.engineName,
            "pipeline": diagnostics.playbackPipeline.rawValue,
            "codec": diagnostics.codec ?? "-",
            "resolution": diagnostics.resolution ?? "-",
            "frameRate": diagnostics.frameRate ?? "-",
            "dynamicRange": diagnostics.dynamicRange.rawValue,
            "quality": safeText(session?.selectedQualityMessage),
            "startupQuality": session?.startupQuality.map { String($0) } ?? "-",
            "durationSeconds": String(observation.duration),
            "playbackRate": String(player.playbackRate.rawValue),
            "networkClass": observation.networkClass,
            "lowPowerMode": String(ProcessInfo.processInfo.isLowPowerModeEnabled),
            "thermalState": String(ProcessInfo.processInfo.thermalState.rawValue),
            "avPlayerStartupExperiment": session?.avPlayerStartupPathOptimizationExperimentEnabled.map { String($0) } ?? "-",
            "piliPlusSelectionExperiment": session?.piliPlusStylePlayURLSelectionExperimentEnabled.map { String($0) } ?? "-",
        ]
    }

    private func safeText(_ value: String?) -> String {
        guard let value, !value.lowercased().contains("http"),
              !value.lowercased().contains("cookie"), !value.lowercased().contains("token")
        else { return "-" }
        return String(value.prefix(256))
    }

    func setTestingActive(_ active: Bool) {
        if active {
            guard originalIdleTimerDisabled == nil else { return }
            originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.onInterrupt?("App离开前台")
                }
                .store(in: &interruptionCancellables)
            NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.onInterrupt?("音频会话受到系统中断")
                }
                .store(in: &interruptionCancellables)
        } else {
            interruptionCancellables.removeAll()
            if let originalIdleTimerDisabled {
                UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
            }
            originalIdleTimerDisabled = nil
        }
    }

    func pause() { player?.pause() }
    func play() { player?.playFromUserInteraction() }
    func seek(to progress: Double) {
        guard let player, !player.isTerminated else { return }
        player.beginUserScrubInteraction(source: .nativeProgress)
        player.seekAfterSliderCommit(to: progress)
    }
}
