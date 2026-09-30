import Foundation

enum BiliHLSManifestTransportPlan {
    enum Error: Swift.Error {
        case invalidSourceURL
        case invalidManifestPath
        case missingMasterPlaylist
        case invalidPlaylistData
        case invalidVirtualURL
    }

    nonisolated static func virtualizedManifests(
        manifestDataByPath: [String: Data],
        httpMasterURL: URL,
        virtualURLForPath: (String) -> URL?
    ) throws -> [String: Data] {
        guard httpMasterURL.scheme == "http", httpMasterURL.host == "127.0.0.1",
              httpMasterURL.lastPathComponent == "master.m3u8"
        else { throw Error.invalidSourceURL }
        guard manifestDataByPath["/master.m3u8"] != nil else {
            throw Error.missingMasterPlaylist
        }

        let httpBaseURL = httpMasterURL.deletingLastPathComponent()
        var replacements: [(original: String, virtual: String)] = []
        for path in manifestDataByPath.keys {
            guard path.hasPrefix("/"), path.hasSuffix(".m3u8"),
                  !path.contains(".."), !path.contains("?"), !path.contains("#")
            else { throw Error.invalidManifestPath }
            guard let virtualURL = virtualURLForPath(path),
                  virtualURL.scheme == "cilicili-hls"
            else { throw Error.invalidVirtualURL }
            let httpURL = httpBaseURL.appendingPathComponent(String(path.dropFirst()))
            replacements.append((httpURL.absoluteString, virtualURL.absoluteString))
        }

        var result: [String: Data] = [:]
        for (path, data) in manifestDataByPath {
            guard var playlist = String(data: data, encoding: .utf8) else {
                throw Error.invalidPlaylistData
            }
            for replacement in replacements {
                playlist = playlist.replacingOccurrences(
                    of: replacement.original,
                    with: replacement.virtual
                )
            }
            result[path] = Data(playlist.utf8)
        }
        return result
    }
}
