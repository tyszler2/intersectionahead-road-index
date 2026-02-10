import Foundation

struct MVTValue {
    var string: String?
}

struct MVTFeature {
    var id: UInt64?
    var tags: [UInt32]
    var type: Int
    var geometry: [UInt32]
}

struct MVTLayer {
    var name: String
    var features: [MVTFeature]
    var keys: [String]
    var values: [MVTValue]
    var extent: Int
}

enum MVTError: Error {
    case invalidTile
}

struct MVTReader {
    private var data: Data
    private var index: Data.Index

    init(data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    mutating func isAtEnd() -> Bool {
        index >= data.endIndex
    }

    mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.endIndex {
            let byte = data[index]
            index = data.index(after: index)
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    mutating func readBytes(length: Int) -> Data? {
        guard index.advanced(by: length) <= data.endIndex else { return nil }
        let sub = data[index..<index.advanced(by: length)]
        index = index.advanced(by: length)
        return Data(sub)
    }

    mutating func readKey() -> (field: Int, wire: Int)? {
        guard let key = readVarint() else { return nil }
        let field = Int(key >> 3)
        let wire = Int(key & 0x7)
        return (field, wire)
    }

    mutating func readLengthDelimited() -> Data? {
        guard let len = readVarint() else { return nil }
        return readBytes(length: Int(len))
    }
}

enum MVTParser {
    static func parseTile(data: Data) throws -> [MVTLayer] {
        var reader = MVTReader(data: data)
        var layers: [MVTLayer] = []

        while !reader.isAtEnd() {
            guard let key = reader.readKey() else { break }
            if key.field == 3 && key.wire == 2 {
                guard let layerData = reader.readLengthDelimited() else { continue }
                if let layer = parseLayer(data: layerData) {
                    layers.append(layer)
                }
            } else {
                _ = skipField(reader: &reader, wire: key.wire)
            }
        }

        return layers
    }

    private static func parseLayer(data: Data) -> MVTLayer? {
        var reader = MVTReader(data: data)
        var name: String = ""
        var features: [MVTFeature] = []
        var keys: [String] = []
        var values: [MVTValue] = []
        var extent: Int = 4096

        while !reader.isAtEnd() {
            guard let key = reader.readKey() else { break }
            switch key.field {
            case 1:
                if let bytes = reader.readLengthDelimited(), let str = String(data: bytes, encoding: .utf8) {
                    name = str
                }
            case 2:
                if let bytes = reader.readLengthDelimited(), let feature = parseFeature(data: bytes) {
                    features.append(feature)
                }
            case 3:
                if let bytes = reader.readLengthDelimited(), let str = String(data: bytes, encoding: .utf8) {
                    keys.append(str)
                }
            case 4:
                if let bytes = reader.readLengthDelimited() {
                    let value = parseValue(data: bytes)
                    values.append(value)
                }
            case 5:
                if let v = reader.readVarint() {
                    extent = Int(v)
                }
            default:
                _ = skipField(reader: &reader, wire: key.wire)
            }
        }

        guard !name.isEmpty else { return nil }
        return MVTLayer(name: name, features: features, keys: keys, values: values, extent: extent)
    }

    private static func parseFeature(data: Data) -> MVTFeature? {
        var reader = MVTReader(data: data)
        var id: UInt64? = nil
        var tags: [UInt32] = []
        var type: Int = 0
        var geometry: [UInt32] = []

        while !reader.isAtEnd() {
            guard let key = reader.readKey() else { break }
            switch key.field {
            case 1:
                id = reader.readVarint()
            case 2:
                if let bytes = reader.readLengthDelimited() {
                    tags = readPackedUInt32(bytes: bytes)
                }
            case 3:
                if let v = reader.readVarint() { type = Int(v) }
            case 4:
                if let bytes = reader.readLengthDelimited() {
                    geometry = readPackedUInt32(bytes: bytes)
                }
            default:
                _ = skipField(reader: &reader, wire: key.wire)
            }
        }

        return MVTFeature(id: id, tags: tags, type: type, geometry: geometry)
    }

    private static func parseValue(data: Data) -> MVTValue {
        var reader = MVTReader(data: data)
        var value = MVTValue(string: nil)

        while !reader.isAtEnd() {
            guard let key = reader.readKey() else { break }
            if key.field == 1, key.wire == 2 {
                if let bytes = reader.readLengthDelimited(), let str = String(data: bytes, encoding: .utf8) {
                    value.string = str
                }
            } else {
                _ = skipField(reader: &reader, wire: key.wire)
            }
        }

        return value
    }

    private static func skipField(reader: inout MVTReader, wire: Int) -> Bool {
        switch wire {
        case 0:
            _ = reader.readVarint()
            return true
        case 2:
            _ = reader.readLengthDelimited()
            return true
        case 5:
            _ = reader.readBytes(length: 4)
            return true
        case 1:
            _ = reader.readBytes(length: 8)
            return true
        default:
            return false
        }
    }

    private static func readPackedUInt32(bytes: Data) -> [UInt32] {
        var r = MVTReader(data: bytes)
        var out: [UInt32] = []
        while !r.isAtEnd() {
            if let v = r.readVarint() { out.append(UInt32(v)) }
        }
        return out
    }
}

enum MVTGeometry {
    static func decodeLineStrings(geometry: [UInt32]) -> [[(Int, Int)]] {
        var lines: [[(Int, Int)]] = []
        var line: [(Int, Int)] = []
        var x = 0
        var y = 0
        var i = 0

        func flushLine() {
            if line.count >= 2 { lines.append(line) }
            line.removeAll(keepingCapacity: true)
        }

        while i < geometry.count {
            let cmd = geometry[i]
            i += 1
            let id = Int(cmd & 0x7)
            let count = Int(cmd >> 3)

            switch id {
            case 1: // MoveTo
                flushLine()
                for _ in 0..<count {
                    if i + 1 >= geometry.count { break }
                    let dx = zigzagDecode(geometry[i]); i += 1
                    let dy = zigzagDecode(geometry[i]); i += 1
                    x += dx
                    y += dy
                    line.append((x, y))
                }
            case 2: // LineTo
                for _ in 0..<count {
                    if i + 1 >= geometry.count { break }
                    let dx = zigzagDecode(geometry[i]); i += 1
                    let dy = zigzagDecode(geometry[i]); i += 1
                    x += dx
                    y += dy
                    line.append((x, y))
                }
            case 7: // ClosePath
                break
            default:
                break
            }
        }

        flushLine()
        return lines
    }

    private static func zigzagDecode(_ n: UInt32) -> Int {
        // ((n >> 1) ^ (-(n & 1))) without overflow
        let shifted = Int32(bitPattern: n >> 1)
        let mask = Int32(bitPattern: n & 1)
        let value = shifted ^ -mask
        return Int(value)
    }
}

enum MVTRoadExtractor {
    static let allowedClasses: Set<String> = [
        "motorway", "trunk", "primary", "secondary", "tertiary",
        "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link",
        "residential", "unclassified", "living_street", "service", "road"
    ]

    static func roadTile(from data: Data, tileID: TileID) throws -> RoadTile {
        let layers = try MVTParser.parseTile(data: data)
        let transportation = layers.first(where: { $0.name == "transportation" })
        let transportationName = layers.first(where: { $0.name == "transportation_name" })

        var segments: [RoadSegment] = []
        var usedNamedGeometries: Set<String> = []

        if let nameLayer = transportationName {
            for (idx, feature) in nameLayer.features.enumerated() {
                if feature.type != 2 { continue }
                let tags = decodeTags(feature: feature, keys: nameLayer.keys, values: nameLayer.values)
                let name = tags["name"] ?? tags["name:en"] ?? tags["ref"] ?? ""
                if name.isEmpty { continue }

                let roadClass = tags["class"] ?? ""
                if !roadClass.isEmpty && !allowedClasses.contains(roadClass) { continue }

                let oneWayValue = tags["oneway"] ?? ""
                let oneWay = oneWayValue == "1" || oneWayValue.lowercased() == "yes" || oneWayValue == "-1"

                let lines = MVTGeometry.decodeLineStrings(geometry: feature.geometry)
                for (lineIndex, line) in lines.enumerated() {
                    let polyline = line.map { tilePointToLatLon(x: $0.0, y: $0.1, extent: nameLayer.extent, tileID: tileID) }
                    if polyline.count < 2 { continue }
                    let fid = feature.id.map { "n_\($0)" } ?? "n_\(idx)_\(lineIndex)"
                    segments.append(RoadSegment(id: fid, name: name, polyline: polyline, oneWay: oneWay))
                    usedNamedGeometries.insert(fid)
                }
            }
        }

        if let layer = transportation {
            for (idx, feature) in layer.features.enumerated() {
                if feature.type != 2 { continue }

                let tags = decodeTags(feature: feature, keys: layer.keys, values: layer.values)
                let roadClass = tags["class"] ?? ""
                if !allowedClasses.contains(roadClass) { continue }

                let name = tags["name"] ?? tags["name:en"] ?? tags["ref"] ?? ""

                let oneWayValue = tags["oneway"] ?? ""
                let oneWay = oneWayValue == "1" || oneWayValue.lowercased() == "yes" || oneWayValue == "-1"

                let lines = MVTGeometry.decodeLineStrings(geometry: feature.geometry)
                for (lineIndex, line) in lines.enumerated() {
                    let polyline = line.map { tilePointToLatLon(x: $0.0, y: $0.1, extent: layer.extent, tileID: tileID) }
                    if polyline.count < 2 { continue }
                    let fid = feature.id.map { "t_\($0)" } ?? "t_\(idx)_\(lineIndex)"
                    if usedNamedGeometries.contains(fid) { continue }
                    let displayName = name.isEmpty ? "Unnamed road" : name
                    segments.append(RoadSegment(id: fid, name: displayName, polyline: polyline, oneWay: oneWay))
                }
            }
        }

        return RoadTile(tileID: tileID, segments: segments)
    }

    private static func decodeTags(feature: MVTFeature, keys: [String], values: [MVTValue]) -> [String: String] {
        var out: [String: String] = [:]
        var i = 0
        while i + 1 < feature.tags.count {
            let kIndex = Int(feature.tags[i])
            let vIndex = Int(feature.tags[i + 1])
            i += 2
            if kIndex < keys.count, vIndex < values.count {
                let key = keys[kIndex]
                let val = values[vIndex].string ?? ""
                out[key] = val
            }
        }
        return out
    }

    private static func tilePointToLatLon(x: Int, y: Int, extent: Int, tileID: TileID) -> LatLon {
        let n = Double(1 << tileID.z)
        let xf = (Double(tileID.x) + (Double(x) / Double(extent))) / n
        let yf = (Double(tileID.y) + (Double(y) / Double(extent))) / n

        let lon = xf * 360.0 - 180.0
        let latRad = atan(sinh(Double.pi * (1.0 - 2.0 * yf)))
        let lat = Geo.degrees(latRad)
        return LatLon(lat: lat, lon: lon)
    }
}
