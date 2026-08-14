import AppKit
import XCTest
@testable import Inkbeam

@MainActor
final class RegionSelectionStateTests: XCTestCase {
    func testDragCreatesNormalizedSelection() {
        var state = RegionSelectionState(display: CaptureFixtures.retinaDisplay)

        state.reduce(.pointerDown(CGPoint(x: 400, y: 300)))
        state.reduce(.pointerDragged(CGPoint(x: 100, y: 80)))

        XCTAssertEqual(
            state.selectionRect,
            CGRect(x: 100, y: 80, width: 300, height: 220)
        )
    }

    func testPointerUpConfirmsNewlyDraggedSelection() {
        let expectedRect = CGRect(x: 100, y: 80, width: 300, height: 220)
        var state = RegionSelectionState(display: CaptureFixtures.retinaDisplay)

        state.reduce(.pointerDown(CGPoint(x: 400, y: 300)))
        state.reduce(.pointerDragged(CGPoint(x: 100, y: 80)))
        state.reduce(.pointerUp)

        XCTAssertEqual(
            state.result,
            .confirmed(
                RegionSelection(
                    display: CaptureFixtures.retinaDisplay,
                    rectInDisplayPoints: expectedRect
                )
            )
        )
    }

    func testPointerUpDoesNotConfirmClickWithoutDrag() {
        let point = CGPoint(x: 400, y: 300)
        var state = RegionSelectionState(display: CaptureFixtures.retinaDisplay)

        state.reduce(.pointerDown(point))
        state.reduce(.pointerUp)

        XCTAssertNil(state.result)
    }

    func testSecondPointerDownReplacesExistingSelection() {
        var state = RegionSelectionState(
            display: CaptureFixtures.retinaDisplay,
            selectionRect: CGRect(x: 100, y: 100, width: 300, height: 200)
        )

        state.reduce(.pointerDown(CGPoint(x: 700, y: 600)))
        state.reduce(.pointerDragged(CGPoint(x: 800, y: 700)))

        XCTAssertEqual(
            state.selectionRect,
            CGRect(x: 700, y: 600, width: 100, height: 100)
        )
    }

    func testMoveClampsSelectionToDisplay() {
        var state = RegionSelectionState(
            display: CaptureFixtures.retinaDisplay,
            selectionRect: CGRect(x: 100, y: 100, width: 300, height: 200)
        )

        state.reduce(.beginMove(CGPoint(x: 150, y: 150)))
        state.reduce(.pointerDragged(CGPoint(x: -500, y: -500)))
        state.reduce(.pointerUp)

        XCTAssertEqual(state.selectionRect?.origin, .zero)
        XCTAssertEqual(state.selectionRect?.size, CGSize(width: 300, height: 200))
        XCTAssertNil(state.result)
    }

    func testEveryResizeHandleMovesItsEdges() {
        let cases: [(
            handle: RegionResizeHandle,
            start: CGPoint,
            drag: CGPoint,
            expected: CGRect
        )] = [
            (
                .northWest,
                CGPoint(x: 100, y: 300),
                CGPoint(x: 50, y: 350),
                CGRect(x: 50, y: 100, width: 350, height: 250)
            ),
            (
                .north,
                CGPoint(x: 250, y: 300),
                CGPoint(x: 250, y: 350),
                CGRect(x: 100, y: 100, width: 300, height: 250)
            ),
            (
                .northEast,
                CGPoint(x: 400, y: 300),
                CGPoint(x: 450, y: 350),
                CGRect(x: 100, y: 100, width: 350, height: 250)
            ),
            (
                .east,
                CGPoint(x: 400, y: 200),
                CGPoint(x: 450, y: 200),
                CGRect(x: 100, y: 100, width: 350, height: 200)
            ),
            (
                .southEast,
                CGPoint(x: 400, y: 100),
                CGPoint(x: 450, y: 50),
                CGRect(x: 100, y: 50, width: 350, height: 250)
            ),
            (
                .south,
                CGPoint(x: 250, y: 100),
                CGPoint(x: 250, y: 50),
                CGRect(x: 100, y: 50, width: 300, height: 250)
            ),
            (
                .southWest,
                CGPoint(x: 100, y: 100),
                CGPoint(x: 50, y: 50),
                CGRect(x: 50, y: 50, width: 350, height: 250)
            ),
            (
                .west,
                CGPoint(x: 100, y: 200),
                CGPoint(x: 50, y: 200),
                CGRect(x: 50, y: 100, width: 350, height: 200)
            ),
        ]

        for testCase in cases {
            var state = RegionSelectionState(
                display: CaptureFixtures.retinaDisplay,
                selectionRect: CGRect(x: 100, y: 100, width: 300, height: 200)
            )

            state.reduce(.beginResize(testCase.handle, testCase.start))
            state.reduce(.pointerDragged(testCase.drag))

            XCTAssertEqual(
                state.selectionRect,
                testCase.expected,
                "Unexpected rectangle for \(testCase.handle)"
            )
        }
    }

