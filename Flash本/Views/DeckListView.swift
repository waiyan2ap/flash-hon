import SwiftUI
import SwiftData

struct DeckListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @State private var showingAddDeck = false
    @State private var newDeckName = ""
    @State private var newDeckType = "vocab"

    var body: some View {
        NavigationStack {
            Group {
                if decks.isEmpty {
                    emptyState
                } else {
                    deckList
                }
            }
            .navigationTitle("Decks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddDeck = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddDeck) {
                addDeckSheet
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Decks Yet",
            systemImage: "rectangle.stack.badge.plus",
            description: Text("Create your first deck to start studying.")
        )
    }

    private var deckList: some View {
        List {
            ForEach(decks) { deck in
                NavigationLink(destination: DeckDetailView(deck: deck)) {
                    DeckRowView(deck: deck)
                }
            }
            .onDelete(perform: deleteDecks)
        }
    }

    private var addDeckSheet: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Deck Name", text: $newDeckName)
                        .autocorrectionDisabled()
                }

                Section("Deck Type") {
                    Picker("Type", selection: $newDeckType) {
                        Text("Vocab").tag("vocab")
                        Text("Kanji").tag("kanji")
                    }
                    .pickerStyle(.segmented)

                    Text(newDeckType == "kanji"
                        ? "Cards include kanji, onyomi, and kunyomi readings."
                        : "Cards include Japanese text and meaning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newDeckName = ""
                        newDeckType = "vocab"
                        showingAddDeck = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        addDeck()
                    }
                    .disabled(newDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addDeck() {
        let name = newDeckName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let deck = Deck(name: name, deckType: newDeckType)
        modelContext.insert(deck)
        newDeckName = ""
        newDeckType = "vocab"
        showingAddDeck = false
    }

    private func deleteDecks(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(decks[index])
        }
    }

    }

#Preview {
    DeckListView()
        .modelContainer(for: [Deck.self, Card.self, SessionResult.self])
}

struct DeckRowView: View {
    let deck: Deck

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name)
                    .font(.headline)
                Text("\(deck.cards.count) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(deck.isKanjiDeck ? "Kanji" : "Vocab")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((deck.isKanjiDeck ? Color.orange : Color.blue).opacity(0.15))
                .foregroundStyle(deck.isKanjiDeck ? .orange : .blue)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}
