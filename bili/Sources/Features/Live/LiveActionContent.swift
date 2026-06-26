import SwiftUI

struct LiveActionContent: View {
    let title: String
    let systemImage: String
    let foregroundStyle: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))

            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 25)
        .padding(.horizontal, 7)
        .foregroundStyle(foregroundStyle)
        .background(VideoDetailTheme.secondarySurface.opacity(0.92), in: Capsule())
    }
}
