import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct QRCodeLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: MineViewModel
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("扫码登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.startQRCodeLogin()
        }
        .onChange(of: viewModel.qrLoginState) { _, state in
            guard case .succeeded = state else { return }
            dismissTask?.cancel()
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                dismiss()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
            viewModel.cancelQRCodeLogin()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.qrLoginState {
        case .idle, .loading:
            VStack(spacing: 14) {
                ProgressView()
                Text(viewModel.qrLoginState.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .waiting(let info, _), .scanned(let info, _):
            VStack(spacing: 18) {
                QRCodeImage(value: info.url)
                    .frame(width: 236, height: 236)
                    .padding(14)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Label(viewModel.qrLoginState.message, systemImage: statusIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.center)

                Button {
                    Task {
                        await viewModel.startQRCodeLogin()
                    }
                } label: {
                    Label("刷新二维码", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

        case .expired(let message):
            retryContent(systemImage: "qrcode", title: "二维码已过期", message: message)

        case .failed(let message):
            retryContent(systemImage: "exclamationmark.triangle", title: "二维码登录失败", message: message)

        case .succeeded(let message):
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.green)
                Text(message)
                    .font(.headline)
            }
        }
    }

    private var statusIcon: String {
        if case .scanned = viewModel.qrLoginState {
            return "checkmark.circle"
        }
        return "qrcode.viewfinder"
    }

    private var statusColor: Color {
        if case .scanned = viewModel.qrLoginState {
            return .pink
        }
        return .secondary
    }

    private func retryContent(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.startQRCodeLogin()
                }
            } label: {
                Label("重新生成", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
    }
}

private struct QRCodeImage: View {
    let value: String

    var body: some View {
        if let image = QRCodeRenderer.image(from: value) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }
}

private enum QRCodeRenderer {
    static func image(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
