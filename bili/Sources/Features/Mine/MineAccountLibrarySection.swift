import SwiftUI

struct MineAccountLibrarySection: View {
    @ObservedObject var viewModel: MineViewModel

    var body: some View {
        Section {
            NavigationLink {
                AccountLibraryListPage(kind: .history, viewModel: viewModel)
            } label: {
                AccountLibraryButtonRow(
                    title: "观看记录",
                    systemImage: "clock.arrow.circlepath"
                )
            }

            NavigationLink {
                AccountLibraryListPage(kind: .favorites, viewModel: viewModel)
            } label: {
                AccountLibraryButtonRow(
                    title: "账号收藏",
                    systemImage: "star"
                )
            }
        } header: {
            Text("账号内容")
        }
    }
}
