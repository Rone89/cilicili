import SwiftUI

/// 详情加载中分P区块的占位：紧凑单行入口的骨架形态。
struct InitialPageMenuPlaceholder: View {
    let pageCount: Int?

    var body: some View {
        HStack(spacing: 10) {
            Text("分P")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let pageCount {
                Text("\(pageCount) P")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            SkeletonBlock(width: 120, height: 14, shape: .capsule)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
