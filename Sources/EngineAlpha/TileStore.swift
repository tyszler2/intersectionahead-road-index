import Foundation

public actor TileStore {
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

    public func load(tileID: TileID) async throws -> RoadTile? {
        let url = tileURL(tileID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let tile = try JSONDecoder().decode(RoadTile.self, from: data)
        touch(tileID: tileID, size: data.count)
        try persistManifest()
        return tile
    }

    public func save(tile: RoadTile, data: Data) async throws {
        try ensureDirectory()
        try ensureTileDirectory(for: tile.tileID)
        let url = tileURL(tile.tileID)
        try data.write(to: url, options: .atomic)
        touch(tileID: tile.tileID, size: data.count)
        try enforceLimit()
        try persistManifest()
    }

    public func save(tile: RoadTile) async throws {
        let data = try JSONEncoder().encode(tile)
        try await save(tile: tile, data: data)
    }

    public func cachedTileIDs() -> [TileID] {
        manifest.entries.keys.compactMap { key in
            let parts = key.split(separator: "_")
            guard parts.count == 3,
                  let z = Int(parts[0]),
                  let x = Int(parts[1]),
                  let y = Int(parts[2]) else { return nil }
            return TileID(z: z, x: x, y: y)
        }
    }

    private func tileURL(_ tileID: TileID) -> URL {
        config.directory.appendingPathComponent("\(tileID.z)").appendingPathComponent("\(tileID.x)").appendingPathComponent("\(tileID.y).json")
    }

    private func ensureDirectory() throws {
        if !fileManager.fileExists(atPath: config.directory.path) {
            try fileManager.createDirectory(at: config.directory, withIntermediateDirectories: true)
        }
    }

    private func ensureTileDirectory(for tileID: TileID) throws {
        let dir = config.directory
            .appendingPathComponent("\(tileID.z)")
            .appendingPathComponent("\(tileID.x)")
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func touch(tileID: TileID, size: Int) {
        manifest.entries[tileID.key] = Manifest.Entry(size: size, lastAccess: Date().timeIntervalSince1970)
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
            guard let tileID = tileIDFromKey(key) else { continue }
            let url = tileURL(tileID)
            try? fileManager.removeItem(at: url)
            manifest.entries.removeValue(forKey: key)
            currentSize -= entry.size
        }
    }

    private func tileIDFromKey(_ key: String) -> TileID? {
        let parts = key.split(separator: "_")
        guard parts.count == 3,
              let z = Int(parts[0]),
              let x = Int(parts[1]),
              let y = Int(parts[2]) else { return nil }
        return TileID(z: z, x: x, y: y)
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
