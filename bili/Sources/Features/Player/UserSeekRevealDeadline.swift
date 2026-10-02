nonisolated struct UserSeekRevealDeadline: Equatable, Sendable {
    let targetTime: Double
    let readySince: Double
    let settleDelay: Double
    let seekGeneration: Int
    let surfaceGeneration: Int

    var deadline: Double {
        readySince + settleDelay
    }

    init?(
        targetTime: Double,
        readySince: Double,
        settleDelay: Double,
        seekGeneration: Int,
        surfaceGeneration: Int
    ) {
        let deadline = readySince + settleDelay
        guard targetTime.isFinite, targetTime >= 0,
              readySince.isFinite,
              settleDelay.isFinite, settleDelay >= 0,
              deadline.isFinite else { return nil }
        self.targetTime = targetTime
        self.readySince = readySince
        self.settleDelay = settleDelay
        self.seekGeneration = seekGeneration
        self.surfaceGeneration = surfaceGeneration
    }

    func remainingDelay(at now: Double) -> Double? {
        guard now.isFinite, deadline > now else { return nil }
        let delay = deadline - now
        return delay.isFinite ? delay : nil
    }

    func matches(
        targetTime: Double?,
        readySince: Double?,
        seekGeneration: Int,
        surfaceGeneration: Int
    ) -> Bool {
        targetTime == self.targetTime
            && readySince == self.readySince
            && seekGeneration == self.seekGeneration
            && surfaceGeneration == self.surfaceGeneration
    }
}
