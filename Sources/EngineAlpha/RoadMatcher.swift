import Foundation

public struct RoadMatch: Hashable {
    public let segmentID: String
    public let roadName: String
    public let distanceMeters: Double
    public let bearingDegrees: Double
    public let snappedLocation: LatLon
    public let score: Double
}

public final class RoadMatcher {
    public struct Config: Hashable {
        public let searchRadiusMeters: Double
        public let bearingWeight: Double
        public let maxBearingDifference: Double

        public init(searchRadiusMeters: Double = 40.0, bearingWeight: Double = 1.5, maxBearingDifference: Double = 70.0) {
            self.searchRadiusMeters = searchRadiusMeters
            self.bearingWeight = bearingWeight
            self.maxBearingDifference = maxBearingDifference
        }
    }

    private let config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    public func match(location: LatLon, headingDegrees: Double?, tiles: [RoadTile]) -> RoadMatch? {
        var best: RoadMatch? = nil
        let heading = headingDegrees.map { Geo.normalizeHeading($0) }

        for tile in tiles {
            for segment in tile.segments {
                guard let hit = RoadGeometry.closestPointOnPolyline(to: location, polyline: segment.polyline) else { continue }
                if hit.distanceMeters > config.searchRadiusMeters { continue }

                let bearingDiff = heading.map { Geo.angularDifference($0, hit.bearingDegrees) } ?? 0.0
                if heading != nil && bearingDiff > config.maxBearingDifference { continue }

                let score = hit.distanceMeters + (bearingDiff * config.bearingWeight)
                if best == nil || score < best!.score {
                    best = RoadMatch(
                        segmentID: segment.id,
                        roadName: segment.name,
                        distanceMeters: hit.distanceMeters,
                        bearingDegrees: hit.bearingDegrees,
                        snappedLocation: hit.point,
                        score: score
                    )
                }
            }
        }

        return best
    }
}
