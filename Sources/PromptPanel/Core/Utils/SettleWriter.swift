import Foundation

/// Coalesces a value that changes continuously while the user drags, and persists it
/// once things settle — off the main thread.
///
/// Why this exists: `windowDidMove` and `windowDidResize` arrive on *every frame* of a
/// drag. Persisting directly from those callbacks meant one SQLite write per frame, on
/// the main thread, for the whole duration of the drag — which is precisely when the
/// main thread needs to be free to keep the window tracking the pointer. The panel
/// origin had an ad-hoc debounce; the panel size had none at all.
///
/// Two details are load-bearing, and both are easy to get wrong again:
///
/// 1. **The pending value lives here, not inside the `DispatchWorkItem`'s block.**
///    `DispatchWorkItem.cancel()` makes the block a no-op forever after — so the
///    previous "cancel, then `perform()` to flush on terminate" idiom silently wrote
///    nothing, while its comment claimed the final position was never lost. Holding
///    the value separately means `flush()` can write it directly.
/// 2. **`flush()` is synchronous.** It is called from `applicationWillTerminate`,
///    which is the last moment the process is guaranteed to be alive; handing the
///    write to a background queue there would be a race against exit.
@MainActor
final class SettleWriter<Value: Sendable> {
    private let interval: DispatchTimeInterval
    private let queue: DispatchQueue
    private let write: @Sendable (Value) -> Void

    private var pendingValue: Value?
    private var workItem: DispatchWorkItem?

    /// - Parameters:
    ///   - interval: Quiet period after the last `schedule(_:)` before the value is written.
    ///   - queue: Where the write runs. Never the main queue — that is the whole point.
    ///   - write: Performs the persistence. Called at most once per settle, and once more
    ///     from `flush()` if a value is still pending.
    init(
        interval: DispatchTimeInterval,
        queue: DispatchQueue,
        write: @escaping @Sendable (Value) -> Void
    ) {
        self.interval = interval
        self.queue = queue
        self.write = write
    }

    /// Record the newest value and restart the quiet period. Intermediate values are
    /// dropped on purpose: only where the drag ended is worth persisting.
    func schedule(_ value: Value) {
        workItem?.cancel()
        pendingValue = value

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.writePending()
            }
        }
        self.workItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    /// Drop the pending value without writing it. Use when an explicit, authoritative
    /// write supersedes whatever the drag left behind — otherwise the stale settle
    /// write lands afterwards and wins.
    func cancel() {
        workItem?.cancel()
        workItem = nil
        pendingValue = nil
    }

    /// Write any pending value immediately, on the calling thread. For `applicationWillTerminate`.
    func flush() {
        workItem?.cancel()
        workItem = nil
        guard let value = pendingValue else { return }
        pendingValue = nil
        write(value)
    }

    private func writePending() {
        workItem = nil
        guard let value = pendingValue else { return }
        pendingValue = nil
        let write = self.write
        queue.async { write(value) }
    }
}
