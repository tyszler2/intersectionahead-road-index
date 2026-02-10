import Foundation

public struct TileID: Codable, Hashable, CustomStringConvertible {
    public let z: Int
    public let x: Int
    public let y: Int

    public init(z: Int, x: Int, y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }

    public var description: String {
        "\(z)/\(x)/\(y)"
    }

    public static func from(latLon: LatLon, zoom: Int) -> TileID {
        let latRad = Geo.radians(latLon.lat)
        let n = Double(1 << zoom)
        let x = Int(floor((latLon.lon + 180.0) / 360.0 * n))
        let y = Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / Double.pi) / 2.0 * n))
        return TileID(z: zoom, x: x, y: y)
    }

    public func neighbors(radiusMeters: Double, at location: LatLon) -> [TileID] {
        let metersPerLat = Geo.metersPerDegreeLat(at: location.lat)
        let metersPerLon = Geo.metersPerDegreeLon(at: location.lat)
        let dLat = radiusMeters / metersPerLat
        let dLon = radiusMeters / metersPerLon

        let minLat = location.lat - dLat
        let maxLat = location.lat + dLat
        let minLon = location.lon - dLon
        let maxLon = location.lon + dLon

        let minTile = TileID.from(latLon: LatLon(lat: minLat, lon: minLon), zoom: z)
        let maxTile = TileID.from(latLon: LatLon(lat: maxLat, lon: maxLon), zoom: z)

        let maxIndex = (1 << z) - 1
        let minX = max(0, min(minTile.x, maxTile.x))
        let maxX = min(maxIndex, max(minTile.x, maxTile.x))
        let minY = max(0, min(minTile.y, maxTile.y))
        let maxY = min(maxIndex, max(minTile.y, maxTile.y))

        var tiles: [TileID] = []
        if minX <= maxX && minY <= maxY {
            for tx in minX...maxX {
                for ty in minY...maxY {
                    tiles.append(TileID(z: z, x: tx, y: ty))
                }
            }
        }
        return tiles
    }

    public var key: String {
        "\(z)_\(x)_\(y)"
    }
}
