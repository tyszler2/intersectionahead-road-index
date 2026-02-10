import Foundation

public enum RoadTileFetcherError: Error {
    case invalidResponse
    case invalidTileData
}

public enum RoadTileFormat: Hashable {
    case json
    case mvt
}

public final class RoadTileFetcher {
    private let baseURL: URL
    private let session: URLSession
    private let format: RoadTileFormat

    public init(baseURL: URL, format: RoadTileFormat = .json, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.format = format
        self.session = session
    }

    public func fetch(tileID: TileID) async throws -> RoadTile {
        let url = baseURL
            .appendingPathComponent("\(tileID.z)")
            .appendingPathComponent("\(tileID.x)")
            .appendingPathComponent("\(tileID.y).\(fileExtension())")

        var request = URLRequest(url: url)
        request.setValue("IntersectionAhead/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RoadTileFetcherError.invalidResponse
        }

        switch format {
        case .json:
            return try JSONDecoder().decode(RoadTile.self, from: data)
        case .mvt:
            return try MVTRoadExtractor.roadTile(from: data, tileID: tileID)
        }
    }

    public func fetchAndStore(tileID: TileID, store: TileStore) async throws -> RoadTile {
        let tile = try await fetch(tileID: tileID)
        let data = try JSONEncoder().encode(tile)
        try await store.save(tile: tile, data: data)
        return tile
    }

    private func fileExtension() -> String {
        switch format {
        case .json: return "json"
        case .mvt: return "pbf"
        }
    }
}
