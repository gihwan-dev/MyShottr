import AppKit

@MainActor
final class RegionSelectionView: NSView {
    static let dimmingOpacity: CGFloat = 0.55
    static let handleSize = CGSize(width: 8, height: 8)

    let display: DisplayDescriptor
    var onAction: ((RegionSelectionEvent) -> Void)?
    var selectionRect: CGRect? {
        didSet {
            needsDisplay = true
        }
    }

    init(display: DisplayDescriptor) {
        self.display = display
        super.init(frame: CGRect(origin: .zero, size: display.frameInAppKitPoints.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let selectionRect, !selectionRect.isEmpty {
            if let handle = Self.resizeHandle(
                at: point,
                selectionRect: selectionRect
            ) {
                onAction?(.beginResize(handle, point))
            } else if selectionRect.contains(point) {
                onAction?(.beginMove(point))
            } else {
                onAction?(.pointerDown(point))
            }
        } else {
            onAction?(.pointerDown(point))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        onAction?(
            .pointerDragged(convert(event.locationInWindow, from: nil))
        )
    }

    override func mouseUp(with event: NSEvent) {
        onAction?(.pointerUp)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.saveGState()
        context.setFillColor(
            NSColor.black.withAlphaComponent(Self.dimmingOpacity).cgColor
        )
        context.fill(bounds)

        if let selectionRect, !selectionRect.isEmpty {
            context.setBlendMode(.clear)
            context.fill(selectionRect)
            context.setBlendMode(.normal)

            context.setStrokeColor(NSColor.white.cgColor)
            let borderWidth = Self.borderWidth(for: display)
            context.setLineWidth(borderWidth)
            context.stroke(
                selectionRect.insetBy(
                    dx: borderWidth / 2,
                    dy: borderWidth / 2
                )
            )

            context.setFillColor(NSColor.white.cgColor)
            for handleRect in Self.resizeHandleRects(for: selectionRect).values {
                context.fill(handleRect)
            }

            drawDimensions(above: selectionRect)
        }

        context.restoreGState()
    }

    static func borderWidth(for display: DisplayDescriptor) -> CGFloat {
        1 / display.scale
    }

    static func dimensionText(
        for selectionRect: CGRect,
        display: DisplayDescriptor
    ) -> String {
        let pixels = DisplayGeometry.pixelRect(
            for: RegionSelection(
                display: display,
                rectInDisplayPoints: selectionRect
            )
        )
        return "\(Int(pixels.width)) × \(Int(pixels.height))"
    }

    static func resizeHandleRects(
        for selectionRect: CGRect
    ) -> [RegionResizeHandle: CGRect] {
        let midX = selectionRect.midX
        let midY = selectionRect.midY
        let centers: [RegionResizeHandle: CGPoint] = [
            .northWest: CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            .north: CGPoint(x: midX, y: selectionRect.maxY),
            .northEast: CGPoint(x: selectionRect.maxX, y: selectionRect.maxY),
            .east: CGPoint(x: selectionRect.maxX, y: midY),
            .southEast: CGPoint(x: selectionRect.maxX, y: selectionRect.minY),
            .south: CGPoint(x: midX, y: selectionRect.minY),
            .southWest: CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            .west: CGPoint(x: selectionRect.minX, y: midY),
        ]

        return centers.mapValues { center in
            CGRect(
                x: center.x - handleSize.width / 2,
                y: center.y - handleSize.height / 2,
                width: handleSize.width,
                height: handleSize.height
            )
        }
    }

    private static func resizeHandle(
        at point: CGPoint,
        selectionRect: CGRect
    ) -> RegionResizeHandle? {
        let handles = resizeHandleRects(for: selectionRect)
        return RegionResizeHandle.allCases.first {
            handles[$0]?.contains(point) == true
        }
    }

    private func drawDimensions(above selectionRect: CGRect) {
        let text = Self.dimensionText(
            for: selectionRect,
            display: display
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: 12,
                weight: .medium
            ),
            .foregroundColor: NSColor.white,
        ]
        let attributedText = NSAttributedString(
            string: text,
            attributes: attributes
        )
        let textSize = attributedText.size()
        attributedText.draw(
            at: CGPoint(
                x: selectionRect.midX - textSize.width / 2,
                y: selectionRect.maxY + 8
            )
        )
    }
}