    func testResizeClampsMovingEdgesToDisplayBounds() {
        var state = RegionSelectionState(
            display: CaptureFixtures.retinaDisplay,
            selectionRect: CGRect(x: 100, y: 100, width: 300, height: 200)
        )

        state.reduce(.beginResize(.southWest, CGPoint(x: 100, y: 100)))
        state.reduce(.pointerDragged(CGPoint(x: -500, y: -500)))
        state.reduce(.pointerUp)

        XCTAssertEqual(
            state.selectionRect,
            CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        XCTAssertNil(state.result)
    }

    func testInactiveDisplayIgnoresInteractionAndConfirmationEvents() {
        let original = CGRect(x: 100, y: 100, width: 300, height: 200)
        var state = RegionSelectionState(
            display: CaptureFixtures.retinaDisplay,
            selectionRect: original,
            isActive: false
        )

        state.reduce(.beginMove(CGPoint(x: 150, y: 150)))
        state.reduce(.pointerDragged(CGPoint(x: 500, y: 500)))
        state.reduce(.confirm)

        XCTAssertEqual(state.selectionRect, original)
        XCTAssertNil(state.result)
    }

    func testPointerDownActivatesInactiveDisplay() {
        var state = RegionSelectionState(
            display: CaptureFixtures.retinaDisplay,
            isActive: false
        )

        state.reduce(.pointerDown(CGPoint(x: 100, y: 80)))
        state.reduce(.pointerDragged(CGPoint(x: 400, y: 300)))

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(
            state.selectionRect,
            CGRect(x: 100, y: 80, width: 300, height: 220)
        )
    }

    func testReturnConfirmsOnlyNonEmptySelection() {
        var state = RegionSelectionState(display: CaptureFixtures.retinaDisplay)

        state.reduce(.confirm)

        XCTAssertNil(state.result)
    }

    func testReturnConfirmsRegionSelection() {
        let rect = CGRect(x: 100, y: 80, width: 300, height: 200)
        var state = RegionSelectionState(
            display: CaptureFixtures.retinaDisplay,
            selectionRect: rect
        )

        state.reduce(.confirm)

        XCTAssertEqual(
            state.result,
            .confirmed(
                RegionSelection(
                    display: CaptureFixtures.retinaDisplay,
                    rectInDisplayPoints: rect
                )
            )
        )
    }

    func testEscapeCancelsSelection() {
        var state = RegionSelectionState(display: CaptureFixtures.retinaDisplay)

        state.reduce(.cancel)

        XCTAssertEqual(state.result, .cancelled)
    }
}

extension RegionSelectionStateTests {
    func testPanelAcceptsKeyEventsOnlyAfterCaptureBegins() {
        let view = RegionSelectionView(display: CaptureFixtures.retinaDisplay)
        let panel = RegionSelectionPanel(
            display: CaptureFixtures.retinaDisplay,
            contentView: view
        )

        XCTAssertFalse(panel.canBecomeKey)

        panel.beginCapture()

        XCTAssertTrue(panel.canBecomeKey)
        panel.orderOut(nil)
    }

