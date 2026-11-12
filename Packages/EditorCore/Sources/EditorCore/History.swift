// What: Snapshot-based undo/redo history with a 200-entry cap.
// Inputs/Outputs: States recorded, undone and redone; nil when the stack is empty.
// Threading: Value type, not thread-safe; own it on one thread/actor.
import Foundation

public struct History<State> {
    private var past: [State] = []
    private var future: [State] = []

    public init() {}

    public mutating func record(_ before: State) {
        past.append(before)
        future.removeAll()
        if past.count > 200 { past.removeFirst() }
    }

    public mutating func undo(current: State) -> State? {
        guard let p = past.popLast() else { return nil }
        future.append(current)
        return p
    }

    public mutating func redo(current: State) -> State? {
        guard let n = future.popLast() else { return nil }
        past.append(current)
        return n
    }
}
