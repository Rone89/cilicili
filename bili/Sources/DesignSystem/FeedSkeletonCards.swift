import SwiftUI

struct VideoFeedSkeletonCard: View {
    enum Style {
        case singleColumn
        case grid
    }

    let style: Style

    var body: some View {
        switch style {
        case .singleColumn:
            singleColumnBody
        case .grid:
            gridBody
        }
    }

    private var singleColumnBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonAspectBlock(cornerRadius: 18)

            HStack(alignment: .center, spacing: 9) {
                SkeletonBlock(width: 34, height: 34, shape: .circle)

                VStack(alignment: .leading, spacing: 1) {
                    SkeletonBlock(height: 18, shape: .rounded(5))
                    SkeletonBlock(width: 206, height: 13, shape: .capsule)
                }
                .frame(height: 34, alignment: .center)
            }
            .frame(height: 34)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 9)
        .padding(.bottom, 14)
        .accessibilityLabel("正在加载视频")
    }

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonAspectBlock(cornerRadius: 15)

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    SkeletonBlock(height: 15, shape: .rounded(5))
                    SkeletonBlock(width: 104, height: 15, shape: .rounded(5))
                }
                .frame(minHeight: 36, alignment: .topLeading)

                HStack(spacing: 4) {
                    SkeletonBlock(width: 14, height: 14, shape: .circle)
                    SkeletonBlock(width: 92, height: 11, shape: .capsule)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityLabel("正在加载视频")
    }
}

struct DynamicFeedSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SkeletonBlock(width: 36, height: 36, shape: .circle)

                SkeletonBlock(width: 132, height: 14, shape: .capsule)

                Spacer(minLength: 10)

                SkeletonBlock(width: 52, height: 11, shape: .capsule)
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(height: 17, shape: .rounded(5))
                SkeletonBlock(width: 260, height: 17, shape: .rounded(5))
            }
            .padding(.horizontal, 12)

            SkeletonAspectBlock(cornerRadius: 20)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                SkeletonBlock(width: 74, height: 28, shape: .capsule)
                SkeletonBlock(width: 74, height: 28, shape: .capsule)
                SkeletonBlock(width: 74, height: 28, shape: .capsule)
            }
            .padding(.horizontal, 12)
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 21)
        .padding(.bottom, 23)
        .accessibilityLabel("正在加载动态")
    }
}

struct LiveRoomSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonAspectBlock(cornerRadius: 15)

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(height: 18, shape: .rounded(5))
                SkeletonBlock(width: 206, height: 17, shape: .rounded(5))

                HStack(spacing: 6) {
                    SkeletonBlock(width: 24, height: 24, shape: .circle)
                    SkeletonBlock(width: 148, height: 12, shape: .capsule)
                }
                .padding(.top, 2)

                SkeletonBlock(width: 112, height: 10, shape: .capsule)
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 14)
        .accessibilityLabel("正在加载直播间")
    }
}
