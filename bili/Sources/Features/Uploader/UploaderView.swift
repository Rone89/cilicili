import SwiftUI

struct UploaderView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    let owner: VideoOwner

    @StateObject private var holder = UploaderViewModelHolder()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                UploaderContentView(owner: owner, viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task(id: owner.mid) {
            holder.configure(owner: owner, api: dependencies.api)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .hidesRootTabBarOnPush()
    }
}
