import Foundation
import Compression

public enum RoadIndexReaderError: Error {
    case invalidHeader
    case unsupportedVersion
    case decompressionFailed
}

struct RoadIndexBinaryReader {
    let data: Data
    var offset: Int = 0

    mutating func readBytes(_ count: Int) -> Data? {
        guard offset + count <= data.count else { return nil }
        let sub = data.subdata(in: offset..<(offset + count))
        offset += count
        return sub
    }

    mutating func readUInt8() -> UInt8? { readBytes(1)?.first }
    mutating func readUInt16() -> UInt16? {
        guard let bytes = readBytes(2) else { return nil }
        return bytes.withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
    }
    mutating func readInt16() -> Int16? {
        guard let bytes = readBytes(2) else { return nil }
        return bytes.withUnsafeBytes { $0.load(as: Int16.self) }.littleEndian
    }
    mutating func readUInt32() -> UInt32? {
        guard let bytes = readBytes(4) else { return nil }
        return bytes.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    }
    mutating func readInt32() -> Int32? {
        guard let bytes = readBytes(4) else { return nil }
        return bytes.withUnsafeBytes { $0.load(as: Int32.self) }.littleEndian
    }
    mutating func readFloat32() -> Float32? {
        guard let bytes = readBytes(4) else { return nil }
        return bytes.withUnsafeBytes { $0.load(as: Float32.self) }
    }
    mutating func readFloat64() -> Float64? {
        guard let bytes = readBytes(8) else { return nil }
        return bytes.withUnsafeBytes { $0.load(as: Float64.self) }
    }
}

public enum RoadIndexReader {
    public static func loadChunk(regionId: String, data: Data) throws -> RoadIndexChunk {
        let payload = try decodeContainer(data)
        return try parsePayload(regionId: regionId, data: payload)
    }

    private static func decodeContainer(_ data: Data) throws -> Data {
        var reader = RoadIndexBinaryReader(data: data)
        guard let magicData = reader.readBytes(4),
              let magic = String(data: magicData, encoding: .utf8),
              magic == "IARC" else { throw RoadIndexReaderError.invalidHeader }

        guard let version = reader.readUInt16(), version == 1 else { throw RoadIndexReaderError.unsupportedVersion }
        guard let compression = reader.readUInt16() else { throw RoadIndexReaderError.invalidHeader }
        guard let uncompressedSize = reader.readUInt32() else { throw RoadIndexReaderError.invalidHeader }

        guard let payloadData = reader.readBytes(data.count - reader.offset) else {
            throw RoadIndexReaderError.invalidHeader
        }

        if compression == 0 {
            return payloadData
        } else if compression == 1 {
            return try decompressLZFSE(payload: payloadData, expectedSize: Int(uncompressedSize))
        } else {
            throw RoadIndexReaderError.unsupportedVersion
        }
    }

