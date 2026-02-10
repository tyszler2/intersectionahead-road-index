import Foundation

public enum RoadIndexStoreError: Error {
    case noRegion
}

public enum RoadIndexFetcherError: Error {
    case invalidResponse
}

public actor RoadIndexStore {
    public struct Config: Hashable {
        public let directory: URL
        public let maxBytes: Int

        public init(directory: URL, maxBytes: Int = 50 * 1024 * 1024) {
            self.directory = directory
            self.maxBytes = maxBytes
        }
    }

    private struct Manifest: Codable {
        var entries: [String: Entry]

        struct Entry: Codable {
            var size: Int
            var lastAccess: TimeInterval
        }
    }

    private let config: Config
    private let fileManager: FileManager
    private var manifest: Manifest

    public init(config: Config) {
        self.config = config
        self.fileManager = FileManager.default
        self.manifest = Manifest(entries: [:])
        let url = config.directory.appendingPathComponent("manifest.json")
        self.manifest = Self.loadManifest(from: url) ?? Manifest(entries: [:])
    }

    public func loadChunk(regionId: String, tileID: TileID) async throws -> RoadIndexChunk? {
        let url = chunkURL(regionId: regionId, tileID: tileID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let chunk = try RoadIndexReader.loadChunk(regionId: regionId, data: data)
        touch(key: cacheKey(regionId: regionId, tileID: tileID), size: data.count)
        try persistManifest()
        return chunk
    }

    public func saveChunk(regionId: String, tileID: TileID, data: Data) async throws {
        try ensureDirectory()
        try ensureChunkDirectory(regionId: regionId, tileID: tileID)
        let url = chunkURL(regionId: regionId, tileID: tileID)
        try data.write(to: url, options: .atomic)
        touch(key: cacheKey(regionId: regionId, tileID: tileID), size: data.count)
        try enforceLimit()
        try persistManifest()
    }

    public func cachedChunkCount() -> Int {
        manifest.entries.count
    }

    private func chunkURL(regionId: String, tileID: TileID) -> URL {
        config.directory
            .appendingPathComponent(regionId)
            .appendingPathComponent("\(tileID.z)")
            .appendingPathComponent("\(tileID.x)")
            .appendingPathComponent("\(tileID.y).iarc")
    }

    private func cacheKey(regionId: String, tileID: TileID) -> String {
        "\(regionId)_\(tileID.z)_\(tileID.x)_\(tileID.y)"
    }

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: config.directory.path) {
            try fileManager.createDirectory(at: config.directory, withIntermediateDirectories: true)
        }
    }

    private func ensureChunkDirectory(regionId: String, tileID: TileID) throws {
        let dir = config.directory
            .appendingPathComponent(regionId)
            .appendingPathComponent("\(tileID.z)")
            .appendingPathComponent("\(tileID.x)")
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func touch(key: String, size: Int) {
        manifest.entries[key] = Manifest.Entry(size: size, lastAccess: Date().timeIntervalSince1970)
    }

    private func totalSize() -> Int {
        manifest.entries.values.reduce(0) { $0 + $1.size }
    }

    private func enforceLimit() throws {
        var currentSize = totalSize()
        if currentSize <= config.maxBytes { return }

        let sorted = manifest.entries.sorted { $0.value.lastAccess < $1.value.lastAccess }
        for (key, entry) in sorted {
            if currentSize <= config.maxBytes { break }
            if let url = urlFromCacheKey(key) {
                try? fileManager.removeItem(at: url)
            }
            manifest.entries.removeValue(forKey: key)
            currentSize -= entry.size
        }
    }

    private func urlFromCacheKey(_ key: String) -> URL? {
        let parts = key.split(separator: "_")
        guard parts.count == 4 else { return nil }
        let regionId = String(parts[0])
        guard let z = Int(parts[1]), let x = Int(parts[2]), let y = Int(parts[3]) else { return nil }
        return chunkURL(regionId: regionId, tileID: TileID(z: z, x: x, y: y))
    }

    private func manifestURL() -> URL {
        config.directory.appendingPathComponent("manifest.json")
    }

    private static func loadManifest(from url: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private func persistManifest() throws {
        try ensureDirectory()
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL(), options: .atomic)
    }
}

public final class RoadIndexFetcher {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(region: RoadIndexRegion, tileID: TileID) async throws -> Data {
        let url = region.baseURL
            .appendingPathComponent("\(tileID.z)")
            .appendingPathComponent("\(tileID.x)")
            .appendingPathComponent("\(tileID.y).iarc")

        var request = URLRequest(url: url)
        request.setValue("IntersectionAhead/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RoadIndexFetcherError.invalidResponse
        }
        return data
    }
}
