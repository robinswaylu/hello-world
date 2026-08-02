import Foundation
import SwiftData

@Model
final class DrillResult {
    var drillID: String
    var date: Date
    var overallScore: Double

    init(drillID: String, date: Date, overallScore: Double) {
        self.drillID = drillID
        self.date = date
        self.overallScore = overallScore
    }
}
