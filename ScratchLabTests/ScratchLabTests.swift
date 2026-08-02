import XCTest
@testable import ScratchLab

final class ScratchLabTests: XCTestCase {
    func testGyroSampleUnitConversion() {
        let sample = GyroSample(timestamp: 0, x: 0, y: 0, z: .pi)
        XCTAssertEqual(sample.zDegPerSec, 180, accuracy: 0.0001)
        XCTAssertEqual(sample.zRPM, 30, accuracy: 0.0001)
    }

    func testCSVExporterHeaderAndRows() {
        let samples = [
            GyroSample(timestamp: 0.0, x: 0.1, y: 0.2, z: 0.3),
            GyroSample(timestamp: 0.01, x: 0.4, y: 0.5, z: 0.6)
        ]
        let csv = CSVExporter.makeCSV(samples: samples)
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "timestamp,x,y,z")
        XCTAssertEqual(lines[1], "0.0,0.1,0.2,0.3")
        XCTAssertEqual(lines[2], "0.01,0.4,0.5,0.6")
    }

    func testCSVExporterEmptySamplesProducesHeaderOnly() {
        let csv = CSVExporter.makeCSV(samples: [])
        XCTAssertEqual(csv, "timestamp,x,y,z")
    }

    func testClippingThresholdMatchesGyroFullScale() {
        let fullScale = MotionMonitor.gyroFullScaleRadPerSec
        let clipFloor = fullScale * MotionMonitor.clippingThresholdFraction

        XCTAssertLessThan(clipFloor, fullScale)
        XCTAssertGreaterThan(clipFloor, 0)
    }
}
