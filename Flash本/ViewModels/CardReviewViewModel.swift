import SwiftUI
import SwiftData

enum ReviewMode: String, CaseIterable, Identifiable {
    case mixed, onyomi, kunyomi, meaning

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mixed: return "Mixed"
        case .onyomi: return "Onyomi"
        case .kunyomi: return "Kunyomi"
        case .meaning: return "Meaning"
        }
    }

    var footerText: String {
        switch self {
        case .mixed: return "Random mix of onyomi, kunyomi, and meaning questions."
        case .onyomi: return "Questions ask for the onyomi (Chinese reading, katakana)."
        case .kunyomi: return "Questions ask for the kunyomi (Japanese reading, hiragana)."
        case .meaning: return "Questions ask for the meaning of the kanji."
        }
    }
}

enum QuestionType {
    case onyomi, kunyomi, meaning

    var displayName: String {
        switch self {
        case .onyomi: return "Onyomi"
        case .kunyomi: return "Kunyomi"
        case .meaning: return "Meaning"
        }
    }
}

struct Question {
    let card: Card
    let type: QuestionType
    let options: [Option]
    let correctAnswer: String

    struct Option: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isCorrect: Bool
    }
}

@Observable
final class CardReviewViewModel {
    var questions: [Question] = []
    var currentIndex = 0
    var correctCount = 0
    var answered = false
    var selectedOption: Question.Option?
    var showingResults = false
    var savedResult = false

    private var deckName = ""
    private var deckIsKanji = false

    var currentQuestion: Question? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var totalQuestions: Int { questions.count }
    var isCorrect: Bool { selectedOption?.isCorrect ?? false }

    var questionTypeLabel: String? {
        guard deckIsKanji else { return nil }
        return currentQuestion?.type.displayName
    }

    func setup(deck: Deck, mode: ReviewMode = .mixed) {
        deckName = deck.name
        deckIsKanji = deck.isKanjiDeck
        let cards = deck.cards.shuffled()
        if deckIsKanji {
            questions = buildKanjiQuestions(for: cards, mode: mode)
        } else {
            questions = cards.compactMap { buildMeaningQuestion(for: $0, from: cards) }
        }
        currentIndex = 0
        correctCount = 0
        answered = false
        selectedOption = nil
        showingResults = false
        savedResult = false
    }

    private func buildKanjiQuestions(for cards: [Card], mode: ReviewMode) -> [Question] {
        var result: [Question] = []
        for card in cards {
            switch mode {
            case .onyomi:
                if let q = buildReadingQuestion(for: card, from: cards, type: .onyomi) {
                    result.append(q)
                }
            case .kunyomi:
                if let q = buildReadingQuestion(for: card, from: cards, type: .kunyomi) {
                    result.append(q)
                }
            case .meaning:
                if let q = buildMeaningQuestion(for: card, from: cards) {
                    result.append(q)
                }
            case .mixed:
                let types = [QuestionType.onyomi, .kunyomi, .meaning].shuffled()
                for type in types {
                    let q = type == .meaning
                        ? buildMeaningQuestion(for: card, from: cards)
                        : buildReadingQuestion(for: card, from: cards, type: type)
                    if let q {
                        result.append(q)
                        break
                    }
                }
            }
        }
        return result
    }

    private func buildReadingQuestion(for card: Card, from allCards: [Card], type: QuestionType) -> Question? {
        let correct = type == .onyomi ? card.onyomi : card.kunyomi
        guard let correct, !correct.isEmpty else { return nil }

        let distractors = allCards
            .filter { $0.id != card.id }
            .compactMap { type == .onyomi ? $0.onyomi : $0.kunyomi }
            .filter { !$0.isEmpty && $0 != correct }

        var unique = Array(Set(distractors)).shuffled()
        guard unique.count >= 3 else { return nil }
        unique = Array(unique.prefix(3))

        var all = unique + [correct]
        all.shuffle()
        return Question(
            card: card,
            type: type,
            options: all.map { Question.Option(text: $0, isCorrect: $0 == correct) },
            correctAnswer: correct
        )
    }

    private func buildMeaningQuestion(for card: Card, from allCards: [Card]) -> Question? {
        let correct = card.back
        let distractors = allCards
            .filter { $0.id != card.id }
            .map { $0.back }
            .filter { !$0.isEmpty && $0 != correct }

        var unique = Array(Set(distractors)).shuffled()
        guard unique.count >= 3 else { return nil }
        unique = Array(unique.prefix(3))

        var all = unique + [correct]
        all.shuffle()
        return Question(
            card: card,
            type: .meaning,
            options: all.map { Question.Option(text: $0, isCorrect: $0 == correct) },
            correctAnswer: correct
        )
    }

    func selectOption(_ option: Question.Option) {
        guard !answered else { return }
        answered = true
        selectedOption = option
        if option.isCorrect {
            correctCount += 1
        }
    }

    func nextQuestion() {
        currentIndex += 1
        answered = false
        selectedOption = nil
        if currentIndex >= questions.count {
            showingResults = true
        }
    }

    func saveResult(modelContext: ModelContext) {
        guard !savedResult else { return }
        savedResult = true
        let result = SessionResult(
            deckName: deckName,
            correctCount: correctCount,
            totalCount: totalQuestions
        )
        modelContext.insert(result)
        try? modelContext.save()
    }

    func restart(deck: Deck, mode: ReviewMode = .mixed) {
        setup(deck: deck, mode: mode)
    }
}
