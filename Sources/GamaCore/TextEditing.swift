//  TextEditing.swift — GamaCore
//  Cursor position and selection range for TextField, expressed as
//  Character-count (grapheme-cluster) offsets. A Character is always one
//  extended grapheme cluster, so an offset in this unit can never split a
//  combining sequence or a multi-scalar emoji, with no width table needed —
//  that's a display-column concern, handled separately by TextLayout.

/// A caret and optional selection range into a field's text, as
/// `Character`-count offsets from the start of the string.
struct Selection: Hashable, Sendable {
    /// The end that doesn't move when a selection is extended.
    var anchor: Int
    /// The caret; where insert and delete-around operate.
    var head: Int

    /// True when there is no selected range, only a caret.
    var isCollapsed: Bool { anchor == head }

    /// The selected range, normalized so `lowerBound <= upperBound`
    /// regardless of which end the caret is on.
    var range: Range<Int> { anchor <= head ? anchor..<head : head..<anchor }

    /// Returns a selection with both ends clamped into `0...count`.
    func clamped(to count: Int) -> Selection {
        Selection(
            anchor: Swift.max(0, Swift.min(anchor, count)),
            head: Swift.max(0, Swift.min(head, count)))
    }
}

/// Pure cursor-relative edit operations on a field's text. Every function
/// takes the current value and selection and returns the new value and
/// selection; none of it touches storage — `TextField` owns that.
enum TextEditing {
    /// Inserts `character` at `selection`, replacing the selected range
    /// when one exists, and collapses the result to just after the
    /// inserted character.
    static func insert(
        _ character: Character, into value: String, at selection: Selection
    ) -> (String, Selection) {
        let selection = selection.clamped(to: value.count)
        let range = selection.range
        var characters = Array(value)
        characters.replaceSubrange(range, with: [character])
        let newHead = range.lowerBound + 1
        return (String(characters), Selection(anchor: newHead, head: newHead))
    }

    /// Deletes the character before the cursor, or the selected range when
    /// one exists. Returns `nil` (decline) when the cursor is already at
    /// the start with no selection.
    static func deleteBackward(_ value: String, at selection: Selection) -> (String, Selection)? {
        let selection = selection.clamped(to: value.count)
        if !selection.isCollapsed {
            var characters = Array(value)
            let range = selection.range
            characters.removeSubrange(range)
            return (String(characters), Selection(anchor: range.lowerBound, head: range.lowerBound))
        }
        guard selection.head > 0 else { return nil }
        var characters = Array(value)
        characters.remove(at: selection.head - 1)
        let newHead = selection.head - 1
        return (String(characters), Selection(anchor: newHead, head: newHead))
    }

    /// Deletes the character at the cursor, or the selected range when one
    /// exists. Returns `nil` (decline) when the cursor is already at the
    /// end with no selection.
    static func deleteForward(_ value: String, at selection: Selection) -> (String, Selection)? {
        let selection = selection.clamped(to: value.count)
        if !selection.isCollapsed {
            var characters = Array(value)
            let range = selection.range
            characters.removeSubrange(range)
            return (String(characters), Selection(anchor: range.lowerBound, head: range.lowerBound))
        }
        guard selection.head < value.count else { return nil }
        var characters = Array(value)
        characters.remove(at: selection.head)
        return (String(characters), selection)
    }

    /// Moves the caret one grapheme cluster left, collapsing any selection.
    /// A no-op at the start of the field.
    static func moveLeft(_ value: String, from selection: Selection) -> Selection {
        let selection = selection.clamped(to: value.count)
        guard selection.head > 0 else { return selection }
        let newHead = selection.head - 1
        return Selection(anchor: newHead, head: newHead)
    }

    /// Moves the caret one grapheme cluster right, collapsing any
    /// selection. A no-op at the end of the field.
    static func moveRight(_ value: String, from selection: Selection) -> Selection {
        let selection = selection.clamped(to: value.count)
        guard selection.head < value.count else { return selection }
        let newHead = selection.head + 1
        return Selection(anchor: newHead, head: newHead)
    }

    /// Moves the caret to the start of the field.
    static func moveToStart(_ value: String) -> Selection {
        Selection(anchor: 0, head: 0)
    }

    /// Moves the caret to the end of the field.
    static func moveToEnd(_ value: String) -> Selection {
        let count = value.count
        return Selection(anchor: count, head: count)
    }
}
