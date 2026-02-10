import Foundation

public final class EngineAlpha {
    public struct Config: Hashable {
        public let tileZoom: Int
        public let tileRadiusMeters: Double
        public let matcherConfig: RoadMatcher.Config
        public let predictorConfig: NextPredictor.Config

        public init(tileZoom: Int = 16, tileRadiusMeters: Double = 500.0, matcherConfig: RoadMatcher.Config = RoadMatcher.Config(), predictorConfig: NextPredictor.Config = NextPredictor.Config()) {
            self.tileZoom = tileZoom
            self.tileRadiusMeters = tileRadiusMeters
            self.matcherConfig = matcherConfig
            self.predictorConfig = predictorConfig
        }
    }

    private let store: TileStore
    private let fetcher: RoadTileFetcher?
    private let matcher: RoadMatcher
    private let predictor: NextPredictor
    private let config: Config
    private var lastFetchAttempt: [String: TimeInterval] = [:]
    private let minFetchInterval: TimeInterval = 60

    public init(store: TileStore, fetcher: RoadTileFetcher? = nil, config: Config = Config()) {
        self.store = store
        self.fetcher = fetcher
        self.config = config
        self.matcher = RoadMatcher(config: config.matcherConfig)
        self.predictor = NextPredictor(config: config.predictorConfig)
    }

    public func update(location: LatLon, headingDegrees: Double?) async throws -> (onRoad: RoadMatch?, nextRoad: NextRoad?) {
        let tileID = TileID.from(latLon: location, zoom: config.tileZoom)
        let neighborhood = tileID.neighbors(radiusMeters: config.tileRadiusMeters, at: location)

        var tiles: [RoadTile] = []
        for id in neighborhood {
            if let cached = try await store.load(tileID: id) {
                tiles.append(cached)
            } else if let fetcher = fetcher {
                let key = id.key
                let now = Date().timeIntervalSince1970
                if let last = lastFetchAttempt[key], now - last < minFetchInterval {
                    continue
                }
                lastFetchAttempt[key] = now
                let fetched = try await fetcher.fetchAndStore(tileID: id, store: store)
                tiles.append(fetched)
            }
        }

        let onRoad = matcher.match(location: location, headingDegrees: headingDegrees, tiles: tiles)
        let nextRoad = onRoad.flatMap { predictor.predictNext(current: $0, headingDegrees: headingDegrees, tiles: tiles) }
        return (onRoad, nextRoad)
    }
}
