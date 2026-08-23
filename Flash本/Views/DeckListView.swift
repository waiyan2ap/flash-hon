import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DeckListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allDecks: [Deck]

    private var decks: [Deck] {
        allDecks.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.createdAt > $1.createdAt
        }
    }
    @State private var showingAddDeck = false
    @State private var newDeckName = ""
    @State private var newDeckType = "vocab"
    @State private var showingImportPicker = false
    @State private var importResult: String?

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
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingImportPicker = true }) {
                        Image(systemName: "arrow.down.doc")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddDeck = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddDeck) {
                addDeckSheet
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json]
            ) { result in
                handleImport(result)
            }
            .alert("Import Complete", isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            )) {
                Button("OK") { importResult = nil }
            } message: {
                if let msg = importResult { Text(msg) }
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
                .swipeActions(edge: .leading) {
                    Button {
                        withAnimation { toggleFavorite(deck) }
                    } label: {
                        Label(
                            deck.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: deck.isFavorite ? "bookmark.slash" : "bookmark.fill"
                        )
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteDeck(deck)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        withAnimation { toggleFavorite(deck) }
                    } label: {
                        Label(
                            deck.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: deck.isFavorite ? "bookmark.slash" : "bookmark.fill"
                        )
                    }
                    Button(role: .destructive) {
                        deleteDeck(deck)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
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

    private func toggleFavorite(_ deck: Deck) {
        deck.isFavorite.toggle()
        deck.updatedAt = .now
    }

    private func deleteDeck(_ deck: Deck) {
        SyncEngine.recordDelete("deck", id: deck.id)
        deck.cards.forEach { SyncEngine.recordDelete("card", id: $0.id) }
        modelContext.delete(deck)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return }
        guard let exportDecks = try? DeckTransfer.decodeLibrary(data) else { return }

        let count = DeckImporter.importDecks(
            from: exportDecks,
            into: modelContext,
            existingDecks: Array(decks)
        )
        importResult = "Imported \(count) deck\(count == 1 ? "" : "s")."
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

            HStack(spacing: 6) {
                if deck.isFavorite {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text(deck.isKanjiDeck ? "Kanji" : "Vocab")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((deck.isKanjiDeck ? Color.orange : Color.blue).opacity(0.15))
                    .foregroundStyle(deck.isKanjiDeck ? .orange : .blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