    private static func decompressLZFSE(payload: Data, expectedSize: Int) throws -> Data {
        var dst = Data(count: expectedSize)
        let decoded = dst.withUnsafeMutableBytes { dstPtr in
            payload.withUnsafeBytes { srcPtr in
                compression_decode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                    payload.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        if decoded == 0 { throw RoadIndexReaderError.decompressionFailed }
        return dst
    }

    private static func parsePayload(regionId: String, data: Data) throws -> RoadIndexChunk {
        var reader = RoadIndexBinaryReader(data: data)
        guard let magicData = reader.readBytes(4),
              let magic = String(data: magicData, encoding: .utf8),
              magic == "IAR1" else { throw RoadIndexReaderError.invalidHeader }
        guard let version = reader.readUInt16(), version == 1 else { throw RoadIndexReaderError.unsupportedVersion }
        _ = reader.readUInt16()

        guard let originLat = reader.readFloat64(),
              let originLon = reader.readFloat64(),
              let cellSize = reader.readFloat32(),
              let gridWidth = reader.readUInt16(),
              let gridHeight = reader.readUInt16(),
              let stringsCount = reader.readUInt32(),
              let nodesCount = reader.readUInt32(),
              let segmentsCount = reader.readUInt32(),
              let shapesCount = reader.readUInt32(),
              let nodeEdgesCount = reader.readUInt32(),
              let cellEntriesCount = reader.readUInt32(),
              let cellSegmentsCount = reader.readUInt32(),
              let stringBytes = reader.readUInt32() else {
            throw RoadIndexReaderError.invalidHeader
        }

        var stringOffsets: [Int] = []
        stringOffsets.reserveCapacity(Int(stringsCount) + 1)
        for _ in 0..<(Int(stringsCount) + 1) {
            guard let off = reader.readUInt32() else { throw RoadIndexReaderError.invalidHeader }
            stringOffsets.append(Int(off))
        }
        guard let stringData = reader.readBytes(Int(stringBytes)) else { throw RoadIndexReaderError.invalidHeader }
        var strings: [String] = []
        strings.reserveCapacity(Int(stringsCount))
        for i in 0..<Int(stringsCount) {
            let start = stringOffsets[i]
            let end = stringOffsets[i + 1]
            if start >= end || end > stringData.count { strings.append(""); continue }
            let sub = stringData.subdata(in: start..<end)
            strings.append(String(data: sub, encoding: .utf8) ?? "")
        }

        var nodes: [RoadIndexNode] = []
        nodes.reserveCapacity(Int(nodesCount))
        for _ in 0..<Int(nodesCount) {
            guard let latE7 = reader.readInt32(),
                  let lonE7 = reader.readInt32(),
                  let edgeStart = reader.readUInt32(),
                  let edgeCount = reader.readUInt16() else { throw RoadIndexReaderError.invalidHeader }
            _ = reader.readUInt16()
            nodes.append(RoadIndexNode(latE7: latE7, lonE7: lonE7, edgeStart: Int(edgeStart), edgeCount: Int(edgeCount)))
        }

        var segments: [RoadIndexSegment] = []
        segments.reserveCapacity(Int(segmentsCount))
        for _ in 0..<Int(segmentsCount) {
            guard let nameIndex = reader.readUInt32(),
                  let nodeA = reader.readUInt32(),
                  let nodeB = reader.readUInt32(),
                  let shapeStart = reader.readUInt32(),
                  let shapeCount = reader.readUInt16(),
                  let flags = reader.readUInt16(),
                  let bearingAB = reader.readInt16(),
                  let bearingBA = reader.readInt16() else { throw RoadIndexReaderError.invalidHeader }

            let name = nameIndex < strings.count ? strings[Int(nameIndex)] : ""
            segments.append(RoadIndexSegment(
                name: name,
                nodeA: Int(nodeA),
                nodeB: Int(nodeB),
                shapeStart: Int(shapeStart),
                shapeCount: Int(shapeCount),
                flags: flags,
                bearingAB: bearingAB,
                bearingBA: bearingBA
            ))
        }

        var shapes: [LatLon] = []
        shapes.reserveCapacity(Int(shapesCount))
        for _ in 0..<Int(shapesCount) {
            guard let latE7 = reader.readInt32(), let lonE7 = reader.readInt32() else { throw RoadIndexReaderError.invalidHeader }
            shapes.append(LatLon(lat: Double(latE7) / 1e7, lon: Double(lonE7) / 1e7))
        }

        var nodeEdges: [Int] = []
        nodeEdges.reserveCapacity(Int(nodeEdgesCount))
        for _ in 0..<Int(nodeEdgesCount) {
            guard let segId = reader.readUInt32() else { throw RoadIndexReaderError.invalidHeader }
            nodeEdges.append(Int(segId))
        }

        var cellEntries: [RoadIndexCellEntry] = []
        cellEntries.reserveCapacity(Int(cellEntriesCount))
        for _ in 0..<Int(cellEntriesCount) {
            guard let cellId = reader.readUInt32(),
                  let segStart = reader.readUInt32(),
                  let segCount = reader.readUInt16() else { throw RoadIndexReaderError.invalidHeader }
            _ = reader.readUInt16()
            cellEntries.append(RoadIndexCellEntry(cellId: cellId, segStart: Int(segStart), segCount: Int(segCount)))
        }

        var cellSegments: [Int] = []
        cellSegments.reserveCapacity(Int(cellSegmentsCount))
        for _ in 0..<Int(cellSegmentsCount) {
            guard let segId = reader.readUInt32() else { throw RoadIndexReaderError.invalidHeader }
            cellSegments.append(Int(segId))
        }

        return RoadIndexChunk(
            regionId: regionId,
            cellSizeMeters: Double(cellSize),
            originLat: originLat,
            originLon: originLon,
            gridWidth: Int(gridWidth),
            gridHeight: Int(gridHeight),
            strings: strings,
            nodes: nodes,
            segments: segments,
            shapes: shapes,
            nodeEdges: nodeEdges,
            cellEntries: cellEntries,
            cellSegments: cellSegments
        )
    }
}
