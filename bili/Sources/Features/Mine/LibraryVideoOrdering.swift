import Foundation
import SwiftUI

nonisolated enum LibraryVideoOrder: String, CaseIterable, Identifiable {
    case original
    case titleAscending
    case shortestFirst
    case longestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "默认顺序"
        case .titleAscending: "按标题排序"
        case .shortestFirst: "时长从短到长"
        case .longestFirst: "时长从长到短"
        }
    }

    func arrange(_ entries: [AccountVideoEntry], query: String = "") -> [AccountVideoEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = entries.enumerated().filter { _, item in
            query.isEmpty || item.title.localizedStandardContains(query)
                || (item.owner?.name.localizedStandardContains(query) ?? false)
                || item.bvid.localizedStandardContains(query)
        }
        guard self != .original else { return matches.map(\.element) }
        return matches.sorted { lhs, rhs in
            switch self {
            case .original:
                return lhs.offset < rhs.offset
            case .titleAscending:
                let comparison = lhs.element.title.localizedStandardCompare(rhs.element.title)
                return comparison == .orderedSame ? lhs.offset < rhs.offset : comparison == .orderedAscending
            case .shortestFirst, .longestFirst:
                // Missing and nonpositive durations sort last in either direction.
                let left = lhs.element.duration.flatMap { $0 > 0 ? $0 : nil }
                let right = rhs.element.duration.flatMap { $0 > 0 ? $0 : nil }
                switch (left, right) {
                case (.some(let left), .some(let right)):
                    if left == right { return lhs.offset < rhs.offset }
                    return self == .shortestFirst ? left < right : left > right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.offset < rhs.offset
                }
            }
        }.map(\.element)
    }
}

struct LibraryVideoSortMenu: View {
    @Binding var order: LibraryVideoOrder
    let identifier: String

    var body: some View {
        Menu {
            Picker("排序", selection: $order) {
                ForEach(LibraryVideoOrder.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Label("排序", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(order.title)
    }
}
