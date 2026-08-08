import AppKit

enum PNGClipboardWriterError: Error, Equatable {
    case writeFailed
}

struct PNGClipboardWriter {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(data: Data) throws {
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else {
            throw PNGClipboardWriterError.writeFailed
        }
    }
}
