import Cocoa

protocol ClipboardWriting {
    @discardableResult
    func writeText(_ text: String) -> Bool
}

/// Optional capability: capture the pasteboard before PromptPanel overwrites it,
/// and put it back afterwards. Kept separate from `ClipboardWriting` so test
/// doubles that only record writes keep compiling.
protocol ClipboardSnapshotting: AnyObject {
    /// Copies every item/type on the general pasteboard. `nil` when it was empty.
    func captureSnapshot() -> ClipboardSnapshot?
    /// Writes `text`, flagged as transient so clipboard-history tools skip it.
    /// Returns the pasteboard `changeCount` right after the write, or `nil` on failure.
    func writeTransientText(_ text: String) -> Int?
    /// Restores `snapshot` only if nothing else touched the pasteboard since
    /// `expectedChangeCount` — a copy the user made in the meantime always wins.
    @discardableResult
    func restore(_ snapshot: ClipboardSnapshot, ifChangeCountIs expectedChangeCount: Int) -> Bool
}

struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
}

/// Manages clipboard read/write operations.
final class ClipboardService: ClipboardWriting, ClipboardSnapshotting {
    /// nspasteboard.org convention honoured by Maccy, Paste, Raycast, Alfred, etc.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    /// Hard cap so a huge image on the clipboard is not duplicated in memory.
    private static let maxSnapshotBytes = 32 * 1024 * 1024

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Write text content to the system clipboard.
    /// - Returns: true if successful, false otherwise.
    @discardableResult
    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        if success {
            PPLogger.clipboard.debug("Clipboard write succeeded (\(text.count) chars)")
        } else {
            PPLogger.clipboard.error("Clipboard write failed")
        }
        return success
    }

    func captureSnapshot() -> ClipboardSnapshot? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            return nil
        }
        var totalBytes = 0
        var captured: [[NSPasteboard.PasteboardType: Data]] = []
        for item in items {
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                totalBytes += data.count
                if totalBytes > Self.maxSnapshotBytes {
                    PPLogger.clipboard.notice("Clipboard snapshot skipped: content too large to restore")
                    return nil
                }
                types[type] = data
            }
            if !types.isEmpty {
                captured.append(types)
            }
        }
        return captured.isEmpty ? nil : ClipboardSnapshot(items: captured)
    }

    func writeTransientText(_ text: String) -> Int? {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        guard pasteboard.writeObjects([item]) else {
            PPLogger.clipboard.error("Transient clipboard write failed")
            return nil
        }
        return pasteboard.changeCount
    }

    @discardableResult
    func restore(_ snapshot: ClipboardSnapshot, ifChangeCountIs expectedChangeCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else {
            PPLogger.clipboard.info("Clipboard restore skipped: pasteboard changed since paste")
            return false
        }
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = snapshot.items.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types {
                item.setData(data, forType: type)
            }
            return item
        }
        let restored = pasteboard.writeObjects(items)
        PPLogger.clipboard.info("Clipboard restored after paste: \(restored)")
        return restored
    }
}
