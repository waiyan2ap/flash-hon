import Foundation
import SwiftData

enum SampleData {
    private static let seedFlag = "didSeedSampleData"

    private struct SeedCard {
        let front: String
        let back: String
        let onyomi: String?
        let kunyomi: String?
    }

    private static let decks: [(name: String, type: String, cards: [SeedCard])] = [
        (
            "Beginner Verbs",
            "vocab",
            [
                SeedCard(front: "食べる[たべる]", back: "to eat", onyomi: nil, kunyomi: nil),
                SeedCard(front: "飲む[のむ]", back: "to drink", onyomi: nil, kunyomi: nil),
                SeedCard(front: "行く[いく]", back: "to go", onyomi: nil, kunyomi: nil),
                SeedCard(front: "来る[くる]", back: "to come", onyomi: nil, kunyomi: nil),
                SeedCard(front: "見る[みる]", back: "to see", onyomi: nil, kunyomi: nil),
                SeedCard(front: "聞く[きく]", back: "to listen", onyomi: nil, kunyomi: nil),
                SeedCard(front: "話す[はなす]", back: "to speak", onyomi: nil, kunyomi: nil),
                SeedCard(front: "読む[よむ]", back: "to read", onyomi: nil, kunyomi: nil),
                SeedCard(front: "書く[かく]", back: "to write", onyomi: nil, kunyomi: nil),
                SeedCard(front: "買う[かう]", back: "to buy", onyomi: nil, kunyomi: nil),
            ]
        ),
        (
            "N5 Kanji",
            "kanji",
            [
                SeedCard(front: "日", back: "day, sun", onyomi: "ニチ", kunyomi: "ひ"),
                SeedCard(front: "月", back: "month, moon", onyomi: "ゲツ", kunyomi: "つき"),
                SeedCard(front: "火", back: "fire", onyomi: "カ", kunyomi: "ひ"),
                SeedCard(front: "水", back: "water", onyomi: "スイ", kunyomi: "みず"),
                SeedCard(front: "木", back: "tree, wood", onyomi: "モク", kunyomi: "き"),
                SeedCard(front: "金", back: "gold, money", onyomi: "キン", kunyomi: "かね"),
                SeedCard(front: "土", back: "earth, soil", onyomi: "ド", kunyomi: "つち"),
                SeedCard(front: "人", back: "person", onyomi: "ジン", kunyomi: "ひと"),
                SeedCard(front: "山", back: "mountain", onyomi: "サン", kunyomi: "やま"),
                SeedCard(front: "川", back: "river", onyomi: "セン", kunyomi: "かわ"),
            ]
        ),
    ]

    static func seedIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seedFlag) else { return }
        UserDefaults.standard.set(true, forKey: seedFlag)

        for deckData in decks {
            let deck = Deck(name: deckData.name, deckType: deckData.type)
            modelContext.insert(deck)
            for cardData in deckData.cards {
                let card = Card(
                    front: cardData.front,
                    back: cardData.back,
                    onyomi: cardData.onyomi,
                    kunyomi: cardData.kunyomi
                )
                card.deck = deck
                modelContext.insert(card)
            }
        }
        try? modelContext.save()
    }
}
