import XCTest
@testable import EngineAlpha

final class EngineAlphaTests: XCTestCase {
    func testBearingNormalization() {
        XCTAssertEqual(Geo.normalizeHeading(370), 10, accuracy: 0.0001)
        XCTAssertEqual(Geo.normalizeHeading(-10), 350, accuracy: 0.0001)
    }

    func testTileIDDeterministic() {
        let id1 = TileID.from(latLon: LatLon(lat: 40.0, lon: -73.0), zoom: 16)
        let id2 = TileID.from(latLon: LatLon(lat: 40.0, lon: -73.0), zoom: 16)
        XCTAssertEqual(id1, id2)
    }

    func testRoadMatchSelectsClosest() {
        let location = LatLon(lat: 40.0, lon: -73.0)
        let segA = RoadSegment(id: "a", name: "A St", polyline: [LatLon(lat: 40.0, lon: -73.0005), LatLon(lat: 40.001, lon: -73.0005)], oneWay: false)
        let segB = RoadSegment(id: "b", name: "B St", polyline: [LatLon(lat: 40.0, lon: -73.002), LatLon(lat: 40.001, lon: -73.002)], oneWay: false)
        let tile = RoadTile(tileID: TileID(z: 16, x: 0, y: 0), segments: [segA, segB])

        let matcher = RoadMatcher()
        let match = matcher.match(location: location, headingDegrees: nil, tiles: [tile])
        XCTAssertEqual(match?.segmentID, "a")
        XCTAssertEqual(match?.roadName, "A St")
    }
}
