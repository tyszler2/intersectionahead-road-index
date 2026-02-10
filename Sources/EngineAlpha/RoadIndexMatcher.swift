import Foundation

public final class RoadIndexMatcher {
    public struct Config: Hashable {
        public let searchRadiusMeters: Double
        public let bearingWeight: Double
        public let maxBearingDifference: Double
        public let nextDistanceMeters: Double
        public let nextHeadingTolerance: Double
        public let linkPenalty: Double

        public init(searchRadiusMeters: Double = 70.0,
                    bearingWeight: Double = 1.4,
                    maxBearingDifference: Double = 60.0,
                    nextDistanceMeters: Double = 160.0,
                    nextHeadingTolerance: Double = 50.0,
                    linkPenalty: Double = 12.0) {
            self.searchRadiusMeters = searchRadiusMeters
            self.bearingWeight = bearingWeight
            self.maxBearingDifference = maxBearingDifference
            self.nextDistanceMeters = nextDistanceMeters
            self.nextHeadingTolerance = nextHeadingTolerance
            self.linkPenalty = linkPenalty
        }
    }

    private let config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    public func matchOn(location: LatLon, headingDegrees: Double?, chunks: [RoadIndexChunk]) -> RoadIndexMatch? {
        let heading = headingDegrees.map { Geo.normalizeHeading($0) }
        var best: RoadIndexMatch? = nil

        let candidates = RoadIndexMatcher.collectCandidateSegments(location: location, chunks: chunks)
        for (chunkIndex, chunk, segIndex) in candidates {
            let segment = chunk.segments[segIndex]
            let polyline = RoadIndexMatcher.polyline(for: segment, in: chunk)
            guard let hit = RoadGeometry.closestPointOnPolyline(to: location, polyline: polyline) else { continue }
            if hit.distanceMeters > config.searchRadiusMeters { continue }

            let bearingDiff = heading.map { Geo.angularDifference($0, hit.bearingDegrees) } ?? 0.0
            if heading != nil && bearingDiff > config.maxBearingDifference { continue }

            let score = hit.distanceMeters + (bearingDiff * config.bearingWeight)
            if best == nil || score < best!.score {
                best = RoadIndexMatch(
                    chunkIndex: chunkIndex,
                    segmentIndex: segIndex,
                    name: segment.name,
                    distanceMeters: hit.distanceMeters,
                    bearingDegrees: hit.bearingDegrees,
                    snappedLocation: hit.point,
                    score: score
                )
            }
        }

        return best
    }

    public func matchNext(current: RoadIndexMatch, headingDegrees: Double?, chunk: RoadIndexChunk) -> RoadIndexNext? {
        guard let heading = headingDegrees.map({ Geo.normalizeHeading($0) }) else { return nil }
        let segment = chunk.segments[current.segmentIndex]

        let bearingDiffAB = Geo.angularDifference(heading, Double(segment.bearingAB))
        let bearingDiffBA = Geo.angularDifference(heading, Double(segment.bearingBA))
        let forwardNodeIndex = bearingDiffAB <= bearingDiffBA ? segment.nodeB : segment.nodeA

        let forwardNode = chunk.nodes[forwardNodeIndex]
        let nodeLatLon = LatLon(lat: forwardNode.lat, lon: forwardNode.lon)
        let distanceToNode = Geo.haversineMeters(current.snappedLocation, nodeLatLon)
        if distanceToNode > config.nextDistanceMeters { return nil }

        let forwardProbe = Geo.pointAlongHeading(origin: current.snappedLocation, headingDegrees: heading, distanceMeters: 20)
        let toNodeBearing = Geo.bearingDegrees(from: current.snappedLocation, to: nodeLatLon)
        let forwardDiff = Geo.angularDifference(heading, toNodeBearing)
        if forwardDiff > config.nextHeadingTolerance { return nil }
        // Dot-product forward test: ensure intersection is ahead of travel direction
        let vHeading = Geo.projectToLocalMeters(origin: current.snappedLocation, point: forwardProbe)
        let vToNode = Geo.projectToLocalMeters(origin: current.snappedLocation, point: nodeLatLon)
        let dot = (vHeading.x * vToNode.x) + (vHeading.y * vToNode.y)
        if dot <= 0 { return nil }

        var best: RoadIndexNext? = nil
        var bestScore: Double = Double.greatestFiniteMagnitude
        let edgeStart = forwardNode.edgeStart
        let edgeEnd = edgeStart + forwardNode.edgeCount

        for i in edgeStart..<edgeEnd {
            let segId = chunk.nodeEdges[i]
            if segId == current.segmentIndex { continue }
            let candidate = chunk.segments[segId]
            if candidate.name == current.name { continue }

            let candidateBearing = segmentBearingAway(from: forwardNodeIndex, segment: candidate, chunk: chunk)
            let candidateDiff = Geo.angularDifference(heading, candidateBearing)
            if candidateDiff > config.nextHeadingTolerance { continue }

            let linkPenalty = candidate.isLink ? config.linkPenalty : 0.0
            let confidence = max(0.0, 1.0 - (candidateDiff / config.nextHeadingTolerance))
            let score = distanceToNode + (candidateDiff * 0.8) + linkPenalty

            if score < bestScore {
                bestScore = score
                best = RoadIndexNext(name: candidate.name, segmentIndex: segId, distanceMeters: score, confidence: confidence)
            }
        }

        return best
    }

