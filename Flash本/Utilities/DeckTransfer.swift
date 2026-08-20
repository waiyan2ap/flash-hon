import Foundation
import SwiftData

// MARK: - Export Models

struct LibraryExport: Codable {
    let version: Int
    let decks: [DeckExport]

    init(decks: [DeckExport]) {
        self.version = 1
        self.decks = decks
    }
}

struct DeckExport: Codable {
    let name: String
    let deckType: String
    let isFavorite: Bool
    let cards: [CardExport]
}

struct CardExport: Codable {
    let front: String
    let back: String
    let furigana: String?
    let onyomi: String?
    let kunyomi: String?
}

// MARK: - Encode / Decode

enum DeckTransfer {
    static func encodeLibrary(_ decks: [Deck]) -> Data? {
        let exports = decks.map { deckToExport($0) }
        let library = LibraryExport(decks: exports)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(library)
    }

    static func encodeSingleDeck(_ deck: Deck) -> Data? {
        let library = LibraryExport(decks: [deckToExport(deck)])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(library)
    }

    static func decodeLibrary(_ data: Data) throws -> [DeckExport] {
        let library = try JSONDecoder().decode(LibraryExport.self, from: data)
        return library.decks
    }

    static func deckToExport(_ deck: Deck) -> DeckExport {
        DeckExport(
            name: deck.name,
            deckType: deck.deckType,
            isFavorite: deck.isFavorite,
            cards: deck.cards.map { cardToExport($0) }
        )
    }

    static func cardToExport(_ card: Card) -> CardExport {
        CardExport(
            front: card.front,
            back: card.back,
            furigana: card.furigana,
            onyomi: card.onyomi,
            kunyomi: card.kunyomi
        )
    }
}

// MARK: - Import Helpers

enum DeckImporter {
    static func importDecks(
        from exportDecks: [DeckExport],
        into modelContext: ModelContext,
        existingDecks: [Deck]
    ) -> Int {
        var importedCount = 0
        var usedNames = Set(existingDecks.map { $0.name })

        for export in exportDecks {
            let name = autoRename(export.name, usedNames: &usedNames)
            let deck = Deck(name: name, deckType: export.deckType)
            deck.isFavorite = export.isFavorite
            modelContext.insert(deck)

            for cardExport in export.cards {
                let card = Card(
                    front: cardExport.front,
                    back: cardExport.back,
                    furigana: cardExport.furigana,
                    onyomi: cardExport.onyomi,
                    kunyomi: cardExport.kunyomi
                )
                card.deck = deck
                modelContext.insert(card)
            }
            importedCount += 1
        }

        try? modelContext.save()
        return importedCount
    }

    private static func autoRename(_ name: String, usedNames: inout Set<String>) -> String {
        guard usedNames.contains(name) else {
            usedNames.insert(name)
            return name
        }

        var counter = 2
        while usedNames.contains("\(name) (\(counter))") {
            counter += 1
        }

        let renamed = "\(name) (\(counter))"
        usedNames.insert(renamed)
        return renamed
    }
}
