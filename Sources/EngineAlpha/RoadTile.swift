import Foundation

public struct RoadSegment: Codable, Hashable {
    public let id: String
    public let name: String
    public let polyline: [LatLon]
    public let oneWay: Bool

    public init(id: String, name: String, polyline: [LatLon], oneWay: Bool) {
        self.id = id
        self.name = name
        self.polyline = polyline
        self.oneWay = oneWay
    }
}

public struct RoadTile: Codable, Hashable {
    public let tileID: TileID
    public let segments: [RoadSegment]

    public init(tileID: TileID, segments: [RoadSegment]) {
        self.tileID = tileID
        self.segments = segments
    }
}

public struct SegmentHit: Hashable {
    public let segment: RoadSegment
    public let distanceMeters: Double
    public let bearingDegrees: Double
    public let snappedPoint: LatLon
}

public enum RoadGeometry {
    public static func closestPointOnPolyline(to location: LatLon, polyline: [LatLon]) -> (point: LatLon, distanceMeters: Double, bearingDegrees: Double)? {
        guard polyline.count >= 2 else { return nil }
        var best: (LatLon, Double, Double)? = nil

        for idx in 0..<(polyline.count - 1) {
            let a = polyline[idx]
            let b = polyline[idx + 1]
            if let hit = closestPointOnSegment(to: location, a: a, b: b) {
                if best == nil || hit.distanceMeters < best!.1 {
                    best = (hit.point, hit.distanceMeters, hit.bearingDegrees)
                }
            }
        }

        return best.map { (point: $0.0, distanceMeters: $0.1, bearingDegrees: $0.2) }
    }

    public static func closestPointOnSegment(to location: LatLon, a: LatLon, b: LatLon) -> (point: LatLon, distanceMeters: Double, bearingDegrees: Double)? {
        let origin = location
        let ap = Geo.projectToLocalMeters(origin: origin, point: a)
        let bp = Geo.projectToLocalMeters(origin: origin, point: b)
        let p = (x: 0.0, y: 0.0)

        let ab = (x: bp.x - ap.x, y: bp.y - ap.y)
        let apVec = (x: p.x - ap.x, y: p.y - ap.y)
        let abLen2 = ab.x * ab.x + ab.y * ab.y
        if abLen2 == 0 { return nil }

        var t = (apVec.x * ab.x + apVec.y * ab.y) / abLen2
        t = max(0.0, min(1.0, t))

        let closest = (x: ap.x + ab.x * t, y: ap.y + ab.y * t)
        let distance = sqrt(closest.x * closest.x + closest.y * closest.y)

        let closestLat = origin.lat + closest.y / Geo.metersPerDegreeLat(at: origin.lat)
        let closestLon = origin.lon + closest.x / Geo.metersPerDegreeLon(at: origin.lat)
        let closestPoint = LatLon(lat: closestLat, lon: closestLon)

        let bearing = Geo.bearingDegrees(from: a, to: b)
        return (closestPoint, distance, bearing)
    }
}