    private func segmentBearingAway(from nodeIndex: Int, segment: RoadIndexSegment, chunk: RoadIndexChunk) -> Double {
        if segment.nodeA == nodeIndex {
            return Double(segment.bearingAB)
        } else {
            return Double(segment.bearingBA)
        }
    }

    static func collectCandidateSegments(location: LatLon, chunks: [RoadIndexChunk]) -> [(Int, RoadIndexChunk, Int)] {
        var results: [(Int, RoadIndexChunk, Int)] = []
        for (chunkIndex, chunk) in chunks.enumerated() {
            let (cx, cy) = cellXYFor(location: location, chunk: chunk)
            for dx in -1...1 {
                for dy in -1...1 {
                    let x = cx + dx
                    let y = cy + dy
                    if x < 0 || y < 0 || x >= chunk.gridWidth || y >= chunk.gridHeight { continue }
                    let cellId = cellIdFrom(x: x, y: y)
                    if let entry = cellEntry(for: cellId, in: chunk) {
                        let start = entry.segStart
                        let end = start + entry.segCount
                        for i in start..<end {
                            results.append((chunkIndex, chunk, chunk.cellSegments[i]))
                        }
                    }
                }
            }
        }
        return results
    }

    static func polyline(for segment: RoadIndexSegment, in chunk: RoadIndexChunk) -> [LatLon] {
        if segment.shapeCount > 0 {
            let start = segment.shapeStart
            let end = start + segment.shapeCount
            return Array(chunk.shapes[start..<end])
        }
        let a = chunk.nodes[segment.nodeA]
        let b = chunk.nodes[segment.nodeB]
        return [LatLon(lat: a.lat, lon: a.lon), LatLon(lat: b.lat, lon: b.lon)]
    }

    static func cellIdFor(location: LatLon, chunk: RoadIndexChunk) -> UInt32 {
        let metersPerLat = Geo.metersPerDegreeLat(at: chunk.originLat)
        let metersPerLon = Geo.metersPerDegreeLon(at: chunk.originLat)
        let dx = (location.lon - chunk.originLon) * metersPerLon
        let dy = (location.lat - chunk.originLat) * metersPerLat
        let x = max(0, Int(floor(dx / chunk.cellSizeMeters)))
        let y = max(0, Int(floor(dy / chunk.cellSizeMeters)))
        let clampedX = min(x, chunk.gridWidth - 1)
        let clampedY = min(y, chunk.gridHeight - 1)
        return UInt32((clampedX << 16) | clampedY)
    }

    static func cellXYFor(location: LatLon, chunk: RoadIndexChunk) -> (Int, Int) {
        let metersPerLat = Geo.metersPerDegreeLat(at: chunk.originLat)
        let metersPerLon = Geo.metersPerDegreeLon(at: chunk.originLat)
        let dx = (location.lon - chunk.originLon) * metersPerLon
        let dy = (location.lat - chunk.originLat) * metersPerLat
        let x = max(0, min(Int(floor(dx / chunk.cellSizeMeters)), chunk.gridWidth - 1))
        let y = max(0, min(Int(floor(dy / chunk.cellSizeMeters)), chunk.gridHeight - 1))
        return (x, y)
    }

    static func cellIdFrom(x: Int, y: Int) -> UInt32 {
        UInt32((x << 16) | y)
    }

    static func cellEntry(for cellId: UInt32, in chunk: RoadIndexChunk) -> RoadIndexCellEntry? {
        var low = 0
        var high = chunk.cellEntries.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let entry = chunk.cellEntries[mid]
            if entry.cellId == cellId { return entry }
            if entry.cellId < cellId {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }
}
