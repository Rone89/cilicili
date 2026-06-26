import SwiftUI

struct HomeVisibleVideoFrame: Equatable {
    let bvid: String
    let index: Int
    let minY: CGFloat
    let midY: CGFloat
    let maxY: CGFloat
    let height: CGFloat

    init(bvid: String, index: Int, frame: CGRect) {
        self.bvid = bvid
        self.index = index
        minY = Self.quantized(frame.minY)
        midY = Self.quantized(frame.midY)
        maxY = Self.quantized(frame.maxY)
        height = Self.quantized(frame.height)
    }

    private static func quantized(_ value: CGFloat) -> CGFloat {
        (value / 4).rounded() * 4
    }
}

struct HomeVisibleVideoFramePreferenceKey: PreferenceKey {
    static var defaultValue: [HomeVisibleVideoFrame] = []

    static func reduce(value: inout [HomeVisibleVideoFrame], nextValue: () -> [HomeVisibleVideoFrame]) {
        value.append(contentsOf: nextValue())
    }
}
