import AVFoundation
import Foundation
import UniformTypeIdentifiers

final class BiliHeaderResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let assetURL: URL

    private let originalURL: URL
    private let headers: [String: String]
    private let callbackQueue = DispatchQueue(label: "cc.bili.progressive-resource-loader")
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private lazy var session: URLSession = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.underlyingQueue = self.callbackQueue
        return URLSession(configuration: .default, delegate: nil, delegateQueue: queue)
    }()

    init(originalURL: URL, headers: [String: String]) {
        self.originalURL = originalURL
        self.headers = headers
        let identifier = UUID().uuidString
        assetURL = URL(string: "bili-resource://asset/\(identifier)/video.mp4")!
        super.init()
    }

    deinit {
        session.invalidateAndCancel()
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        var request = URLRequest(url: originalURL)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let rangeHeader = rangeHeader(for: loadingRequest) {
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }

        let identifier = ObjectIdentifier(loadingRequest)
        let task = session.dataTask(with: request) { [weak self, weak loadingRequest] data, response, error in
            guard let self = self, let loadingRequest = loadingRequest else { return }
            self.removeTask(for: identifier)

            if let error = error {
                loadingRequest.finishLoading(with: error)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, let data else {
                loadingRequest.finishLoading(with: Self.error(message: "Empty progressive video response."))
                return
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                let message = "Progressive video HTTP \(httpResponse.statusCode)."
                PlayerMetricsLog.logger.error("progressiveProxyHTTPError status=\(httpResponse.statusCode, privacy: .public)")
                loadingRequest.finishLoading(with: Self.error(code: httpResponse.statusCode, message: message))
                return
            }

            self.fillContentInformation(
                loadingRequest.contentInformationRequest,
                response: httpResponse,
                dataLength: data.count
            )
            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
        }
        store(task, for: identifier)
        task.resume()
        return true
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let identifier = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = tasks.removeValue(forKey: identifier)
        lock.unlock()
        task?.cancel()
    }

    private func rangeHeader(for loadingRequest: AVAssetResourceLoadingRequest) -> String? {
        guard let dataRequest = loadingRequest.dataRequest else {
            return loadingRequest.contentInformationRequest == nil ? nil : "bytes=0-1"
        }
        let start = dataRequest.currentOffset > 0 ? dataRequest.currentOffset : dataRequest.requestedOffset
        let length = Int64(dataRequest.requestedLength)
        guard start >= 0, length > 0 else { return nil }
        return "bytes=\(start)-\(start + length - 1)"
    }

    private func fillContentInformation(
        _ contentInformationRequest: AVAssetResourceLoadingContentInformationRequest?,
        response: HTTPURLResponse,
        dataLength: Int
    ) {
        guard let contentInformationRequest = contentInformationRequest else { return }
        contentInformationRequest.isByteRangeAccessSupported = true
        contentInformationRequest.contentLength = contentLength(from: response, dataLength: dataLength)
        if let mimeType = response.mimeType,
           let type = UTType(mimeType: mimeType) ?? UTType(mimeType: mimeType, conformingTo: .movie) {
            contentInformationRequest.contentType = type.identifier
        } else if let type = UTType(filenameExtension: "mp4") {
            contentInformationRequest.contentType = type.identifier
        }
    }

    private func contentLength(from response: HTTPURLResponse, dataLength: Int) -> Int64 {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let slashIndex = contentRange.lastIndex(of: "/"),
           let total = Int64(contentRange[contentRange.index(after: slashIndex)...]) {
            return total
        }
        if response.expectedContentLength > 0 {
            return response.expectedContentLength
        }
        return Int64(dataLength)
    }

    private func store(_ task: URLSessionDataTask, for identifier: ObjectIdentifier) {
        lock.lock()
        tasks[identifier] = task
        lock.unlock()
    }

    private func removeTask(for identifier: ObjectIdentifier) {
        lock.lock()
        tasks.removeValue(forKey: identifier)
        lock.unlock()
    }

    private static func error(code: Int = -1, message: String) -> NSError {
        NSError(
            domain: "cc.bili.progressive-resource-loader",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
