/// One undoable step: a single command or a whole transaction.
struct HistoryEntry: Sendable {
    let label: String
    /// Applied in order to perform this step.
    let commands: [any DocumentCommand]
}

/// The command bus: the only way the document changes.
///
/// Every UI gesture, console line, graph evaluation, or AI proposal ends here
/// as a ``DocumentCommand`` (spec §59). The session applies it to a copy of the
/// document, validates the result, and commits only if both succeed, so a
/// refused edit changes nothing: not the document, the history, the revision,
/// the selection, or the pending change feed.
public struct EditorSession: Sendable {
    public private(set) var document: SceneDocument
    public private(set) var selection = Selection()
    /// Increments on every committed execute, transaction, undo, and redo.
    public private(set) var revision: UInt64 = 0
    /// Changes committed since the last ``drainChanges()``, in order.
    public private(set) var pendingChanges: [SceneChange] = []

    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []

    public init(document: SceneDocument = SceneDocument()) {
        self.document = document
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// The label of the step ``undo()`` would reverse.
    public var undoLabel: String? { undoStack.last?.label }
    /// The label of the step ``redo()`` would reapply.
    public var redoLabel: String? { redoStack.last?.label }

    /// Applies one command as one undoable step and clears the redo stack.
    @discardableResult
    public mutating func execute(_ command: any DocumentCommand) throws(AuthoringError) -> [SceneChange] {
        try commit(label: command.label, [command], to: .undo)
    }

    /// Applies `commands` atomically as one undoable step: if any command fails,
    /// none of them take effect (spec §12).
    @discardableResult
    public mutating func transaction(
        _ label: String,
        _ commands: [any DocumentCommand]
    ) throws(AuthoringError) -> [SceneChange] {
        guard !commands.isEmpty else { throw .emptyTransaction }
        return try commit(label: label, commands, to: .undo)
    }

    /// Reverses the most recent step.
    @discardableResult
    public mutating func undo() throws(AuthoringError) -> [SceneChange] {
        guard let entry = undoStack.last else { throw .nothingToUndo }
        let changes = try commit(label: entry.label, entry.commands, to: .redo)
        undoStack.removeLast()
        return changes
    }

    /// Reapplies the most recently undone step.
    @discardableResult
    public mutating func redo() throws(AuthoringError) -> [SceneChange] {
        guard let entry = redoStack.last else { throw .nothingToRedo }
        let changes = try commit(label: entry.label, entry.commands, to: .undoKeepingRedo)
        redoStack.removeLast()
        return changes
    }

    /// Returns and clears the committed change feed, for a runtime projection.
    public mutating func drainChanges() -> [SceneChange] {
        defer { pendingChanges = [] }
        return pendingChanges
    }

    // MARK: Selection

    /// Replaces the selection. Every identifier must exist.
    public mutating func select(_ ids: [EntityID]) throws(AuthoringError) {
        try requireExisting(ids)
        selection.replace(with: ids)
    }

    /// Adds to the selection. Every identifier must exist.
    public mutating func addToSelection(_ ids: [EntityID]) throws(AuthoringError) {
        try requireExisting(ids)
        selection.add(ids)
    }

    public mutating func removeFromSelection(_ ids: [EntityID]) {
        selection.subtract(ids)
    }

    public mutating func clearSelection() {
        selection.clear()
    }

    // MARK: Commit

    private enum Destination {
        /// A new step: record for undo and invalidate redo.
        case undo
        /// An undone step: record for redo.
        case redo
        /// A redone step: record for undo, leaving the rest of redo intact.
        case undoKeepingRedo
    }

    private mutating func commit(
        label: String,
        _ commands: [any DocumentCommand],
        to destination: Destination
    ) throws(AuthoringError) -> [SceneChange] {
        var draft = document
        var changes: [SceneChange] = []
        var inverses: [any DocumentCommand] = []
        for command in commands {
            inverses.append(try command.apply(to: &draft, changes: &changes))
        }
        try draft.validate()

        let reverse = HistoryEntry(label: label, commands: inverses.reversed())
        document = draft
        revision += 1
        pendingChanges += changes
        selection.prune { draft.contains($0) }
        switch destination {
        case .undo:
            undoStack.append(reverse)
            redoStack.removeAll()
        case .redo:
            redoStack.append(reverse)
        case .undoKeepingRedo:
            undoStack.append(reverse)
        }
        return changes
    }

    private func requireExisting(_ ids: [EntityID]) throws(AuthoringError) {
        for id in ids where !document.contains(id) {
            throw .missingEntity(id)
        }
    }
}
