import Foundation
import QuartzCore

extension VideoDetailViewModel {
    func scheduleSupplementalPlayURLLoad(
        cid: Int,
        page: Int?,
        waitsForFirstFrame: Bool = false,
        startDelay: TimeInterval = 0
    ) {
        cancelPlayURLSupplementTask(advancesGeneration: false)
        let supplementGeneration = advancePlayURLSupplementGeneration()
        let bvid = detail.bvid
        isSupplementingPlayQualities = false
        playURLSupplementTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            guard !self.isPlaybackInvalidatedForNavigation,
                  self.detail.bvid == bvid,
                  self.selectedCID == cid,
                  self.playURLSupplementGeneration == supplementGeneration
            else { return }
            defer {
                if !Task.isCancelled,
                   !self.isPlaybackInvalidatedForNavigation,
                   self.detail.bvid == bvid,
                   self.selectedCID == cid,
                   self.playURLSupplementGeneration == supplementGeneration {
                    self.isSupplementingPlayQualities = false
                }
                self.clearPlayURLSupplementTaskIfCurrent(generation: supplementGeneration)
            }
            do {
                guard await self.waitForSupplementalPlayURLStart(
                    cid: cid,
                    waitsForFirstFrame: waitsForFirstFrame,
                    startDelay: startDelay
                ) else { return }
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.selectedCID == cid,
                      self.playURLSupplementGeneration == supplementGeneration
                else { return }
                self.isSupplementingPlayQualities = true
                let supplementStart = CACurrentMediaTime()
                let supplementalPreferredQuality = self.targetPlaybackPreferredQuality
                self.recordSupplementalPlayURLLoadStarted(preferredQuality: supplementalPreferredQuality)
                let data = try await self.fetchSupplementalPlayURLData(
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    preferredQuality: supplementalPreferredQuality
                )
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.selectedCID == cid,
                      self.playURLSupplementGeneration == supplementGeneration
                else { return }
                await self.storeSupplementalPlayURLData(data, bvid: bvid, cid: cid, page: page)
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.selectedCID == cid,
                      self.playURLSupplementGeneration == supplementGeneration
                else { return }
                self.applySupplementalPlayURLData(
                    data,
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    supplementStart: supplementStart
                )
            } catch {
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.playURLSupplementGeneration == supplementGeneration
                else { return }
                self.recordSupplementalPlayURLLoadFailed(error)
            }
        }
    }
}
