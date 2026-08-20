import SwiftUI
import SwiftData

struct CardReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let deck: Deck
    var mode: ReviewMode? = nil

    @State private var vm = CardReviewViewModel()
    @State private var scorePulse = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if vm.showingResults {
                resultsView
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else if let question = vm.currentQuestion {
                questionView(question)
                    .id(vm.currentIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            vm.setup(deck: deck, mode: mode ?? .mixed)
        }
        .sensoryFeedback(.success, trigger: vm.selectedOption, condition: { _, _ in vm.isCorrect })
        .sensoryFeedback(.error, trigger: vm.selectedOption, condition: { _, _ in !vm.isCorrect })
        .sensoryFeedback(.impact(weight: .light), trigger: vm.currentIndex)
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Close") { dismiss() }
                    .foregroundStyle(.secondary)

                Spacer()

                if !vm.showingResults {
                    Text("\(vm.currentIndex + 1) / \(vm.totalQuestions)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !vm.showingResults {
                ProgressView(value: Double(vm.currentIndex), total: Double(max(vm.totalQuestions, 1)))
                    .tint(Color.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func questionView(_ question: Question) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Text(vm.questionTypeLabel ?? "Japanese")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if question.type == .meaning {
                    FuriganaText(
                        text: question.card.furigana.map { "\(question.card.front)[\($0)]" } ?? question.card.front,
                        font: .preferredFont(forTextStyle: .title1),
                        textColor: .label
                    )
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(question.card.front)
                        .font(.system(size: 48, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            .padding(.horizontal)

            Spacer()

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(question.options) { option in
                    OptionButton(
                        text: option.text,
                        state: buttonState(for: option),
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.selectOption(option)
                            }
                        }
                    )
                    .frame(minHeight: 110)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)

            if vm.answered {
                Button(vm.isCorrect ? "Correct! →" : "Wrong — Next") {
                    withAnimation(.spring(duration: 0.35)) {
                        vm.nextQuestion()
                    }
                }
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(vm.isCorrect ? Color.green : Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func buttonState(for option: Question.Option) -> OptionButton.State {
        guard vm.answered else { return .default }
        guard let selected = vm.selectedOption else { return .default }

        if option.isCorrect {
            return .correct
        }
        if option == selected {
            return .wrong
        }
        return .disabled
    }

    private var resultsView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("\(vm.correctCount) / \(vm.totalQuestions)")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(scoreColor)
                .scaleEffect(scorePulse ? 1 : 0.6)
                .opacity(scorePulse ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                        scorePulse = true
                    }
                }

            Text(scoreMessage)
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 16) {
                Button("Study Again") {
                    scorePulse = false
                    vm.restart(deck: deck, mode: mode ?? .mixed)
                }
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button("Done") {
                    vm.saveResult(modelContext: modelContext)
                    dismiss()
                }
                .font(.title2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    private var scoreColor: Color {
        let pct = Double(vm.correctCount) / Double(max(vm.totalQuestions, 1))
        if pct >= 0.9 { return .green }
        if pct >= 0.5 { return .orange }
        return .red
    }

    private var scoreMessage: String {
        let pct = Double(vm.correctCount) / Double(max(vm.totalQuestions, 1))
        if pct == 1.0 { return "Perfect!" }
        if pct >= 0.75 { return "Great job!" }
        if pct >= 0.5 { return "Keep practicing!" }
        return "Try again!"
    }
}

struct OptionButton: View {
    let text: String
    let state: State
    let action: () -> Void

    enum State {
        case `default`, correct, wrong, disabled
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.title3)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 12)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
        }
        .disabled(state != .default)
        .scaleEffect(state == .correct || state == .wrong ? 1.02 : 1)
    }

    private var foregroundColor: Color {
        switch state {
        case .default:     return .primary
        case .correct:     return .green
        case .wrong:       return .red
        case .disabled:    return .secondary.opacity(0.4)
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .default:     return Color.blue.opacity(0.08)
        case .correct:     return .green.opacity(0.12)
        case .wrong:       return .red.opacity(0.12)
        case .disabled:    return Color.blue.opacity(0.04)
        }
    }

    private var borderColor: Color {
        switch state {
        case .default:     return .clear
        case .correct:     return .green
        case .wrong:       return .red
        case .disabled:    return .clear
        }
    }

    private var borderWidth: CGFloat {
        switch state {
        case .default:     return 0
        case .correct:     return 2
        case .wrong:       return 2
        case .disabled:    return 0
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Deck.self, Card.self, SessionResult.self, configurations: config)
    let deck = Deck(name: "N5 Kanji")
    container.mainContext.insert(deck)
    for word in [
        ("食べる[たべる]", "to eat"),
        ("飲む[のむ]", "to drink"),
        ("寝る[ねる]", "to sleep"),
        ("読む[よむ]", "to read"),
    ] {
        let card = Card(front: word.0, back: word.1)
        card.deck = deck
        container.mainContext.insert(card)
    }
    return CardReviewView(deck: deck)
        .modelContainer(container)
}
