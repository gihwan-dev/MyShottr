import AppKit

@MainActor
class RegionSelectionPanel: NSPanel {
    let display: DisplayDescriptor
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    private var isCaptureActive = false

    init(
        display: DisplayDescriptor,
        contentView: RegionSelectionView
    ) {
        self.display = display
        super.init(
            contentRect: display.frameInAppKitPoints,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
    }

    override var canBecomeKey: Bool {
        isCaptureActive
    }

    override var canBecomeMain: Bool {
        false
    }

    func beginCapture() {
        isCaptureActive = true
        orderFrontRegardless()
        if let contentView {
            invalidateCursorRects(for: contentView)
        }
    }

    func activateForCapture() {
        makeKeyAndOrderFront(nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel?()
        case 36, 76:
            onConfirm?()
        default:
            super.keyDown(with: event)
        }
    }

    override func close() {
        onCancel?()
        super.close()
    }
}
