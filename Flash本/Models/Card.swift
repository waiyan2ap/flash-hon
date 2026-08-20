import Foundation
import SwiftData

@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var front: String
    var back: String
    var furigana: String?
    var onyomi: String?
    var kunyomi: String?
    var createdAt: Date

    @Relationship(inverse: \Deck.cards) var deck: Deck?

    init(front: String, back: String, furigana: String? = nil, onyomi: String? = nil, kunyomi: String? = nil) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.furigana = furigana
        self.onyomi = onyomi
        self.kunyomi = kunyomi
        self.createdAt = Date()
    }
}