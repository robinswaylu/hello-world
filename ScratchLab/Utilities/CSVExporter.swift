import Foundation

enum CSVExporter {
    static func makeCSV(samples: [GyroSample]) -> String {
        var lines = ["timestamp,x,y,z"]
        lines.reserveCapacity(samples.count + 1)
        for sample in samples {
            lines.append("\(sample.timestamp),\(sample.x),\(sample.y),\(sample.z)")
        }
        return lines.joined(separator: "\n")
    }

    static func writeTemporaryFile(samples: [GyroSample], sessionStart: Date) throws -> URL {
        let csv = makeCSV(samples: samples)
        let stamp = Int(sessionStart.timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scratchlab-session-\(stamp)")
            .appendingPathExtension("csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
