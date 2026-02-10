import Foundation

public struct RoadIndexRegion: Hashable {
    public let id: String
    public let baseURL: URL
    public let chunkZoom: Int
    public let minLat: Double
    public let minLon: Double
    public let maxLat: Double
    public let maxLon: Double

    public init(id: String, baseURL: URL, chunkZoom: Int, minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        self.id = id
        self.baseURL = baseURL
        self.chunkZoom = chunkZoom
        self.minLat = minLat
        self.minLon = minLon
        self.maxLat = maxLat
        self.maxLon = maxLon
    }

    public func contains(_ location: LatLon) -> Bool {
        location.lat >= minLat && location.lat <= maxLat && location.lon >= minLon && location.lon <= maxLon
    }
}

public struct RoadIndexSegment {
    public let name: String
    public let nodeA: Int
    public let nodeB: Int
    public let shapeStart: Int
    public let shapeCount: Int
    public let flags: UInt16
    public let bearingAB: Int16
    public let bearingBA: Int16

    public var isOneway: Bool { (flags & 0x1) != 0 }
    public var isLink: Bool { (flags & 0x2) != 0 }
    public var isRoundabout: Bool { (flags & 0x4) != 0 }
}

public struct RoadIndexNode {
    public let latE7: Int32
    public let lonE7: Int32
    public let edgeStart: Int
    public let edgeCount: Int

    public var lat: Double { Double(latE7) / 1e7 }
    public var lon: Double { Double(lonE7) / 1e7 }
}

public struct RoadIndexCellEntry {
    public let cellId: UInt32
    public let segStart: Int
    public let segCount: Int
}

public struct RoadIndexChunk {
    public let regionId: String
    public let cellSizeMeters: Double
    public let originLat: Double
    public let originLon: Double
    public let gridWidth: Int
    public let gridHeight: Int

    public let strings: [String]
    public let nodes: [RoadIndexNode]
    public let segments: [RoadIndexSegment]
    public let shapes: [LatLon]
    public let nodeEdges: [Int]
    public let cellEntries: [RoadIndexCellEntry]
    public let cellSegments: [Int]
}

public struct RoadIndexMatch: Hashable {
    public let chunkIndex: Int
    public let segmentIndex: Int
    public let name: String
    public let distanceMeters: Double
    public let bearingDegrees: Double
    public let snappedLocation: LatLon
    public let score: Double
}

public struct RoadIndexNext: Hashable {
    public let name: String
    public let segmentIndex: Int
    public let distanceMeters: Double
    public let confidence: Double
}
