import Foundation

/// A bounded, newest-first log of reversible actions. The app supplies the payload (what to restore);
/// this type decides what can still be undone.
public struct UndoLog<Payload> {
    public struct Entry: Identifiable {
        public let id: UUID
        public let title: String
        public let date: Date
        public let payload: Payload
        /// After this, the action can no longer be safely reversed (e.g. the user kept typing).
        public let expiresAt: Date?
        public internal(set) var undone: Bool

        public func isReversible(at now: Date = Date()) -> Bool {
            !undone && (expiresAt.map { now < $0 } ?? true)
        }
    }

    public let capacity: Int
    public private(set) var entries: [Entry] = []

    public init(capacity: Int = 20) { self.capacity = capacity }

    @discardableResult
    public mutating func record(_ title: String, payload: Payload, at date: Date = Date(), expiresAfter: TimeInterval? = nil) -> UUID {
        let entry = Entry(id: UUID(), title: title, date: date, payload: payload,
                          expiresAt: expiresAfter.map { date.addingTimeInterval($0) }, undone: false)
        entries.insert(entry, at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
        return entry.id
    }

    /// The newest action that can still be reversed.
    public func lastReversible(at now: Date = Date()) -> Entry? {
        entries.first { $0.isReversible(at: now) }
    }

    public func entry(id: UUID) -> Entry? { entries.first { $0.id == id } }

    /// Marks an action as undone; returns false if it wasn't reversible.
    @discardableResult
    public mutating func markUndone(_ id: UUID, at now: Date = Date()) -> Bool {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].isReversible(at: now) else { return false }
        entries[i].undone = true
        return true
    }

    public mutating func removeAll() { entries.removeAll() }
}
