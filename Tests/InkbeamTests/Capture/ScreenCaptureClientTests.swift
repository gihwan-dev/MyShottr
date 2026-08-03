import ScreenCaptureKit
import XCTest
@testable import Inkbeam

final class ScreenCaptureClientTests: XCTestCase {
    func testConfigurationUsesExactPixelDimensions() throws {
        let configuration = try ScreenCaptureClient.configuration(
            for: CaptureFixtures.retinaSelection
        )

        XCTAssertEqual(configuration.width, 600)
        XCTAssertEqual(configuration.height, 400)
        XCTAssertEqual(
            configuration.sourceRect,
            CGRect(x: 100, y: 702, width: 300, height: 200)
        )
        XCTAssertFalse(configuration.showsCursor)
    }

    func testConfigurationRejectsEmptySelection() {
        let selection = RegionSelection(
            display: CaptureFixtures.retinaDisplay,
            rectInDisplayPoints: .zero
        )

        XCTAssertThrowsError(try ScreenCaptureClient.configuration(for: selection)) {
            XCTAssertEqual($0 as? CaptureError, .emptySelection)
        }
    }

    func testCaptureRequiresPermissionBeforeCallingCaptureAdapter() async {
        let permission = ScreenCapturePermission(
            preflight: { false },
            request: { false }
        )
        let client = ScreenCaptureClient(
            permission: permission,
            captureImage: { _, _ in
                XCTFail("The capture adapter must not run without permission")
                throw CaptureError.screenCaptureKitFailed
            }
        )

        do {
            _ = try await client.capture(selection: CaptureFixtures.retinaSelection)
            XCTFail("Capture must fail when screen recording permission is denied")
        } catch {
            XCTAssertEqual(error as? CaptureError, .screenRecordingPermissionDenied)
        }
    }

    func testCaptureMapsAdapterFailureToActionableCaptureError() async {
        let permission = ScreenCapturePermission(
            preflight: { true },
            request: { false }
        )
        let client = ScreenCaptureClient(
            permission: permission,
            captureImage: { _, _ in
                throw NSError(
                    domain: "ScreenCaptureClientTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "capture unavailable"]
                )
            }
        )

        do {
            _ = try await client.capture(selection: CaptureFixtures.retinaSelection)
            XCTFail("Capture must surface adapter failures")
        } catch {
            XCTAssertEqual(
                error as? CaptureError,
                .screenCaptureKitFailed
            )
        }
    }

    func testCaptureReturnsScreenRegionArtifactWithoutRealPermissionOrCapture() async throws {
        let screenshot = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 600,
                height: 400,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        )
        let permission = ScreenCapturePermission(
            preflight: { true },
            request: {
                XCTFail("Preflight access must skip the permission request")
                return false
            }
        )
        let client = ScreenCaptureClient(
            permission: permission,
            captureImage: { displayID, configuration in
                XCTAssertEqual(displayID, CaptureFixtures.retinaDisplay.displayID)
                XCTAssertEqual(configuration.width, 600)
                XCTAssertEqual(configuration.height, 400)
                XCTAssertEqual(
                    configuration.sourceRect,
                    CGRect(x: 100, y: 702, width: 300, height: 200)
                )
                XCTAssertFalse(configuration.showsCursor)
                return screenshot
            }
        )

        let artifact = try await client.capture(selection: CaptureFixtures.retinaSelection)

        XCTAssertEqual(artifact.sourceKind, .screenRegion)
        XCTAssertEqual(artifact.pixelWidth, 600)
        XCTAssertEqual(artifact.pixelHeight, 400)
        XCTAssertEqual(artifact.scale, 2)
    }
}
