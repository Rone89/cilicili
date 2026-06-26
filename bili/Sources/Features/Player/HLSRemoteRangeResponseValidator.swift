import Foundation

enum HLSRemoteRangeResponseValidator {
    nonisolated static func validate(
        _ response: URLResponse,
        requestedRange: HTTPByteRange,
        url: URL? = nil
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw HLSBridgeRemoteFailure.httpStatus(httpResponse.statusCode, url: url, range: requestedRange)
        }
        if httpResponse.statusCode == 200, requestedRange.start > 0 {
            throw HLSBridgeRemoteFailure.invalidRangeResponse(statusCode: httpResponse.statusCode, url: url, range: requestedRange)
        }
    }
}
