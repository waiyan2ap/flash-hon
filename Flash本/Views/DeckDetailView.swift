import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var deck: Deck
    @State private var showingAddCard = false
    @State private var showingReview = false
    @State private var showingModePicker = false
    @State private var editingCard: Card?
    @State private var searchText = ""
    @State private var reviewMode: ReviewMode?

    private var filteredCards: [Card] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return deck.cards }
        return deck.cards.filter { card in
            card.front.localizedStandardContains(trimmed)
                || card.back.localizedStandardContains(trimmed)
                || (card.furigana?.localizedStandardContains(trimmed) ?? false)
                || (card.onyomi?.localizedStandardContains(trimmed) ?? false)
                || (card.kunyomi?.localizedStandardContains(trimmed) ?? false)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Group {
            if deck.cards.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        .navigationTitle(deck.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !deck.cards.isEmpty, let data = DeckTransfer.encodeSingleDeck(deck) {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(deck.name).json")
                    ShareLink(item: url, preview: SharePreview(deck.name)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .onAppear { try? data.write(to: url) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingAddCard = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCard) {
            AddCardView(deck: deck)
        }
        .sheet(item: $editingCard) { card in
            AddCardView(deck: deck, card: card)
        }
        .sheet(isPresented: $showingModePicker) {
            StudyModePickerView(deck: deck) { mode in
                showingModePicker = false
                reviewMode = mode
                showingReview = true
            }
        }
        .fullScreenCover(isPresented: $showingReview) {
            CardReviewView(deck: deck, mode: reviewMode)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Cards Yet",
            systemImage: "square.text.square",
            description: Text(deck.isKanjiDeck
                ? "Add kanji cards with onyomi and kunyomi readings to start studying."
                : "Add cards to start studying.")
        )
    }

    private var cardList: some View {
        List {
            if !isSearching {
                Section {
                    if deck.cards.count < 4 {
                        HStack {
                            Label("Study", systemImage: "play.circle")
                            Spacer()
                            Text("Need \(4 - deck.cards.count) more")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Button {
                            if deck.isKanjiDeck {
                                showingModePicker = true
                            } else {
                                reviewMode = nil
                                showingReview = true
                            }
                        } label: {
                            HStack {
                                Label("Study", systemImage: "play.circle")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            if filteredCards.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                Section("Cards (\(filteredCards.count))") {
                    ForEach(filteredCards) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            if deck.isKanjiDeck {
                                Text(card.front)
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 8) {
                                    if let onyomi = card.onyomi {
                                        Text(onyomi)
                                            .font(.subheadline)
                                            .foregroundStyle(.orange)
                                    }
                                    if let kunyomi = card.kunyomi {
                                        Text(kunyomi)
                                            .font(.subheadline)
                                            .foregroundStyle(.blue)
                                    }
                                }

                                Text(card.back)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                FuriganaText(text: card.front, font: .preferredFont(forTextStyle: .body))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(card.back)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingCard = card
                        }
                        .contextMenu {
                            Button {
                                editingCard = card
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteCard(card)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteCards)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search cards")
    }

    private func deleteCards(at offsets: IndexSet) {
        for index in offsets {
            deleteCard(filteredCards[index])
        }
    }

    private func deleteCard(_ card: Card) {
        SyncEngine.recordDelete("card", id: card.id)
        modelContext.delete(card)
    }
}

struct StudyModePickerView: View {
    let deck: Deck
    let onStart: (ReviewMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: ReviewMode = .mixed

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Study Mode", selection: $mode) {
                        ForEach(ReviewMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityLabel("Study Mode")
                } footer: {
                    Text(mode.footerText)
                }
            }
            .navigationTitle("Study Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onStart(mode)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Deck.self, Card.self, SessionResult.self, configurations: config)
    let deck = Deck(name: "N5 Kanji", deckType: "kanji")
    container.mainContext.insert(deck)
    return NavigationStack {
        DeckDetailView(deck: deck)
    }
    .modelContainer(container)
}
