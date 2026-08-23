import Foundation
import SwiftData

@Model
final class SessionResult {
    @Attribute(.unique) var id: UUID
    var deckName: String
    var correctCount: Int
    var totalCount: Int
    var date: Date
    var updatedAt: Date = Date()
    var deletedAt: Date? = nil

    var accuracy: Double {
        guard totalCount > 0 else { return 0 }
        return Double(correctCount) / Double(totalCount)
    }

    init(deckName: String, correctCount: Int, totalCount: Int) {
        self.id = UUID()
        self.deckName = deckName
        self.correctCount = correctCount
        self.totalCount = totalCount
        self.date = Date()
    }
}