import SwiftUI

struct DynamicImageHeroPreview: View {
    let images: [DynamicImageItem]
    var cornerRadius: CGFloat = 18
    var aspectRatio: CGFloat = 16 / 9

    private var firstImage: DynamicImageItem? {
        images.first
    }

    var body: some View {
        if let firstImage {
            DynamicImageButton(
                image: firstImage,
                displayMode: .hero(aspectRatio: aspectRatio, cornerRadius: cornerRadius)
            ) {
                heroOverlay
            }
            .accessibilityLabel(accessibilityTitle)
        }
    }

    @ViewBuilder
    private var heroOverlay: some View {
        if images.count > 1 {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.46)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom) {
                    VideoCoverGlassBadge {
                        Label("\(min(images.count, 9))图", systemImage: "photo.on.rectangle.angled")
                            .labelStyle(.titleAndIcon)
                    }

                    Spacer(minLength: 8)

                    VideoCoverGlassBadge {
                        Text("1/\(images.count)")
                            .monospacedDigit()
                    }
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var accessibilityTitle: String {
        images.count > 1 ? "查看 \(images.count) 张图片" : "查看图片"
    }
}
