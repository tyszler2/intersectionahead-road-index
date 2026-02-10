import Foundation
import EngineAlpha

struct Args {
    var chunkPath: String = ""
    var lat: Double?
    var lon: Double?
    var heading: Double?
    var gpxPath: String?
}

func parseArgs() -> Args {
    var args = Args()
    var iter = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = iter.next() {
        switch arg {
        case "--chunk":
            args.chunkPath = iter.next() ?? ""
        case "--lat":
            args.lat = Double(iter.next() ?? "")
        case "--lon":
            args.lon = Double(iter.next() ?? "")
        case "--heading":
            args.heading = Double(iter.next() ?? "")
        case "--gpx":
            args.gpxPath = iter.next()
        default:
            break
        }
    }
    return args
}

func loadChunk(path: String) throws -> RoadIndexChunk {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    return try RoadIndexReader.loadChunk(regionId: "local", data: data)
}

final class GPXParser: NSObject, XMLParserDelegate {
    private(set) var points: [(Double, Double, Double?)] = []
    private var currentLat: Double?
    private var currentLon: Double?

    func parse(_ url: URL) -> [(Double, Double, Double?)] {
        let parser = XMLParser(contentsOf: url)!
        parser.delegate = self
        parser.parse()
        return points
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "trkpt" || elementName == "rtept" {
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if (elementName == "trkpt" || elementName == "rtept"), let lat = currentLat, let lon = currentLon {
            points.append((lat, lon, nil))
            currentLat = nil
            currentLon = nil
        }
    }
}

func runPointQuery(chunk: RoadIndexChunk, lat: Double, lon: Double, heading: Double?) {
    let matcher = RoadIndexMatcher()
    let match = matcher.matchOn(location: LatLon(lat: lat, lon: lon), headingDegrees: heading, chunks: [chunk])
    let next = match.flatMap { matcher.matchNext(current: $0, headingDegrees: heading, chunk: chunk) }
    print("ON: \(match?.name ?? "—")")
    print("NEXT: \(next?.name ?? "—")")
}

let args = parseArgs()
if args.chunkPath.isEmpty {
    print("Usage: RoadIndexCLI --chunk /path/to/file.iarc --lat <lat> --lon <lon> --heading <deg>")
    print("   or: RoadIndexCLI --chunk /path/to/file.iarc --gpx /path/to/track.gpx")
    exit(1)
}

do {
    let chunk = try loadChunk(path: args.chunkPath)
    if let gpx = args.gpxPath {
        let parser = GPXParser()
        let points = parser.parse(URL(fileURLWithPath: gpx))
        for (lat, lon, heading) in points {
            runPointQuery(chunk: chunk, lat: lat, lon: lon, heading: heading)
        }
    } else if let lat = args.lat, let lon = args.lon {
        runPointQuery(chunk: chunk, lat: lat, lon: lon, heading: args.heading)
    } else {
        print("Missing lat/lon or gpx.")
        exit(1)
    }
} catch {
    print("Error: \(error)")
    exit(1)
}
