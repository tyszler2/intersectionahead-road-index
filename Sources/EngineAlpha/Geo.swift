import Foundation

public struct LatLon: Codable, Hashable {
    public let lat: Double
    public let lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

public enum Geo {
    public static let earthRadiusMeters: Double = 6_371_000

    public static func radians(_ degrees: Double) -> Double {
        degrees * Double.pi / 180.0
    }

    public static func degrees(_ radians: Double) -> Double {
        radians * 180.0 / Double.pi
    }

    public static func normalizeHeading(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360.0)
        return d >= 0 ? d : d + 360.0
    }

    public static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let diff = abs(normalizeHeading(a) - normalizeHeading(b))
        return diff > 180.0 ? 360.0 - diff : diff
    }

    public static func haversineMeters(_ a: LatLon, _ b: LatLon) -> Double {
        let dLat = radians(b.lat - a.lat)
        let dLon = radians(b.lon - a.lon)
        let rLat1 = radians(a.lat)
        let rLat2 = radians(b.lat)

        let sinDLat = sin(dLat / 2.0)
        let sinDLon = sin(dLon / 2.0)
        let h = sinDLat * sinDLat + cos(rLat1) * cos(rLat2) * sinDLon * sinDLon
        return 2.0 * earthRadiusMeters * asin(sqrt(h))
    }

    public static func bearingDegrees(from: LatLon, to: LatLon) -> Double {
        let lat1 = radians(from.lat)
        let lat2 = radians(to.lat)
        let dLon = radians(to.lon - from.lon)

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let brng = atan2(y, x)
        return normalizeHeading(degrees(brng))
    }

    public static func metersPerDegreeLat(at lat: Double) -> Double {
        let rad = radians(lat)
        return 111_132.954 - 559.822 * cos(2 * rad) + 1.175 * cos(4 * rad)
    }

    public static func metersPerDegreeLon(at lat: Double) -> Double {
        let rad = radians(lat)
        return 111_132.954 * cos(rad)
    }

    public static func projectToLocalMeters(origin: LatLon, point: LatLon) -> (x: Double, y: Double) {
        let metersPerLat = metersPerDegreeLat(at: origin.lat)
        let metersPerLon = metersPerDegreeLon(at: origin.lat)
        let dx = (point.lon - origin.lon) * metersPerLon
        let dy = (point.lat - origin.lat) * metersPerLat
        return (dx, dy)
    }

    public static func pointAlongHeading(origin: LatLon, headingDegrees: Double, distanceMeters: Double) -> LatLon {
        let headingRad = radians(headingDegrees)
        let metersPerLat = metersPerDegreeLat(at: origin.lat)
        let metersPerLon = metersPerDegreeLon(at: origin.lat)
        let dLat = (cos(headingRad) * distanceMeters) / metersPerLat
        let dLon = (sin(headingRad) * distanceMeters) / metersPerLon
        return LatLon(lat: origin.lat + dLat, lon: origin.lon + dLon)
    }
}