    func testSelectRegionCreatesConfiguredPanelForEveryDisplay() async throws {
        let harness = makeHarness()
        let selection = Task { try await harness.controller.selectRegion() }
        await Task.yield()

        XCTAssertEqual(
            harness.panels.map(\.display.displayID),
            [
                CaptureFixtures.retinaDisplay.displayID,
                CaptureFixtures.leftDisplay.displayID,
            ]
        )
        for panel in harness.panels {
            XCTAssertTrue(panel.styleMask.contains(.borderless))
            XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
            XCTAssertFalse(panel.isOpaque)
            XCTAssertEqual(panel.backgroundColor, .clear)
            XCTAssertEqual(panel.level, .screenSaver)
            XCTAssertTrue(panel.canBecomeKey)
        }

        harness.controller.cancel()
        let outcome = try await selection.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testSelectRegionActivatesPanelUnderPointerBeforeCrosshair() async throws {
        let harness = makeHarness(pointerLocation: CGPoint(x: -100, y: 200))
        let selection = Task { try await harness.controller.selectRegion() }
        await Task.yield()

        XCTAssertEqual(
            harness.storage.presentationEvents,
            [
                .panelActivated(CaptureFixtures.leftDisplay.displayID),
                .crosshair,
            ]
        )
        XCTAssertFalse(harness.panels[0].isKeyWindow)
        XCTAssertTrue(harness.panels[1].isKeyWindow)

        harness.controller.cancel()
        let outcome = try await selection.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testDragFromNonActiveDisplayIsIgnored() async throws {
        let harness = makeHarness()
        let selection = Task { try await harness.controller.selectRegion() }
        await Task.yield()

        harness.controller.handle(
            .pointerDown(CGPoint(x: 100, y: 100)),
            from: CaptureFixtures.retinaDisplay.displayID
        )
        harness.controller.handle(
            .pointerDragged(CGPoint(x: 500, y: 500)),
            from: CaptureFixtures.leftDisplay.displayID
        )

        XCTAssertEqual(
            harness.views[CaptureFixtures.retinaDisplay.displayID]?.selectionRect,
            CGRect(x: 100, y: 100, width: 0, height: 0)
        )
        XCTAssertNil(
            harness.views[CaptureFixtures.leftDisplay.displayID]?.selectionRect
        )

        harness.controller.handle(
            .pointerDragged(CGPoint(x: 400, y: 300)),
            from: CaptureFixtures.retinaDisplay.displayID
        )
        XCTAssertEqual(
            harness.views[CaptureFixtures.retinaDisplay.displayID]?.selectionRect,
            CGRect(x: 100, y: 100, width: 300, height: 200)
        )

        harness.controller.cancel()
        _ = try await selection.value
    }

    func testPointerUpOrdersOutEveryPanelBeforeReturningSelection() async throws {
        let harness = makeHarness()
        let selection = Task { try await harness.controller.selectRegion() }
        await Task.yield()

        harness.controller.handle(
            .pointerDown(CGPoint(x: 100, y: 80)),
            from: CaptureFixtures.retinaDisplay.displayID
        )
        harness.controller.handle(
            .pointerDragged(CGPoint(x: 400, y: 280)),
            from: CaptureFixtures.retinaDisplay.displayID
        )
        harness.controller.handle(
            .pointerUp,
            from: CaptureFixtures.retinaDisplay.displayID
        )

        let outcome = try await selection.value
        XCTAssertEqual(
            outcome,
            .confirmed(
                RegionSelection(
                    display: CaptureFixtures.retinaDisplay,
                    rectInDisplayPoints: CGRect(
                        x: 100,
                        y: 80,
                        width: 300,
                        height: 200
                    )
                )
            )
        )
        XCTAssertTrue(harness.panels.allSatisfy { $0.orderOutCount == 1 })
        XCTAssertFalse(harness.controller.isSelecting)
        XCTAssertEqual(harness.storage.cursorEvents, [.crosshair, .restored])
    }

    func testCancelResolvesAndClearsContinuationExactlyOnce() async throws {
        let harness = makeHarness()
        let selection = Task { try await harness.controller.selectRegion() }
        await Task.yield()

        harness.controller.cancel()
        harness.controller.cancel()

        let outcome = try await selection.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(harness.panels.allSatisfy { $0.orderOutCount == 1 })
        XCTAssertFalse(harness.controller.isSelecting)
        XCTAssertEqual(harness.storage.cursorEvents, [.crosshair, .restored])
    }

    func testClosingAnyPanelCancelsAndClearsSelection() async throws {
        let harness = makeHarness()
        let selection = Task { try await harness.controller.selectRegion() }
        await Task.yield()

        harness.panels[1].close()

        let outcome = try await selection.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertFalse(harness.controller.isSelecting)
        XCTAssertEqual(harness.storage.cursorEvents, [.crosshair, .restored])
    }

    func testEscapeKeyResolvesAndClearsSelection() async throws {
        let harness = makeHarness()
        let selection = Task { try await harness.controller.selectRegion() }
        await Task.yield()
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
        )

        harness.panels[0].keyDown(with: event)

        let outcome = try await selection.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertFalse(harness.controller.isSelecting)
    }

    func testReturnKeyConfirmsNonEmptySelection() async throws {
        let harness = makeHarness()
        let selection = Task { try await harness.controller.selectRegion() }
        await Task.yield()
        harness.controller.handle(
            .pointerDown(CGPoint(x: 100, y: 80)),
            from: CaptureFixtures.retinaDisplay.displayID
        )
        harness.controller.handle(
            .pointerDragged(CGPoint(x: 400, y: 280)),
            from: CaptureFixtures.retinaDisplay.displayID
        )
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )
        )

        harness.panels[0].keyDown(with: event)

