import Foundation

public final class RoadIndexEngine {
    public struct Config: Hashable {
        public let chunkZoom: Int
        public let chunkRadiusMeters: Double
        public let matcherConfig: RoadIndexMatcher.Config
        public let minUpdateInterval: TimeInterval
        public let switchScoreDelta: Double
        public let stableCount: Int

        public init(chunkZoom: Int = 9,
                    chunkRadiusMeters: Double = 1200.0,
                    matcherConfig: RoadIndexMatcher.Config = RoadIndexMatcher.Config(),
                    minUpdateInterval: TimeInterval = 0.7,
                    switchScoreDelta: Double = 6.0,
                    stableCount: Int = 2) {
            self.chunkZoom = chunkZoom
            self.chunkRadiusMeters = chunkRadiusMeters
            self.matcherConfig = matcherConfig
            self.minUpdateInterval = minUpdateInterval
            self.switchScoreDelta = switchScoreDelta
            self.stableCount = stableCount
        }
    }

    private let store: RoadIndexStore
    private let fetcher: RoadIndexFetcher
    private let regions: [RoadIndexRegion]
    private let matcher: RoadIndexMatcher
    private let config: Config

    private var lastUpdateTime: TimeInterval = 0
    private var lastMatch: RoadIndexMatch? = nil
    private var stabilityCounter: Int = 0

    public init(store: RoadIndexStore, fetcher: RoadIndexFetcher, regions: [RoadIndexRegion], config: Config = Config()) {
        self.store = store
        self.fetcher = fetcher
        self.regions = regions
        self.config = config
        self.matcher = RoadIndexMatcher(config: config.matcherConfig)
    }

    public func update(location: LatLon, headingDegrees: Double?) async throws -> (on: RoadIndexMatch?, next: RoadIndexNext?) {
        let now = Date().timeIntervalSince1970
        if now - lastUpdateTime < config.minUpdateInterval {
            return (lastMatch, nil)
        }
        lastUpdateTime = now

        guard let region = regions.first(where: { $0.contains(location) }) else {
            return (nil, nil)
        }

        let chunkTile = TileID.from(latLon: location, zoom: region.chunkZoom)
        let neighborhood = chunkTile.neighbors(radiusMeters: config.chunkRadiusMeters, at: location)
        var chunks: [RoadIndexChunk] = []

        for tile in neighborhood {
            if let cached = try await store.loadChunk(regionId: region.id, tileID: tile) {
                chunks.append(cached)
            } else {
                let data = try await fetcher.fetch(region: region, tileID: tile)
                try await store.saveChunk(regionId: region.id, tileID: tile, data: data)
                let chunk = try RoadIndexReader.loadChunk(regionId: region.id, data: data)
                chunks.append(chunk)
            }
        }

        guard let best = matcher.matchOn(location: location, headingDegrees: headingDegrees, chunks: chunks) else {
            lastMatch = nil
            stabilityCounter = 0
            return (nil, nil)
        }

        let accepted: RoadIndexMatch
        if let prev = lastMatch {
            if best.segmentIndex == prev.segmentIndex {
                stabilityCounter += 1
                accepted = best
            } else if best.score + config.switchScoreDelta < prev.score {
                stabilityCounter = 1
                accepted = best
            } else if stabilityCounter >= config.stableCount {
                stabilityCounter = 1
                accepted = best
            } else {
                accepted = prev
                stabilityCounter += 1
            }
        } else {
            accepted = best
            stabilityCounter = 1
        }

        lastMatch = accepted

        let next = (accepted.chunkIndex >= 0 && accepted.chunkIndex < chunks.count) ? matcher.matchNext(current: accepted, headingDegrees: headingDegrees, chunk: chunks[accepted.chunkIndex]) : nil
        return (accepted, next)
    }
}
