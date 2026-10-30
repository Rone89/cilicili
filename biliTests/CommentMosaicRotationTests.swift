import XCTest
import SwiftUI
import UIKit
@testable import bili

final class CommentMosaicRotationTests: XCTestCase {
    @MainActor
    func testMultiImageGridShrinksAfterWideLayout() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let payload: [String: Any] = ["src": file.absoluteString, "width": 4, "height": 4]
        let image = try JSONDecoder().decode(DynamicImageItem.self,
            from: JSONSerialization.data(withJSONObject: payload))
        for count in [2, 3, 4, 6, 9] {
            let host = UIHostingController(rootView: CompactDynamicImageMosaicGrid(
                images: Array(repeating: image, count: count),
                accessibilityName: "评论图片", placeholderFill: .gray))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 1000))
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            for width in [CGFloat(320), 800, 160, 320, 800, 320] {
                window.frame.size.width = width
                host.view.frame = window.bounds
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                await Task.yield()
                let size = host.sizeThatFits(in: CGSize(width: width, height: 10000))
                XCTAssertEqual(size.width, width, accuracy: 1, "count=\(count), width=\(width)")
                let rows = CGFloat((count + 2) / 3)
                let spacing = DynamicImageGridMetrics.spacing
                let height = count <= 4 ? width * 9 / 16
                    : rows * (width - 2 * spacing) / 3 + (rows - 1) * spacing
                XCTAssertEqual(size.height, height, accuracy: 1, "count=\(count), width=\(width)")
            }
        }
    }
}