        let outcome = try await selection.value
        XCTAssertEqual(
            outcome,
            .confirmed(
                RegionSelection(
                    display: CaptureFixtures.retinaDisplay,
                    rectInDisplayPoints: CGRect(
                        x: 100,
                        y: 80,
                        width: 300,
                        height: 200
                    )
                )
            )
        )
        XCTAssertTrue(harness.panels.allSatisfy { $0.orderOutCount == 1 })
        XCTAssertFalse(harness.controller.isSelecting)
        XCTAssertEqual(harness.storage.cursorEvents, [.crosshair, .restored])
    }

    func testSecondSelectionWhileContinuationIsPendingThrows() async throws {
        let harness = makeHarness()
        let firstSelection = Task { try await harness.controller.selectRegion() }
        await Task.yield()

        do {
            _ = try await harness.controller.selectRegion()
            XCTFail("A second selection must not create another overlay")
        } catch {
            XCTAssertEqual(error as? CaptureError, .captureAlreadyInProgress)
        }
        XCTAssertEqual(harness.panels.count, 2)

        harness.controller.cancel()
        let outcome = try await firstSelection.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testCancelRestoresCursorExactlyOnce() async throws {
        let harness = makeHarness()
        let selection = Task { try await harness.controller.selectRegion() }
        await Task.yield()

        XCTAssertEqual(harness.storage.cursorEvents, [.crosshair])

        harness.controller.cancel()
        _ = try await selection.value

        XCTAssertEqual(harness.storage.cursorEvents, [.crosshair, .restored])
    }

    func testOverlayMetricsUseSourcePixelsAndEightPointHandles() {
        let rect = CGRect(x: 100, y: 80, width: 300, height: 200)

        XCTAssertEqual(
            RegionSelectionView.dimensionText(
                for: rect,
                display: CaptureFixtures.retinaDisplay
            ),
            "600 × 400"
        )
        XCTAssertEqual(
            RegionSelectionView.borderWidth(
                for: CaptureFixtures.retinaDisplay
            ),
            0.5
        )
        let handles = RegionSelectionView.resizeHandleRects(for: rect)
        XCTAssertEqual(handles.count, 8)
        XCTAssertTrue(
            handles.values.allSatisfy {
                $0.size == CGSize(width: 8, height: 8)
            }
        )
    }

    private func makeHarness(
        pointerLocation: CGPoint = CGPoint(x: 100, y: 100)
    ) -> RegionSelectionControllerHarness {
        let storage = RegionSelectionControllerHarnessStorage()
        let controller = RegionSelectionController(
            displays: {
                [
                    CaptureFixtures.retinaDisplay,
                    CaptureFixtures.leftDisplay,
                ]
            },
            pointerLocation: {
                pointerLocation
            },
            panelFactory: { display, view in
                let panel = RecordingRegionSelectionPanel(
                    display: display,
                    contentView: view
                )
                panel.onActivateForCapture = {
                    storage.presentationEvents.append(
                        .panelActivated(display.displayID)
                    )
                }
                storage.panels.append(panel)
                storage.views[display.displayID] = view
                return panel
            },
            activateCrosshair: {
                storage.cursorEvents.append(.crosshair)
                storage.presentationEvents.append(.crosshair)
            },
            restoreCursor: {
                storage.cursorEvents.append(.restored)
            }
        )
        return RegionSelectionControllerHarness(
            controller: controller,
            storage: storage
        )
    }
}

@MainActor
private struct RegionSelectionControllerHarness {
    let controller: RegionSelectionController
    let storage: RegionSelectionControllerHarnessStorage

    var panels: [RecordingRegionSelectionPanel] {
        storage.panels
    }

    var views: [UInt32: RegionSelectionView] {
        storage.views
    }
}

@MainActor
private final class RegionSelectionControllerHarnessStorage {
    var panels: [RecordingRegionSelectionPanel] = []
    var views: [UInt32: RegionSelectionView] = [:]
    var cursorEvents: [RegionSelectionCursorEvent] = []
    var presentationEvents: [RegionSelectionPresentationEvent] = []
}

private enum RegionSelectionCursorEvent: Equatable {
    case crosshair
    case restored
}

private enum RegionSelectionPresentationEvent: Equatable {
    case panelActivated(UInt32)
    case crosshair
}

@MainActor
private final class RecordingRegionSelectionPanel: RegionSelectionPanel {
    private(set) var orderOutCount = 0
    var onActivateForCapture: (() -> Void)?

    override func activateForCapture() {
        super.activateForCapture()
        onActivateForCapture?()
    }

    override func orderOut(_ sender: Any?) {
        orderOutCount += 1
        super.orderOut(sender)
    }
}
