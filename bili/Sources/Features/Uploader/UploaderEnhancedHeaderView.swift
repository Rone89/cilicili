import SwiftUI

struct UploaderEnhancedHeaderView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    let owner: VideoOwner
    @ObservedObject var viewModel: UploaderViewModel

    private var card: UploaderCard? { viewModel.profile?.card }
    private var overview: UploaderSpaceOverview? { viewModel.spaceOverview }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    AvatarRemoteImage(urlString: card?.face ?? owner.face, pixelSize: 240) {
                        Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                    }
                    .frame(width: 80, height: 80).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 8) {
                        Text(card?.name ?? owner.name).font(.title2.weight(.bold))
                        if viewModel.isOwnSpace {
                            Text("我的个人空间").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            UploaderFollowButton(owner: owner, viewModel: viewModel)
                                .disabled(!viewModel.canChangeRelation || viewModel.profile?.following == nil || viewModel.profileState.isLoading)
                        }
                    }
                    Spacer(minLength: 0)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { badges }
                    VStack(alignment: .leading, spacing: 6) { badges }
                }
                Text("UID: \(owner.mid)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                UploaderSignatureText(sign: card?.sign)
                if let verification = overview?.verification, !verification.isEmpty {
                    Label(verification, systemImage: "checkmark.seal")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, libraryStore.standardPageHorizontalInset)
            UploaderStatsRow(viewModel: viewModel, card: card, usesEqualColumns: true)
                .padding(.horizontal, 20)
            Divider()
                .padding(.horizontal, 20)
            UploaderFollowMessage(message: viewModel.followMessage, isFollowing: viewModel.isFollowing)
                .padding(.horizontal, libraryStore.standardPageHorizontalInset)
            UploaderProfileStatusMessage(state: viewModel.profileState)
                .padding(.horizontal, libraryStore.standardPageHorizontalInset)
        }
    }

    @ViewBuilder private var badges: some View {
        if let level = overview?.level { Text("LV\(level)").font(.caption.weight(.semibold)) }
        if let vip = overview?.vipLabel, !vip.isEmpty { Text(vip).font(.caption.weight(.semibold)) }
        if let location = overview?.location, !location.isEmpty {
            Text(location).font(.caption).foregroundStyle(.secondary)
        }
    }
}
