#if DEBUG
import Foundation

/// A fixed input and ABBA order; this does not change either renderer's policy.
struct DanmakuBenchmarkPlan {
    struct Step: Equatable {
        let density: Int
        let metal: Bool
        var renderer: String { metal ? "Metal" : "DanmakuKit" }
    }

    let sampleSeconds: Double
    let warmupSeconds: Double
    let steps: [Step]

    init(sampleSeconds: Double = 90, warmupSeconds: Double = 3, densities: [Int] = [50, 100, 300]) {
        self.sampleSeconds = sampleSeconds
        self.warmupSeconds = warmupSeconds
        steps = densities.flatMap { density in
            [false, true, true, false].map { Step(density: density, metal: $0) }
        }
    }

    var totalSeconds: Double { Double(steps.count) * (sampleSeconds + warmupSeconds) }

    func reportHeader(suiteID: UUID, index: Int, status: String) -> String {
        let step = steps[index]
        return """
        Automatic Danmaku A/B
        suite: \(suiteID.uuidString)
        step: \(index + 1)/\(steps.count); renderer: \(step.renderer); density: \(step.density)
        status: \(status); requested sample: \(sampleSeconds)s; warmup: \(warmupSeconds)s
        requested callback FPS: 60; playback rate: 1.0; order: Kit / Metal / Metal / Kit
        """
    }
}
#endif
