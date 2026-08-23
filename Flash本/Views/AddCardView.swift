import SwiftUI
import SwiftData

struct AddCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var deck: Deck
    let card: Card?

    @State private var front: String
    @State private var back: String
    @State private var furigana: String
    @State private var onyomi: String
    @State private var kunyomi: String

    init(deck: Deck, card: Card? = nil) {
        self.deck = deck
        self.card = card
        _front = State(initialValue: card?.front ?? "")
        _back = State(initialValue: card?.back ?? "")
        _furigana = State(initialValue: card?.furigana ?? "")
        _onyomi = State(initialValue: card?.onyomi ?? "")
        _kunyomi = State(initialValue: card?.kunyomi ?? "")
    }

    private var isEditing: Bool { card != nil }
    private var isKanji: Bool { deck.isKanjiDeck }

    var body: some View {
        NavigationStack {
            Form {
                if isKanji {
                    Section("漢字") {
                        TextField("kanji", text: $front)
                            .autocorrectionDisabled()
                    }

                    Section("音読み (onyomi)") {
                        TextField("katakana, e.g. ニチ", text: $onyomi)
                            .autocorrectionDisabled()
                    }

                    Section("訓読み (kunyomi)") {
                        TextField("hiragana, e.g. ひ", text: $kunyomi)
                            .autocorrectionDisabled()
                    }

                    Section("意味 (meaning)") {
                        TextField("meaning in your language", text: $back, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    if !front.isEmpty && (!onyomi.isEmpty || !kunyomi.isEmpty) {
                        Section("Preview") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(front)
                                    .font(.title2.bold())
                                HStack(spacing: 8) {
                                    if !onyomi.isEmpty {
                                        Text(onyomi)
                                            .font(.subheadline)
                                            .foregroundStyle(.orange)
                                    }
                                    if !kunyomi.isEmpty {
                                        Text(kunyomi)
                                            .font(.subheadline)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Text(back)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Section("Japanese") {
                        TextField("漢字", text: $front)
                            .autocorrectionDisabled()

                        TextField("よみ[yomi] (optional)", text: $furigana)
                            .autocorrectionDisabled()
                            .font(.caption)
                    }

                    Section("Meaning") {
                        TextField("meaning in your language", text: $back, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    if !furigana.isEmpty {
                        Section("Preview") {
                            FuriganaText(text: "\(front)[\(furigana)]", font: .preferredFont(forTextStyle: .body))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Card" : "New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        let cleanFront = front.trimmingCharacters(in: .whitespaces)
        let cleanBack = back.trimmingCharacters(in: .whitespaces)
        if isKanji {
            let cleanOnyomi = onyomi.trimmingCharacters(in: .whitespaces)
            let cleanKunyomi = kunyomi.trimmingCharacters(in: .whitespaces)
            return !cleanFront.isEmpty && !cleanBack.isEmpty && (!cleanOnyomi.isEmpty || !cleanKunyomi.isEmpty)
        }
        return !cleanFront.isEmpty && !cleanBack.isEmpty
    }

    private func save() {
        let cleanFront = front.trimmingCharacters(in: .whitespaces)
        let cleanBack = back.trimmingCharacters(in: .whitespaces)

        guard !cleanFront.isEmpty, !cleanBack.isEmpty else { return }

        if let card {
            card.front = cleanFront
            card.back = cleanBack
            if isKanji {
                card.onyomi = emptyToNil(onyomi)
                card.kunyomi = emptyToNil(kunyomi)
                card.furigana = nil
            } else {
                card.furigana = emptyToNil(furigana)
                card.onyomi = nil
                card.kunyomi = nil
            }
            card.updatedAt = .now
        } else {
            let card: Card
            if isKanji {
                card = Card(front: cleanFront, back: cleanBack, onyomi: emptyToNil(onyomi), kunyomi: emptyToNil(kunyomi))
            } else {
                card = Card(front: cleanFront, back: cleanBack, furigana: emptyToNil(furigana))
            }
            card.deck = deck
            modelContext.insert(card)
        }
        dismiss()
    }

    private func emptyToNil(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Deck.self, Card.self, SessionResult.self, configurations: config)
    let deck = Deck(name: "N5 Kanji", deckType: "kanji")
    container.mainContext.insert(deck)
    return AddCardView(deck: deck)
        .modelContainer(container)
}
