import Foundation
import SwiftData

@Model
final class Deck {
    @Attribute(.unique) var id: UUID
    var name: String
    var desc: String
    var deckType: String = "vocab"
    var isFavorite: Bool = false
    var createdAt: Date
    var updatedAt: Date = Date()
    var deletedAt: Date? = nil
    @Relationship(deleteRule: .cascade) var cards: [Card] = []

    init(name: String, description: String = "", deckType: String = "vocab") {
        self.id = UUID()
        self.name = name
        self.desc = description
        self.deckType = deckType
        self.createdAt = Date()
    }

    var isKanjiDeck: Bool { deckType == "kanji" }
}
