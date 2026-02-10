import Foundation

public struct NextRoad: Hashable {
    public let roadName: String
    public let segmentID: String
    public let confidence: Double
}

public final class NextPredictor {
    public struct Config: Hashable {
        public let lookaheadMeters: Double
        public let intersectionRadiusMeters: Double
        public let maxBearingDifference: Double

        public init(lookaheadMeters: Double = 30.0, intersectionRadiusMeters: Double = 18.0, maxBearingDifference: Double = 90.0) {
            self.lookaheadMeters = lookaheadMeters
            self.intersectionRadiusMeters = intersectionRadiusMeters
            self.maxBearingDifference = maxBearingDifference
        }
    }

    private let config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    public func predictNext(current: RoadMatch, headingDegrees: Double?, tiles: [RoadTile]) -> NextRoad? {
        guard let heading = headingDegrees.map({ Geo.normalizeHeading($0) }) else { return nil }
        let probePoint = Geo.pointAlongHeading(origin: current.snappedLocation, headingDegrees: heading, distanceMeters: config.lookaheadMeters)

        var best: NextRoad? = nil

        for tile in tiles {
            for segment in tile.segments {
                if segment.id == current.segmentID { continue }
                if segment.name == current.roadName { continue }

                guard let hit = RoadGeometry.closestPointOnPolyline(to: probePoint, polyline: segment.polyline) else { continue }
                if hit.distanceMeters > config.intersectionRadiusMeters { continue }

                let bearingDiff = Geo.angularDifference(heading, hit.bearingDegrees)
                if bearingDiff > config.maxBearingDifference { continue }

                let confidence = max(0.0, 1.0 - (bearingDiff / config.maxBearingDifference))
                if best == nil || confidence > best!.confidence {
                    best = NextRoad(roadName: segment.name, segmentID: segment.id, confidence: confidence)
                }
            }
        }

        return best
    }
}
