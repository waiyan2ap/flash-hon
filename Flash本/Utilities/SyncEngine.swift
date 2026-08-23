import Foundation
import UIKit
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import Observation

@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    var syncError: String?

    private var container: ModelContainer?
    private var foregroundObserver: NSObjectProtocol?

    private static let pendingDeletionsKey = "sync.pendingDeletions"
    private static let lastSyncedKey = "sync.lastSyncedAt"

    /// Firestore's FIRTimestamp rejects dates outside year 1–9999 validation;
    /// Unix epoch is a safe "fetch everything" floor.
    private static let firestoreEpochFloor = Date(timeIntervalSince1970: 0)

    struct TouchedIDs {
        var decks: Set<UUID> = []
        var cards: Set<UUID> = []
        var sessions: Set<UUID> = []
    }

    private init() {
        lastSyncedAt = UserDefaults.standard.object(forKey: Self.lastSyncedKey) as? Date
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleSync()
            }
        }
    }

    deinit {
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    }

    func configure(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    func scheduleSync() {
        guard FirebaseBootstrap.isConfigured, AuthService.shared.isSignedIn else { return }
        Task { await syncNow() }
    }

    func handleSignOut() {
        syncError = nil
    }

    // MARK: - Deletion queue

    static func recordDelete(_ kind: String, id: UUID) {
        var queue = UserDefaults.standard.stringArray(forKey: pendingDeletionsKey) ?? []
        queue.append("\(kind):\(id.uuidString)")
        UserDefaults.standard.set(queue, forKey: pendingDeletionsKey)
    }

    static func clearPendingDeletions() {
        UserDefaults.standard.removeObject(forKey: pendingDeletionsKey)
    }

    var lastSyncedText: String {
        guard let lastSyncedAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSyncedAt, relativeTo: .now)
    }

    // MARK: - Sync

    @MainActor
    func syncNow() async {
        guard FirebaseBootstrap.isConfigured,
              AuthService.shared.isSignedIn,
              !isSyncing,
              let container else { return }

        isSyncing = true
        defer { isSyncing = false }
        syncError = nil

        let db = Firestore.firestore()
        guard let uid = AuthService.shared.uid else { return }

        do {
            var since = try await fetchServerLastSynced(db: db, uid: uid)
            since = max(since, Self.firestoreEpochFloor)

            try await processPendingDeletions(db: db, uid: uid)
            let pulled = try await pullChanges(db: db, uid: uid, since: since, context: container.mainContext)
            try await pushLocalChanges(db: db, uid: uid, since: since, skip: pulled, context: container.mainContext)

            lastSyncedAt = Date()
            UserDefaults.standard.set(lastSyncedAt, forKey: Self.lastSyncedKey)
            try await db.collection("users").document(uid)
                .collection("meta").document("sync")
                .setData(["lastSyncedAt": Timestamp(date: lastSyncedAt!)], merge: true)
        } catch {
            syncError = error.localizedDescription
        }
    }

    @MainActor
    func purgeCloudData() async {
        guard FirebaseBootstrap.isConfigured,
              AuthService.shared.isSignedIn,
              let uid = AuthService.shared.uid else { return }

        isSyncing = true
        defer { isSyncing = false }

        let db = Firestore.firestore()
        do {
            for collection in ["decks", "cards", "sessions"] {
                let snapshot = try await db.collection("users").document(uid)
                    .collection(collection).getDocuments()
                let docs = snapshot.documents.map(\.reference)
                for chunk in docs.chunks(of: 400) {
                    let batch = db.batch()
                    chunk.forEach { batch.deleteDocument($0) }
                    try await batch.commit()
                }
            }
            try await db.collection("users").document(uid)
                .collection("meta").document("sync").delete()

            Self.clearPendingDeletions()
            lastSyncedAt = nil
            UserDefaults.standard.removeObject(forKey: Self.lastSyncedKey)
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Steps

    private func fetchServerLastSynced(db: Firestore, uid: String) async throws -> Date {
        let doc = try await db.collection("users").document(uid)
            .collection("meta").document("sync").getDocument()
        if let ts = doc.data()?["lastSyncedAt"] as? Timestamp {
            return ts.dateValue()
        }
        return Self.firestoreEpochFloor
    }

    private func processPendingDeletions(db: Firestore, uid: String) async throws {
        let defaults = UserDefaults.standard
        guard let queue = defaults.stringArray(forKey: Self.pendingDeletionsKey), !queue.isEmpty else { return }

        var remaining: [String] = []
        for entry in queue {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let kind = String(parts[0])
            let docID = String(parts[1])
            do {
                let collections = ["deck", "card", "session"]
                guard collections.contains(kind) else { continue }
                try await db.collection("users").document(uid)
                    .collection(kind == "deck" ? "decks" : kind == "card" ? "cards" : "sessions")
                    .document(docID)
                    .setData(["deletedAt": Timestamp(date: Date()), "updatedAt": Timestamp(date: Date())], merge: true)
            } catch {
                remaining.append(entry)
            }
        }
        defaults.set(remaining, forKey: Self.pendingDeletionsKey)
    }

    @MainActor
    private func pullChanges(db: Firestore, uid: String, since: Date, context: ModelContext) async throws -> TouchedIDs {
        var touched = TouchedIDs()
        let userRef = db.collection("users").document(uid)

        let deckSnap = try await userRef.collection("decks")
            .whereField("updatedAt", isGreaterThan: Timestamp(date: since))
            .getDocuments()
        for doc in deckSnap.documents {
            guard let id = Self.uuid(doc.documentID) else { continue }
            touched.decks.insert(id)
            applyDeck(doc.data(), id: id, context: context)
        }

        let cardSnap = try await userRef.collection("cards")
            .whereField("updatedAt", isGreaterThan: Timestamp(date: since))
            .getDocuments()
        for doc in cardSnap.documents {
            guard let id = Self.uuid(doc.documentID) else { continue }
            touched.cards.insert(id)
            applyCard(doc.data(), id: id, context: context)
        }

        let sessionSnap = try await userRef.collection("sessions")
            .whereField("updatedAt", isGreaterThan: Timestamp(date: since))
            .getDocuments()
        for doc in sessionSnap.documents {
            guard let id = Self.uuid(doc.documentID) else { continue }
            touched.sessions.insert(id)
            applySession(doc.data(), id: id, context: context)
        }

        try? context.save()
        return touched
    }

    @MainActor
    private func pushLocalChanges(db: Firestore, uid: String, since: Date, skip: TouchedIDs, context: ModelContext) async throws {
        let userRef = db.collection("users").document(uid)

        let deckDescriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.updatedAt > since })
        let decks = try context.fetch(deckDescriptor).filter { !skip.decks.contains($0.id) }
        for chunk in decks.chunks(of: 400) {
            let batch = db.batch()
            for deck in chunk {
                batch.setData(Self.deckDict(deck), forDocument: userRef.collection("decks").document(deck.id.uuidString))
            }
            try await batch.commit()
        }

        let cardDescriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.updatedAt > since })
        let cards = try context.fetch(cardDescriptor).filter { !skip.cards.contains($0.id) }
        for chunk in cards.chunks(of: 400) {
            let batch = db.batch()
            for card in chunk {
                batch.setData(Self.cardDict(card), forDocument: userRef.collection("cards").document(card.id.uuidString))
            }
            try await batch.commit()
        }

        let sessionDescriptor = FetchDescriptor<SessionResult>(predicate: #Predicate { $0.updatedAt > since })
        let sessions = try context.fetch(sessionDescriptor).filter { !skip.sessions.contains($0.id) }
        for chunk in sessions.chunks(of: 400) {
            let batch = db.batch()
            for session in chunk {
                batch.setData(Self.sessionDict(session), forDocument: userRef.collection("sessions").document(session.id.uuidString))
            }
            try await batch.commit()
        }
    }

    // MARK: - Apply remote -> local

    @MainActor
    private func applyDeck(_ data: [String: Any], id: UUID, context: ModelContext) {
        if Self.timestamp(data["deletedAt"]) != nil {
            if let local = fetchDeck(id: id, context: context) {
                context.delete(local)
            }
            return
        }
        guard let name = data["name"] as? String else { return }
        let desc = data["desc"] as? String ?? ""
        let deckType = data["deckType"] as? String ?? "vocab"
        let isFavorite = data["isFavorite"] as? Bool ?? false
        let createdAt = Self.timestamp(data["createdAt"]) ?? Date()
        let updatedAt = Self.timestamp(data["updatedAt"]) ?? Date()

        if let local = fetchDeck(id: id, context: context) {
            if updatedAt > local.updatedAt || (updatedAt == local.updatedAt && name != local.name) {
                local.name = name
                local.desc = desc
                local.deckType = deckType
                local.isFavorite = isFavorite
                local.createdAt = createdAt
                local.updatedAt = updatedAt
            }
        } else {
            let deck = Deck(name: name, description: desc, deckType: deckType)
            deck.id = id
            deck.isFavorite = isFavorite
            deck.createdAt = createdAt
            deck.updatedAt = updatedAt
            context.insert(deck)
        }
    }

    @MainActor
    private func applyCard(_ data: [String: Any], id: UUID, context: ModelContext) {
        if Self.timestamp(data["deletedAt"]) != nil {
            if let local = fetchCard(id: id, context: context) {
                context.delete(local)
            }
            return
        }
        guard let front = data["front"] as? String,
              let back = data["back"] as? String else { return }
        let furigana = data["furigana"] as? String
        let onyomi = data["onyomi"] as? String
        let kunyomi = data["kunyomi"] as? String
        let deckID = (data["deckId"] as? String).flatMap(UUID.init(uuidString:))
        let createdAt = Self.timestamp(data["createdAt"]) ?? Date()
        let updatedAt = Self.timestamp(data["updatedAt"]) ?? Date()

        if let local = fetchCard(id: id, context: context) {
            if updatedAt > local.updatedAt {
                local.front = front
                local.back = back
                local.furigana = furigana
                local.onyomi = onyomi
                local.kunyomi = kunyomi
                local.createdAt = createdAt
                local.updatedAt = updatedAt
                if let deckID, let parent = fetchDeck(id: deckID, context: context) {
                    local.deck = parent
                }
            }
        } else {
            guard let deckID, let parent = fetchDeck(id: deckID, context: context) else { return }
            let card = Card(front: front, back: back, furigana: furigana, onyomi: onyomi, kunyomi: kunyomi)
            card.id = id
            card.createdAt = createdAt
            card.updatedAt = updatedAt
            card.deck = parent
            context.insert(card)
        }
    }

    @MainActor
    private func applySession(_ data: [String: Any], id: UUID, context: ModelContext) {
        guard fetchSession(id: id, context: context) == nil else { return }
        if Self.timestamp(data["deletedAt"]) != nil { return }
        guard let deckName = data["deckName"] as? String,
              let correctCount = data["correctCount"] as? Int,
              let totalCount = data["totalCount"] as? Int else { return }
        let session = SessionResult(deckName: deckName, correctCount: correctCount, totalCount: totalCount)
        session.id = id
        session.date = Self.timestamp(data["date"]) ?? Self.timestamp(data["updatedAt"]) ?? Date()
        session.updatedAt = Self.timestamp(data["updatedAt"]) ?? session.date
        context.insert(session)
    }

    // MARK: - Mapping local -> dict

    private static func deckDict(_ deck: Deck) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["name"] = deck.name
        dict["desc"] = deck.desc
        dict["deckType"] = deck.deckType
        dict["isFavorite"] = deck.isFavorite
        dict["createdAt"] = Timestamp(date: deck.createdAt)
        dict["updatedAt"] = Timestamp(date: deck.updatedAt)
        dict["deletedAt"] = NSNull()
        return dict
    }

    private static func cardDict(_ card: Card) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["front"] = card.front
        dict["back"] = card.back
        if let furigana = card.furigana {
            dict["furigana"] = furigana
        } else {
            dict["furigana"] = NSNull()
        }
        if let onyomi = card.onyomi {
            dict["onyomi"] = onyomi
        } else {
            dict["onyomi"] = NSNull()
        }
        if let kunyomi = card.kunyomi {
            dict["kunyomi"] = kunyomi
        } else {
            dict["kunyomi"] = NSNull()
        }
        if let parentID = card.deck?.id.uuidString {
            dict["deckId"] = parentID
        } else {
            dict["deckId"] = NSNull()
        }
        dict["createdAt"] = Timestamp(date: card.createdAt)
        dict["updatedAt"] = Timestamp(date: card.updatedAt)
        dict["deletedAt"] = NSNull()
        return dict
    }

    private static func sessionDict(_ session: SessionResult) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["deckName"] = session.deckName
        dict["correctCount"] = session.correctCount
        dict["totalCount"] = session.totalCount
        dict["date"] = Timestamp(date: session.date)
        dict["updatedAt"] = Timestamp(date: session.updatedAt)
        dict["deletedAt"] = NSNull()
        return dict
    }

    // MARK: - Helpers

    private func fetchDeck(id: UUID, context: ModelContext) -> Deck? {
        var descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchCard(id: UUID, context: ModelContext) -> Card? {
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchSession(id: UUID, context: ModelContext) -> SessionResult? {
        var descriptor = FetchDescriptor<SessionResult>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func uuid(_ string: String) -> UUID? {
        UUID(uuidString: string)
    }

    private static func timestamp(_ any: Any?) -> Date? {
        (any as? Timestamp)?.dateValue()
    }
}

extension Collection {
    func chunks(of size: Int) -> [[Element]] {
        guard size > 0 else { return [Array(self)] }
        var result: [[Element]] = []
        var current: [Element] = []
        for element in self {
            if current.count == size {
                result.append(current)
                current = [element]
            } else {
                current.append(element)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
