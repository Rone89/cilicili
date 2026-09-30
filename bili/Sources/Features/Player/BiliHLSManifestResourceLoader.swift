import AVFoundation
import Foundation
import OSLog
import UniformTypeIdentifiers

nonisolated final class BiliHLSManifestResourceLoader: NSObject,
    AVAssetResourceLoaderDelegate,
    @unchecked Sendable
{
    private struct ManifestResponse {
        let data: Data
        let dataRange: Range<Int>?
    }

    private enum RequestError: LocalizedError {
        case invalidManifestRequest
        case invalidManifestData
        case invalidByteRange
        case invalidated

        var errorDescription: String? {
            switch self {
            case .invalidManifestRequest:
                "The HLS manifest request is invalid or unavailable."
            case .invalidManifestData:
                "The HLS manifest is not valid UTF-8 data."
            case .invalidByteRange:
                "The HLS manifest byte range is invalid."
            case .invalidated:
                "The HLS manifest loader has been invalidated."
            }
        }
    }

    private static let scheme = "cilicili-hls"
    private static let playlistContentType = UTType.m3uPlaylist.identifier

    let assetURL: URL
    /// Pass this serial queue to `AVAssetResourceLoader.setDelegate(_:queue:)`.
    let delegateQueue: DispatchQueue

    private let manifestsByPath: [String: Data]
    private let sessionID: UUID
    private let delegateQueueSpecificKey = DispatchSpecificKey<Bool>()
    private var isInvalidated = false
    private var manifestRequestCount = 0

    init(manifestsByPath: [String: Data], sessionID: UUID) {
        self.manifestsByPath = manifestsByPath
        self.sessionID = sessionID
        self.assetURL = URL(
            string: "cilicili-hls://session/\(sessionID.uuidString.lowercased())/master.m3u8"
        )!
        delegateQueue = DispatchQueue(
            label: "cc.bili.hls-manifest-resource-loader.\(sessionID.uuidString.lowercased())"
        )
        super.init()
        delegateQueue.setSpecific(key: delegateQueueSpecificKey, value: true)
    }

    static func virtualURL(forPath path: String, sessionID: UUID) -> URL? {
        guard isValidManifestPath(path) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "session"
        components.path = "/\(sessionID.uuidString.lowercased())\(path)"
        return components.url
    }

    /// Prevents subsequent requests from being served and waits for any delegate callback in progress.
    func invalidate() {
        if DispatchQueue.getSpecific(key: delegateQueueSpecificKey) == true {
            invalidateOnDelegateQueue()
        } else {
            delegateQueue.sync {
                invalidateOnDelegateQueue()
            }
        }
    }

    private func invalidateOnDelegateQueue() {
        guard !isInvalidated else { return }
        isInvalidated = true
        PlayerMetricsLog.logger.info(
            "[DASH-HLS] manifest loader cancelled requests=\(self.manifestRequestCount, privacy: .public)"
        )
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let response: Result<ManifestResponse, RequestError> = isInvalidated
            ? .failure(.invalidated)
            : response(for: loadingRequest)
        switch response {
        case .success(let response):
            manifestRequestCount += 1
            if let path = loadingRequest.request.url?.path.split(separator: "/").last {
                PlayerMetricsLog.logger.debug(
                    "[DASH-HLS] manifest request path=\(String(path), privacy: .public) bytes=\(response.data.count, privacy: .public)"
                )
            }
            if let contentInformationRequest = loadingRequest.contentInformationRequest {
                contentInformationRequest.contentType = Self.playlistContentType
                contentInformationRequest.contentLength = Int64(response.data.count)
                contentInformationRequest.isByteRangeAccessSupported = true
                contentInformationRequest.isEntireLengthAvailableOnDemand = true
            }
            if let dataRequest = loadingRequest.dataRequest, let dataRange = response.dataRange {
                dataRequest.respond(with: response.data.subdata(in: dataRange))
            }
            loadingRequest.finishLoading()
        case .failure(let error):
            loadingRequest.finishLoading(with: error)
        }
        return true
    }

    private func response(
        for loadingRequest: AVAssetResourceLoadingRequest
    ) -> Result<ManifestResponse, RequestError> {
        guard let url = loadingRequest.request.url,
              let path = Self.manifestPath(from: url, sessionID: sessionID),
              let data = manifestsByPath[path]
        else {
            return .failure(.invalidManifestRequest)
        }
        guard String(data: data, encoding: .utf8) != nil else {
            return .failure(.invalidManifestData)
        }

        let dataRange: Range<Int>?
        if let dataRequest = loadingRequest.dataRequest {
            guard let range = Self.responseRange(
                resourceLength: data.count,
                requestedOffset: dataRequest.requestedOffset,
                currentOffset: dataRequest.currentOffset,
                requestedLength: dataRequest.requestedLength,
                requestsAllDataToEndOfResource: dataRequest.requestsAllDataToEndOfResource
            ) else {
                return .failure(.invalidByteRange)
            }
            dataRange = range
        } else {
            dataRange = nil
        }

        return .success(ManifestResponse(data: data, dataRange: dataRange))
    }

    static func manifestPath(from url: URL, sessionID: UUID) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host == "session",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath == components.path
        else {
            return nil
        }

        let sessionPathPrefix = "/\(sessionID.uuidString.lowercased())/"
        guard components.path.hasPrefix(sessionPathPrefix) else { return nil }
        let path = "/" + String(components.path.dropFirst(sessionPathPrefix.count))
        guard isValidManifestPath(path) else { return nil }
        return path
    }

    static func responseRange(
        resourceLength: Int,
        requestedOffset: Int64,
        currentOffset: Int64,
        requestedLength: Int,
        requestsAllDataToEndOfResource: Bool
    ) -> Range<Int>? {
        guard resourceLength >= 0,
              requestedOffset >= 0,
              requestedLength >= 0,
              let totalLength = Int64(exactly: resourceLength),
              let requestedLength64 = Int64(exactly: requestedLength)
        else {
            return nil
        }

        let startOffset = currentOffset >= 0
            ? max(requestedOffset, currentOffset)
            : requestedOffset
        guard startOffset <= totalLength else { return nil }

        let endOffset: Int64
        if requestsAllDataToEndOfResource {
            endOffset = totalLength
        } else {
            let requestedEnd = requestedOffset.addingReportingOverflow(requestedLength64)
            guard !requestedEnd.overflow, startOffset <= requestedEnd.partialValue else { return nil }
            endOffset = min(totalLength, requestedEnd.partialValue)
        }

        guard let start = Int(exactly: startOffset),
              let end = Int(exactly: endOffset),
              start <= end
        else {
            return nil
        }
        return start..<end
    }

    private static func isValidManifestPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.hasSuffix("/") else { return false }
        let components = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard let filename = components.last,
              filename.hasSuffix(".m3u8"),
              !components.isEmpty
        else {
            return false
        }

        return components.allSatisfy { component in
            guard component != ".", component != "..", !component.isEmpty else { return false }
            return component.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 45, 46, 48...57, 65...90, 95, 97...122:
                    true
                default:
                    false
                }
            }
        }
    }
}
