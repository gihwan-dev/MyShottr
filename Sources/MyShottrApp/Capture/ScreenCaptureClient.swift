import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

protocol ScreenCapturing: Sendable {
    func capture(selection: RegionSelection) async throws -> CaptureArtifact
}

struct ScreenCaptureClient: ScreenCapturing, @unchecked Sendable {
    typealias CaptureImage = (
        _ displayID: CGDirectDisplayID,
        _ configuration: SCStreamConfiguration
    ) async throws -> CGImage

    private let permission: any ScreenCapturePermissionProviding
    private let captureImage: CaptureImage

    init(
        permission: any ScreenCapturePermissionProviding = ScreenCapturePermission(),
        captureImage: @escaping CaptureImage = Self.captureImageWithScreenCaptureKit
    ) {
        self.permission = permission
        self.captureImage = captureImage
    }

    static func configuration(for selection: RegionSelection) throws -> SCStreamConfiguration {
        guard !selection.rectInDisplayPoints.isEmpty else {
            throw CaptureError.emptySelection
        }

        let pixelRect = DisplayGeometry.pixelRect(for: selection)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = DisplayGeometry.sourceRect(for: selection)
        configuration.width = Int(pixelRect.width)
        configuration.height = Int(pixelRect.height)
        configuration.showsCursor = false
        return configuration
    }

    func capture(selection: RegionSelection) async throws -> CaptureArtifact {
        try permission.requireAccess()
        let configuration = try Self.configuration(for: selection)

        let image: CGImage
        do {
            image = try await captureImage(selection.display.displayID, configuration)
        } catch let error as CaptureError {
            throw error
        } catch {
            throw CaptureError.screenCaptureKitFailed
        }

        let pngData = try Self.encodePNG(image)
        do {
            return try CaptureArtifact(
                id: UUID(),
                sourceKind: .screenRegion,
                pngData: pngData,
                scale: Double(selection.display.scale)
            )
        } catch {
            throw CaptureError.pngEncodingFailed
        }
    }

    private static func captureImageWithScreenCaptureKit(
        displayID: CGDirectDisplayID,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayUnavailable(displayID)
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.pngEncodingFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.pngEncodingFailed
        }

        return data as Data
    }
}
