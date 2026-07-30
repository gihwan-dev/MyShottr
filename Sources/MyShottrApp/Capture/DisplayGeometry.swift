import Foundation

enum DisplayGeometry {
    static func localRect(
        fromGlobalAppKitRect rect: CGRect,
        on display: DisplayDescriptor
    ) -> CGRect {
        CGRect(
            x: rect.minX - display.frameInAppKitPoints.minX,
            y: rect.minY - display.frameInAppKitPoints.minY,
            width: rect.width,
            height: rect.height
        )
    }

    static func pixelRect(for selection: RegionSelection) -> CGRect {
        let source = sourceRect(for: selection)
        return CGRect(
            x: source.minX * selection.display.scale,
            y: source.minY * selection.display.scale,
            width: source.width * selection.display.scale,
            height: source.height * selection.display.scale
        ).integral
    }

    static func sourceRect(for selection: RegionSelection) -> CGRect {
        let points = clamp(selection.rectInDisplayPoints, to: selection.display)
        let displayHeight = selection.display.frameInAppKitPoints.height
        return CGRect(
            x: points.minX,
            y: displayHeight - points.maxY,
            width: points.width,
            height: points.height
        )
    }

    static func clamp(_ rect: CGRect, to display: DisplayDescriptor) -> CGRect {
        let bounds = CGRect(origin: .zero, size: display.frameInAppKitPoints.size)
        let width = min(max(1, rect.width), bounds.width)
        let height = min(max(1, rect.height), bounds.height)
        return CGRect(
            x: min(max(bounds.minX, rect.minX), bounds.maxX - width),
            y: min(max(bounds.minY, rect.minY), bounds.maxY - height),
            width: width,
            height: height
        )
    }
}
