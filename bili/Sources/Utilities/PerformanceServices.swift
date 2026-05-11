import AVFoundation
import Combine
import SwiftUI
import UIKit

actor VideoPreloadCenter {
    static let shared = VideoPreloadCenter()

    private let maxConcurrentPreloads = 3
    private var tasks: [String: Task<Void, Never>] = [:]
    private var activeOrder: [String] = []

    func preload(_ video: VideoItem, api: BiliAPIClient) {
        guard tasks[video.bvid] == nil, let cid = video.cid else { return }
        trimIfNeeded()
        activeOrder.append(video.bvid)
        tasks[video.bvid] = Task(priority: .utility) { [bvid = video.bvid] in
            do {
                let data = try await api.fetchPlayURL(bvid: bvid, cid: cid, page: nil)
                guard !Task.isCancelled else { return }
                let urls: (video: URL, audio: URL?)? = await MainActor.run {
                    guard let variant = data.playVariants.first(where: { $0.isPlayable }),
                          let videoURL = variant.videoURL
                    else { return nil }
                    return (videoURL, variant.audioURL)
                }
                guard let urls else { return }
                async let videoAssetWarmup: Void = Self.warmAsset(url: urls.video)
                if let audioURL = urls.audio {
                    async let audioAssetWarmup: Void = Self.warmAsset(url: audioURL)
                    _ = await (videoAssetWarmup, audioAssetWarmup)
                } else {
                    _ = await videoAssetWarmup
                }
            } catch {}
            self.finish(bvid)
        }
    }

    func cancel(_ video: VideoItem) {
        tasks[video.bvid]?.cancel()
        tasks[video.bvid] = nil
        activeOrder.removeAll { $0 == video.bvid }
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        activeOrder.removeAll()
    }

    private func finish(_ bvid: String) {
        tasks[bvid] = nil
        activeOrder.removeAll { $0 == bvid }
    }

    private func trimIfNeeded() {
        while activeOrder.count >= maxConcurrentPreloads, let oldest = activeOrder.first {
            tasks[oldest]?.cancel()
            tasks[oldest] = nil
            activeOrder.removeFirst()
        }
    }

    private nonisolated static func warmAsset(url: URL) async {
        let asset = AVURLAsset(url: url)
        _ = try? await asset.load(.isPlayable)
        _ = try? await asset.load(.duration)
    }
}

actor VideoRangeCache {
    static let shared = VideoRangeCache()

    private let maxCacheBytes: Int64 = 512 * 1024 * 1024
    private let fileManager = FileManager.default
    private let rootURL: URL

    init() {
        rootURL = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoRangeCache", isDirectory: true)
    }

    func data(url: URL, range: HTTPByteRange) -> Data? {
        let fileURL = cacheFileURL(url: url, range: range)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return try? Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    func store(_ data: Data, url: URL, range: HTTPByteRange) {
        guard !data.isEmpty else { return }
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try data.write(to: cacheFileURL(url: url, range: range), options: .atomic)
            trimIfNeeded()
        } catch {}
    }

    private func cacheFileURL(url: URL, range: HTTPByteRange) -> URL {
        let key = "\(Self.stableCacheHash(url.absoluteString))-\(range.start)-\(range.endInclusive).bin"
        return rootURL.appendingPathComponent(key)
    }

    private nonisolated static func stableCacheHash(_ string: String) -> String {
        let basis: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        let value = string.utf8.reduce(basis) { partial, byte in
            (partial ^ UInt64(byte)) &* prime
        }
        return String(value, radix: 16)
    }

    private func trimIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        let entries = files.compactMap { url -> (url: URL, date: Date, size: Int64)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }

        var totalSize = entries.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > maxCacheBytes else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? fileManager.removeItem(at: entry.url)
            totalSize -= entry.size
            if totalSize <= maxCacheBytes { break }
        }
    }
}

@MainActor
enum Haptics {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
    }

    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.75)
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}

struct CachedRemoteImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let scale: CGFloat
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader = CachedRemoteImageLoader()

    init(
        url: URL?,
        scale: CGFloat = 1,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.scale = scale
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loader.image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loader.load(url: url, scale: scale)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

@MainActor
final class CachedRemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var task: Task<Void, Never>?

    func load(url: URL?, scale: CGFloat) async {
        task?.cancel()
        guard let url else {
            image = nil
            return
        }

        if let cachedImage = await RemoteImageCache.shared.image(for: url) {
            image = cachedImage
            return
        }

        task = Task(priority: .utility) { [weak self] in
            guard let loadedImage = await RemoteImageCache.shared.load(url: url, scale: scale),
                  !Task.isCancelled
            else { return }
            await MainActor.run {
                self?.image = loadedImage
            }
        }
        await task?.value
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

actor RemoteImageCache {
    static let shared = RemoteImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 320
        cache.totalCostLimit = 42 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func load(url: URL, scale: CGFloat) async -> UIImage? {
        if let cached = image(for: url) {
            return cached
        }

        if let task = inFlight[url] {
            return await task.value
        }

        let task = Task(priority: .utility) { () -> UIImage? in
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                let (data, _) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled,
                      let decoded = UIImage(data: data, scale: scale)
                else { return nil }
                return decoded.preparingForDisplay() ?? decoded
            } catch {
                return nil
            }
        }

        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: image.memoryCost)
        }
        return image
    }
}

private extension UIImage {
    nonisolated var memoryCost: Int {
        guard let cgImage else { return 1 }
        return max(cgImage.bytesPerRow * cgImage.height, 1)
    }
}
