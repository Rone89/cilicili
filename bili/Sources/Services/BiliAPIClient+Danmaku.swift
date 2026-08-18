import Foundation

nonisolated struct DanmakuRequestContext: Sendable {
    let commentURL: URL
    let apiURL: URL
    let guestModeCookieHeader: String?
}

extension BiliAPIClient {
    func fetchDanmaku(cid: Int) async throws -> [DanmakuItem] {
        if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(for: cid, segmentIndex: 0) {
            return cached
        }

        return try await ResourceRequestLimiter.shared.runDanmaku { [self] in
            if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(for: cid, segmentIndex: 0) {
                return cached
            }

            let context = await danmakuRequestContext()
            var request = try await makeRequest(
                base: context.commentURL,
                path: "/\(cid).xml",
                query: [:],
                referer: "https://www.bilibili.com",
                userAgent: Self.webUserAgent,
                cookieHeader: context.guestModeCookieHeader,
                cachePolicy: .returnCacheDataElseLoad
            )
            request.networkServiceType = .responsiveData
            request.timeoutInterval = 8
            request.setValue("application/xml,text/xml,*/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await fetchDanmakuData(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                throw BiliAPIError.emptyData
            }
            guard !data.isEmpty else { throw BiliAPIError.emptyData }

            let items = try DanmakuXMLParser(cid: cid).parse(data: data)
            await SubtitleDanmakuResourceCache.shared.storeDanmaku(items, for: cid, segmentIndex: 0)
            return items
        }
    }

    func fetchDanmakuSegment(cid: Int, segmentIndex: Int) async throws -> [DanmakuItem] {
        let normalizedSegmentIndex = max(1, segmentIndex)
        if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(
            for: cid,
            segmentIndex: normalizedSegmentIndex
        ) {
            return cached
        }

        return try await ResourceRequestLimiter.shared.runDanmaku { [self] in
            if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(
                for: cid,
                segmentIndex: normalizedSegmentIndex
            ) {
                return cached
            }

            let context = await danmakuRequestContext()
            var request = try await makeRequest(
                base: context.apiURL,
                path: "/x/v2/dm/web/seg.so",
                query: [
                    "type": "1",
                    "oid": String(cid),
                    "segment_index": String(normalizedSegmentIndex),
                ],
                referer: "https://www.bilibili.com",
                userAgent: Self.webUserAgent,
                cookieHeader: context.guestModeCookieHeader,
                cachePolicy: .returnCacheDataElseLoad
            )
            request.networkServiceType = .responsiveData
            request.timeoutInterval = 8
            request.setValue("application/octet-stream,*/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await fetchDanmakuData(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                throw BiliAPIError.emptyData
            }

            let items = try DanmakuSegmentProtobufParser(
                cid: cid,
                segmentIndex: normalizedSegmentIndex
            )
            .parse(data: data)
            await SubtitleDanmakuResourceCache.shared.storeDanmaku(
                items,
                for: cid,
                segmentIndex: normalizedSegmentIndex
            )
            return items
        }
    }
}
