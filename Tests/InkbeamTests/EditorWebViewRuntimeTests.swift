import Foundation
import AppKit
import Carbon
import ImageIO
import WebKit
import XCTest
@testable import Inkbeam

@MainActor
final class EditorWebViewRuntimeTests: TemporaryDirectoryTestCase {
    private static let runtimeSourcePixelWidth = 320
    private static let runtimeSourcePixelHeight = 200

    func testUsesInkbeamWebKitRuntimeContract() {
        XCTAssertEqual(EditorWebView.editorScheme, "inkbeam-editor")
        XCTAssertEqual(EditorWebView.bridgeName, "inkbeam")
    }

    func testBundledEditorLoadsValidProjectMountsCompositesTheSessionPNGAndSurfacesNavigationFailure() async throws {
        let session = DocumentSession()
        let editor = EditorWebView(session: session)
        var documentChangedCount = 0
        var historyStates: [EditorHistoryState] = []
        editor.onDocumentChanged = {
            documentChangedCount += 1
        }
        editor.onHistoryStateChanged = {
            historyStates.append($0)
        }
        let window = attach(editor.webView)
        XCTAssertTrue(window.makeFirstResponder(editor.webView))
        defer {
            window.contentView = nil
            window.close()
            editor.tearDown()
        }

        let loadOperation = try editor.load(project: validProject())
        try await loadOperation.wait()
        try await waitForEditorMount(in: editor.webView)
        let currentHandlerExists = try await evaluateBoolean(
            "typeof window.webkit?.messageHandlers?.inkbeam?.postMessage === 'function'",
            in: editor.webView
        )
        let oldHandlerIsAbsent = try await evaluateBoolean(
            "typeof window.webkit?.messageHandlers?.[['my', 'shottr'].join('')] === 'undefined'",
            in: editor.webView
        )
        XCTAssertTrue(currentHandlerExists)
        XCTAssertTrue(oldHandlerIsAbsent)
        try await waitForSourceImage(in: editor.webView)
        try await assertExternalResourcesAreBlocked(in: editor.webView)

        XCTAssertNil(editor.navigationError)
        XCTAssertTrue(session.isOpen)
        editor.setAppearance(.dark)
        try await assertAppearance(
            .dark,
            expectedRootColor: "rgb(248, 238, 233)",
            in: editor.webView
        )

        try await createRectangleWithApplicationEvents(
            in: editor.webView,
            window: window
        )
        try await waitUntil("rectangle history becomes undoable") {
            historyStates.contains(
                EditorHistoryState(canUndo: true, canRedo: false)
            )
        }
        try await waitUntil("rectangle emits documentChanged") {
            documentChangedCount >= 1
        }
        let snapshot = try await editor.requestAnnotationSnapshot()
        let snapshotJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: snapshot) as? [String: Any]
        )
        let elements = try XCTUnwrap(
            snapshotJSON["elements"] as? [[String: Any]]
        )
        XCTAssertEqual(elements.count, 1)
        let rectangle = try XCTUnwrap(elements.first)
        XCTAssertEqual(rectangle["type"] as? String, "rectangle")
        XCTAssertGreaterThan(rectangle["width"] as? Double ?? 0, 0)
        XCTAssertGreaterThan(rectangle["height"] as? Double ?? 0, 0)

        let liveCanvasJSONString = try await evaluateString(
            """
                JSON.stringify((() => {
                  const stage = window.Konva?.stages?.[0];
                  const layers = stage?.getLayers() ?? [];
                  const workspaceLayer = layers.find(
                    (layer) => layer.id() === 'workspaceLayer'
                  );
                  const viewportGroup = workspaceLayer?.getChildren()?.[0];
                  const sourceNode = viewportGroup?.getChildren(
                    (node) => node.getClassName() === 'Image'
                  )?.[0];
                  const elementNodes = viewportGroup?.getChildren(
                    (node) => node.getClassName() === 'Group'
                      && String(node.getAttr('data-testid') ?? '')
                        .startsWith('element-')
                  ) ?? [];
                  const elementNode = elementNodes[0];
                  const elementBounds = elementNode?.getClientRect({
                    relativeTo: stage,
                  });
                  const canvas = stage?.container()?.querySelector('canvas');
                  const pixels = canvas?.getContext('2d')?.getImageData(
                    0, 0, canvas.width, canvas.height
                  )?.data ?? [];
                  let nonTransparentPixels = 0;
                  for (let index = 3; index < pixels.length; index += 4) {
                    if (pixels[index] > 0) nonTransparentPixels += 1;
                  }
                  let hitNodeClass = null;
                  if (elementBounds && elementNode) {
                    const minX = Math.floor(elementBounds.x);
                    const maxX = Math.ceil(
                      elementBounds.x + elementBounds.width
                    );
                    const minY = Math.floor(elementBounds.y);
                    const maxY = Math.ceil(
                      elementBounds.y + elementBounds.height
                    );
                    for (let y = minY; y <= maxY && !hitNodeClass; y += 1) {
                      for (let x = minX; x <= maxX; x += 1) {
                        const candidate = stage?.getIntersection({ x, y });
                        if (candidate?.getParent() === elementNode) {
                          hitNodeClass = candidate.getClassName();
                          break;
                        }
                      }
                    }
                  }
                  return {
                    layerCount: layers.length,
                    elementNodeCount: elementNodes.length,
                    nonTransparentPixels,
                    hitNodeClass,
                    workspaceLayerIndex: workspaceLayer?.getZIndex(),
                    sourceNodeIndex: sourceNode?.getZIndex(),
                    elementNodeIndex: elementNode?.getZIndex(),
                  };
                })())
            """,
            in: editor.webView
        )
        let liveCanvas = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(liveCanvasJSONString.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(liveCanvas["layerCount"] as? Int, 1)
        XCTAssertEqual(liveCanvas["elementNodeCount"] as? Int, 1)
        XCTAssertGreaterThan(liveCanvas["nonTransparentPixels"] as? Int ?? 0, 0)
        XCTAssertEqual(liveCanvas["hitNodeClass"] as? String, "Path")
        XCTAssertEqual(liveCanvas["workspaceLayerIndex"] as? Int, 0)
        XCTAssertEqual(liveCanvas["sourceNodeIndex"] as? Int, 0)
        XCTAssertEqual(liveCanvas["elementNodeIndex"] as? Int, 1)

        let transfer = try await editor.requestComposite()
        let png = try transfer.data()
        XCTAssertTrue(png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(
            properties[kCGImagePropertyPixelWidth] as? Int,
            Self.runtimeSourcePixelWidth
        )
        XCTAssertEqual(
            properties[kCGImagePropertyPixelHeight] as? Int,
            Self.runtimeSourcePixelHeight
        )

        let documentChangedCheckpoint = documentChangedCount
        let historyCheckpoint = historyStates.count
        editor.performHistoryAction(.undo)
        try await waitUntil("undo emits one documentChanged") {
            documentChangedCount == documentChangedCheckpoint + 1
        }
        try await waitUntil("undo exposes redo history state") {
            historyStates.dropFirst(historyCheckpoint).contains(
                EditorHistoryState(canUndo: false, canRedo: true)
            )
        }
        let undoSnapshot = try await editor.requestAnnotationSnapshot()
        let undoSnapshotJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: undoSnapshot)
                as? [String: Any]
        )
        XCTAssertEqual(
            (undoSnapshotJSON["elements"] as? [[String: Any]])?.count,
            0
        )

        let saveRequestID = UUID()
        editor.sendOperationStatus(
            requestID: saveRequestID,
            status: .started(.save)
        )
        editor.sendOperationStatus(
            requestID: saveRequestID,
            status: .saveCompleted
        )
        try await assertSavedFeedback(in: editor.webView)

        editor.setAppearance(.light)
        try await assertAppearance(
            .light,
            expectedRootColor: "rgb(32, 27, 26)",
            in: editor.webView
        )

        let navigationFailed = expectation(description: "missing editor navigation failure is reported")
        editor.onNavigationFailure = { _ in navigationFailed.fulfill() }
        editor.webView(
            editor.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "Inkbeam.EditorBundle", code: 1)
        )
        await fulfillment(of: [navigationFailed], timeout: 5)
        XCTAssertNotNil(editor.navigationError)
    }

    func testAppKitOwnedOutputShortcutsRemainAvailableWhileWebKitOwnsFocusedControls()
        async throws
    {
        let previousMainMenu = NSApp.mainMenu
        let commandTarget = RuntimeOutputCommandTarget()
        NSApp.mainMenu = makeOutputCommandMenu(target: commandTarget)
        defer {
            NSApp.mainMenu = previousMainMenu
        }

        for focusOwner in RuntimeFocusOwner.allCases {
            for outputShortcut in RuntimeOutputShortcut.allCases {
                let project = try validProject()
                let projectURL = temporaryDirectory.appendingPathComponent(
                    "\(focusOwner.rawValue)-\(outputShortcut.rawValue).inkbeam",
                    isDirectory: true
                )
                let exportURL = temporaryDirectory.appendingPathComponent(
                    "\(focusOwner.rawValue)-\(outputShortcut.rawValue).png",
                    isDirectory: false
                )
                let store = RuntimeProjectStoreSpy()
                var annotationSnapshotCount = 0
                var compositeCount = 0
                var clipboardWriteCount = 0
                var exportDestinationCount = 0
                var hideCount = 0
                var statuses: [EditorOperationStatus] = []
                let controller = try DocumentWindowController(
                    project: project,
                    projectURL: projectURL,
                    projectStore: store,
                    preferences: StubPreferences(.approvedDefaults),
                    annotationSnapshotProvider: {
                        annotationSnapshotCount += 1
                        return project.annotationJSON
                    },
                    compositeProvider: { _ in
                        compositeCount += 1
                        return try self.makeCompletedRuntimeTransfer()
                    },
                    clipboardWriter: { _ in
                        clipboardWriteCount += 1
                    },
                    pngExportURLProvider: {
                        exportDestinationCount += 1
                        return exportURL
                    },
                    operationStatusSender: { _, status in
                        statuses.append(status)
                    },
                    windowHider: {
                        hideCount += 1
                    },
                    commandWindowPredicate: { _ in true }
                )
                controller.presentWindow()
                let window = try XCTUnwrap(controller.window)
                let webView = try XCTUnwrap(
                    window.contentView as? WKWebView
                )
                defer {
                    controller.discardFailedPresentation()
                    window.contentView = nil
                    window.close()
                }
                try await controller.waitForEditorLoad()
                try await waitForEditorMount(in: webView)
                try await waitForSourceImage(in: webView)
                window.makeKeyAndOrderFront(nil)
                XCTAssertTrue(window.makeFirstResponder(webView))

                try await enterFocusOwner(
                    focusOwner,
                    in: webView,
                    window: window
                )
                let before = try await captureFocusSnapshot(
                    in: webView
                )
                let revisionBeforeShortcut =
                    controller.modificationRevision
                let modifiedBeforeShortcut =
                    controller.hasModifiedDocument
                XCTAssertEqual(
                    before.activeOwner,
                    focusOwner.expectedActiveOwner
                )
                commandTarget.firstResponder = window.firstResponder
                let event = try outputShortcut.makeKeyEvent(
                    windowNumber: window.windowNumber
                )
                let invocationCount = commandTarget.invocationCount
                XCTAssertTrue(
                    try XCTUnwrap(NSApp.mainMenu)
                        .performKeyEquivalent(with: event),
                    "\(outputShortcut.rawValue) was not handled for \(focusOwner.rawValue)"
                )
                XCTAssertEqual(
                    commandTarget.invocationCount,
                    invocationCount + 1
                )
                XCTAssertTrue(commandTarget.lastDispatchSucceeded)
                XCTAssertTrue(controller.hasActiveOutputOperation)
                try await waitUntil(
                    "\(outputShortcut.rawValue) reaches its terminal"
                ) {
                    !controller.hasActiveOutputOperation
                        && outputShortcut.didReachExpectedTerminal(
                            annotationSnapshotCount:
                                annotationSnapshotCount,
                            compositeCount: compositeCount,
                            clipboardWriteCount:
                                clipboardWriteCount,
                            exportDestinationCount:
                                exportDestinationCount,
                            hideCount: hideCount,
                            saveCount: store.saveCount,
                            statuses: statuses
                        )
                }

                outputShortcut.assertExactNativeSeams(
                    annotationSnapshotCount:
                        annotationSnapshotCount,
                    compositeCount: compositeCount,
                    clipboardWriteCount: clipboardWriteCount,
                    exportDestinationCount:
                        exportDestinationCount,
                    hideCount: hideCount,
                    saveCount: store.saveCount,
                    statuses: statuses,
                    exportURL: exportURL
                )
                let after = try await captureFocusSnapshot(
                    in: webView
                )
                XCTAssertEqual(after, before)
                XCTAssertEqual(
                    controller.modificationRevision,
                    revisionBeforeShortcut
                )
                XCTAssertEqual(
                    controller.hasModifiedDocument,
                    modifiedBeforeShortcut
                )
                commandTarget.firstResponder = nil
            }
        }
    }

    func testDocumentWindowControllerSynchronizesEffectiveAppearanceAfterLoadAndOnChange()
        async throws
    {
        let controller = try DocumentWindowController(
            project: try validProject(),
            projectURL: nil,
            preferences: StubPreferences(.approvedDefaults)
        )
        let window = try XCTUnwrap(controller.window)
        let webView = try XCTUnwrap(
            window.contentView as? WKWebView
        )
        window.appearance = try XCTUnwrap(
            NSAppearance(named: .darkAqua)
        )
        controller.presentWindow()
        defer {
            controller.discardFailedPresentation()
            window.contentView = nil
            window.close()
        }

        try await controller.waitForEditorLoad()
        try await waitForEditorMount(in: webView)
        try await assertAppearance(
            .dark,
            expectedRootColor: "rgb(248, 238, 233)",
            in: webView
        )

        window.appearance = try XCTUnwrap(
            NSAppearance(named: .aqua)
        )
        try await assertAppearance(
            .light,
            expectedRootColor: "rgb(32, 27, 26)",
            in: webView
        )
    }

    private func waitForEditorMount(in webView: WKWebView) async throws {
        try await waitForJavaScriptPredicate(
            "React editor mounts with toolbar and canvas",
            predicate: """
            Boolean(
              document.getElementById('root')?.childElementCount &&
              document.querySelector('[aria-label="Annotation tools"]') &&
              document.querySelector('canvas')
            )
            """,
            in: webView
        )
    }

    private func waitForSourceImage(in webView: WKWebView) async throws {
        try await waitForJavaScriptPredicate(
            "source image loads into the workspace layer",
            predicate: """
            (() => {
              const image = window.Konva?.stages?.[0]?.findOne('Image')?.image();
              return Boolean(
                image?.complete &&
                image.naturalWidth === \(Self.runtimeSourcePixelWidth) &&
                image.naturalHeight === \(Self.runtimeSourcePixelHeight)
              );
            })()
            """,
            in: webView
        )
    }

    private func createRectangleWithApplicationEvents(
        in webView: WKWebView,
        window: NSWindow
    ) async throws {
        let clickResult = try await evaluateString(
            """
            (() => {
              const button = document.querySelector(
                '[aria-label="Annotation tools"] button[aria-label="Rectangle, shortcut R"]'
              );
              if (!button) throw new Error('Rectangle tool is unavailable');
              button.click();
              return 'clicked';
            })()
            """,
            in: webView
        )
        XCTAssertEqual(clickResult, "clicked")
        try await waitForJavaScriptPredicate(
            "rectangle tool activates after application events",
            predicate: """
            document.querySelector(
              '[aria-label="Annotation tools"] button[aria-label="Rectangle, shortcut R"]'
            )?.getAttribute('aria-pressed') === 'true'
            """,
            in: webView
        )

        let pointsJSONString = try await evaluateString(
            """
            (() => {
              const stage = window.Konva?.stages?.[0];
              const source = stage?.findOne('Image');
              const container = stage?.container();
              if (!stage || !source || !container) {
                throw new Error('Stage source geometry is unavailable');
              }
              const bounds = container.getBoundingClientRect();
              const origin = source.getAbsolutePosition();
              const scale = source.getAbsoluteScale();
              return JSON.stringify({
                startX: bounds.left + origin.x + (source.width() * 0.25 * scale.x),
                startY: bounds.top + origin.y + (source.height() * 0.25 * scale.y),
                endX: bounds.left + origin.x + (source.width() * 0.75 * scale.x),
                endY: bounds.top + origin.y + (source.height() * 0.75 * scale.y),
              });
            })()
            """,
            in: webView
        )
        let points = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(pointsJSONString.utf8))
                as? [String: Double]
        )
        let start = windowPoint(
            clientX: try XCTUnwrap(points["startX"]),
            clientY: try XCTUnwrap(points["startY"]),
            in: webView
        )
        let end = windowPoint(
            clientX: try XCTUnwrap(points["endX"]),
            clientY: try XCTUnwrap(points["endY"]),
            in: webView
        )
        let harness = try WebKitPointerEventHarness(
            webView: webView,
            window: window
        )
        try await harness.dragLeftButton(from: start, to: end)
    }

    private func enterFocusOwner(
        _ focusOwner: RuntimeFocusOwner,
        in webView: WKWebView,
        window: NSWindow
    ) async throws {
        switch focusOwner {
        case .inlineTextTextarea:
            _ = try await evaluateString(
                """
                (() => {
                  window.__inkbeamRuntimeKeyTrace = null;
                  window.addEventListener('keydown', (event) => {
                    window.__inkbeamRuntimeKeyTrace = JSON.stringify({
                      code: event.code,
                      isTrusted: event.isTrusted,
                    });
                  }, { capture: true, once: true });
                  return 'armed';
                })()
                """,
                in: webView
            )
            try sendWebKey(
                characters: "t",
                charactersIgnoringModifiers: "t",
                keyCode: UInt16(kVK_ANSI_T),
                modifiers: [],
                to: window
            )
            try await waitForJavaScriptPredicate(
                "trusted T shortcut activates the Text tool",
                predicate: """
                document.querySelector(
                  '[aria-label="Annotation tools"] button[aria-label="Text, shortcut T"]'
                )?.getAttribute('aria-pressed') === 'true'
                  && JSON.parse(
                    window.__inkbeamRuntimeKeyTrace ?? '{}'
                  ).code === 'KeyT'
                  && JSON.parse(
                    window.__inkbeamRuntimeKeyTrace ?? '{}'
                  ).isTrusted === true
                """,
                in: webView
            )
            let pointJSONString = try await evaluateString(
                """
                (() => {
                  const stage = window.Konva?.stages?.[0];
                  const source = stage?.findOne('Image');
                  const container = stage?.container();
                  const content = stage?.getContent();
                  if (!stage || !source || !container || !content) {
                    throw new Error('Text insertion geometry is unavailable');
                  }
                  const containerBounds = container.getBoundingClientRect();
                  const origin = source.getAbsolutePosition();
                  const scale = source.getAbsoluteScale();
                  window.__inkbeamRuntimePointerTrace = null;
                  content.addEventListener('pointerdown', (event) => {
                    window.__inkbeamRuntimePointerTrace = JSON.stringify({
                      isTrusted: event.isTrusted,
                      pointerType: event.pointerType,
                    });
                  }, { capture: true, once: true });
                  return JSON.stringify({
                    clientX: containerBounds.left + origin.x
                      + source.width() * 0.5 * scale.x,
                    clientY: containerBounds.top + origin.y
                      + source.height() * 0.5 * scale.y,
                  });
                })()
                """,
                in: webView
            )
            let point = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: Data(pointJSONString.utf8)
                ) as? [String: Double]
            )
            let harness = try WebKitPointerEventHarness(
                webView: webView,
                window: window
            )
            try await harness.clickLeftButton(
                at: windowPoint(
                    clientX: try XCTUnwrap(point["clientX"]),
                    clientY: try XCTUnwrap(point["clientY"]),
                    in: webView
                )
            )
            try await waitForJavaScriptPredicate(
                "trusted canvas click opens the inline text textarea",
                predicate: """
                document.activeElement instanceof HTMLTextAreaElement
                  && document.activeElement.getAttribute('aria-label')
                    === 'Edit annotation text'
                  && JSON.parse(
                    window.__inkbeamRuntimePointerTrace ?? '{}'
                  ).isTrusted === true
                  && JSON.parse(
                    window.__inkbeamRuntimePointerTrace ?? '{}'
                  ).pointerType === 'mouse'
                """,
                in: webView
            )
        case .shortcutHelpButton:
            _ = try await evaluateString(
                """
                (() => {
                  window.__inkbeamRuntimeKeyTrace = null;
                  window.addEventListener('keydown', (event) => {
                    window.__inkbeamRuntimeKeyTrace = JSON.stringify({
                      code: event.code,
                      isTrusted: event.isTrusted,
                    });
                  }, { capture: true, once: true });
                  return 'armed';
                })()
                """,
                in: webView
            )
            try sendWebKey(
                characters: "?",
                charactersIgnoringModifiers: "/",
                keyCode: UInt16(kVK_ANSI_Slash),
                modifiers: [.shift],
                to: window
            )
            try await waitForJavaScriptPredicate(
                "Shortcut help close button owns DOM focus",
                predicate: """
                document.activeElement instanceof HTMLButtonElement
                  && document.activeElement.getAttribute('aria-label')
                    === 'Close keyboard shortcuts'
                  && document.activeElement.closest(
                    '[role="dialog"][aria-labelledby="shortcut-help-title"]'
                  ) !== null
                  && JSON.parse(
                    window.__inkbeamRuntimeKeyTrace ?? '{}'
                  ).code === 'Slash'
                  && JSON.parse(
                    window.__inkbeamRuntimeKeyTrace ?? '{}'
                  ).isTrusted === true
                """,
                in: webView
            )
        }
    }

    private func sendWebKey(
        characters: String,
        charactersIgnoringModifiers: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        to window: NSWindow
    ) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers:
                charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        ))
        try XCTUnwrap(window.firstResponder).keyDown(with: event)
    }

    private func captureFocusSnapshot(
        in webView: WKWebView
    ) async throws -> RuntimeFocusSnapshot {
        let snapshotJSONString = try await evaluateString(
            """
            JSON.stringify((() => {
              const stage = window.Konva?.stages?.[0];
              if (!stage) throw new Error('Stage is unavailable');
              const elements = stage.find('Group')
                .filter((node) => String(
                  node.getAttr('data-testid') ?? ''
                ).startsWith('element-'))
                .map((node) => ({
                  id: node.getAttr('data-testid'),
                  x: node.x(),
                  y: node.y(),
                  width: node.width(),
                  height: node.height(),
                  rotation: node.rotation(),
                  text: node.findOne('Text')?.text() ?? null,
                }));
              const active = document.activeElement;
              return {
                documentFingerprint: JSON.stringify(elements),
                activeOwner: `${active?.tagName.toLowerCase() ?? 'none'}:${
                  active?.getAttribute('aria-label') ?? ''
                }`,
              };
            })())
            """,
            in: webView
        )
        let snapshot = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(snapshotJSONString.utf8)
            ) as? [String: String]
        )
        return RuntimeFocusSnapshot(
            documentFingerprint: try XCTUnwrap(
                snapshot["documentFingerprint"]
            ),
            activeOwner: try XCTUnwrap(snapshot["activeOwner"])
        )
    }

    private func makeOutputCommandMenu(
        target: RuntimeOutputCommandTarget
    ) -> NSMenu {
        let menu = NSMenu(title: "Inkbeam Test Main Menu")
        let documentItem = NSMenuItem(
            title: "Document",
            action: nil,
            keyEquivalent: ""
        )
        let documentMenu = NSMenu(title: "Document")
        documentMenu.autoenablesItems = false
        for definition in DocumentCommandDefinition.outputCommands {
            let item = NSMenuItem(
                title: definition.title,
                action: definition.action,
                keyEquivalent: definition.appKitKeyEquivalent
            )
            item.keyEquivalentModifierMask =
                definition.appKitModifiers
            item.target = target
            item.isEnabled = true
            documentMenu.addItem(item)
        }
        documentItem.submenu = documentMenu
        menu.addItem(documentItem)
        return menu
    }

    private func makeCompletedRuntimeTransfer() throws
        -> CompositeTransfer
    {
        let directory = temporaryDirectory.appendingPathComponent(
            "runtime-transfer-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        let transfer = try CompositeTransfer.begin(
            requestId: UUID(),
            expectedChunks: 1,
            directory: directory
        )
        try transfer.append(
            index: 0,
            base64: ProjectFixtures.pngData.base64EncodedString()
        )
        _ = try transfer.finish()
        return transfer
    }

    private func assertAppearance(
        _ colorScheme: EditorAppearanceColorScheme,
        expectedRootColor: String,
        in webView: WKWebView
    ) async throws {
        try await waitForJavaScriptPredicate(
            "\(colorScheme.rawValue) appearance applies its root token",
            predicate: """
            document.documentElement.dataset.colorScheme
              === '\(colorScheme.rawValue)'
              && getComputedStyle(document.documentElement).color
                === '\(expectedRootColor)'
            """,
            in: webView
        )
        let stateJSONString = try await evaluateString(
            """
            JSON.stringify({
              colorScheme: document.documentElement.dataset.colorScheme,
              rootColor: getComputedStyle(document.documentElement).color,
            })
            """,
            in: webView
        )
        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(stateJSONString.utf8)
            ) as? [String: String]
        )
        XCTAssertEqual(state["colorScheme"], colorScheme.rawValue)
        XCTAssertEqual(state["rootColor"], expectedRootColor)
    }

    private func assertSavedFeedback(in webView: WKWebView) async throws {
        let selector =
            "output.editor-feedback[role=\"status\"]"
            + "[aria-live=\"polite\"]"
        try await waitForJavaScriptPredicate(
            "one polite Saved status appears",
            predicate: """
            (() => {
              const nodes = document.querySelectorAll('\(selector)');
              return nodes.length === 1
                && nodes[0].textContent?.trim() === 'Saved';
            })()
            """,
            in: webView
        )
        let feedbackJSONString = try await evaluateString(
            """
            JSON.stringify((() => {
              const nodes = document.querySelectorAll('\(selector)');
              return {
                count: nodes.length,
                text: nodes[0]?.textContent?.trim() ?? '',
              };
            })())
            """,
            in: webView
        )
        let feedback = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(feedbackJSONString.utf8)
            ) as? [String: Any]
        )
        XCTAssertEqual(feedback["count"] as? Int, 1)
        XCTAssertEqual(feedback["text"] as? String, "Saved")
    }

    private func waitUntil(
        _ description: String,
        condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(description)")
        throw EditorWebViewRuntimeTestError.timedOut(description)
    }

    private func waitForJavaScriptPredicate(
        _ description: String,
        predicate: String,
        in webView: WKWebView
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            if try await evaluateBoolean(predicate, in: webView) {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(description)")
        throw EditorWebViewRuntimeTestError.timedOut(description)
    }

    private func windowPoint(
        clientX: Double,
        clientY: Double,
        in webView: WKWebView
    ) -> NSPoint {
        let localY = webView.bounds.height - clientY
        return webView.convert(
            NSPoint(x: clientX, y: localY),
            to: nil
        )
    }

    private func assertExternalResourcesAreBlocked(in webView: WKWebView) async throws {
        let resultJSONString = try await evaluateAsyncString(
            """
            (async () => {
              const policy = document.querySelector(
                'meta[http-equiv="Content-Security-Policy"]'
              )?.content;
              if (!policy) return JSON.stringify({ hasPolicy: false });
              const urls = {
                remoteFetch: 'https://example.com/inkbeam-csp-fetch',
                localFetch: 'http://localhost:65535/inkbeam-csp-fetch',
              };
              const observeFetch = (url) => new Promise((resolve) => {
                const controller = new AbortController();
                let rejected;
                let violation;
                let settled = false;
                const finishIfComplete = () => {
                  if (!settled && rejected === true && violation) {
                    settled = true;
                    clearTimeout(timeout);
                    document.removeEventListener('securitypolicyviolation', onViolation);
                    resolve({ url, rejected, violation, timedOut: false });
                  }
                };
                const onViolation = (event) => {
                  if (event.blockedURI !== url) return;
                  violation = {
                    blockedURI: event.blockedURI,
                    effectiveDirective: event.effectiveDirective,
                  };
                  finishIfComplete();
                };
                document.addEventListener('securitypolicyviolation', onViolation);
                fetch(url, { mode: 'no-cors', signal: controller.signal }).then(
                  () => {
                    rejected = false;
                  },
                  () => {
                    rejected = true;
                    finishIfComplete();
                  }
                );
                const timeout = setTimeout(() => {
                  if (settled) return;
                  settled = true;
                  document.removeEventListener('securitypolicyviolation', onViolation);
                  controller.abort();
                  resolve({
                    url,
                    rejected: rejected === true,
                    violation,
                    timedOut: true,
                  });
                }, 250);
              });
              const fetchResults = await Promise.all(
                [urls.remoteFetch, urls.localFetch].map(observeFetch)
              );
              return JSON.stringify({ hasPolicy: true, policy, urls, fetchResults });
            })()
            """,
            in: webView
        )
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultJSONString.utf8))
                as? [String: Any]
        )
        guard result["hasPolicy"] as? Bool == true else {
            return XCTFail("Bundled editor must install its CSP in the attached WKWebView")
        }
        let policy = try XCTUnwrap(result["policy"] as? String)
        let directives = Set(policy.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        XCTAssertEqual(directives, Set([
            "default-src 'none'",
            "connect-src 'none'",
            "object-src 'none'",
            "base-uri 'none'",
            "frame-src 'none'",
            "script-src 'self'",
            "style-src 'self'",
            "img-src 'self'",
        ]))
        XCTAssertFalse(policy.contains("http:"))
        XCTAssertFalse(policy.contains("https:"))
        XCTAssertFalse(policy.contains("localhost"))
        XCTAssertFalse(policy.contains("'unsafe-eval'"))
        let urls = try XCTUnwrap(result["urls"] as? [String: String])
        let fetchResults = try XCTUnwrap(result["fetchResults"] as? [[String: Any]])

        XCTAssertEqual(fetchResults.count, 2)
        for result in fetchResults {
            XCTAssertEqual(result["rejected"] as? Bool, true)
            XCTAssertEqual(result["timedOut"] as? Bool, false)
            let violation = try XCTUnwrap(result["violation"] as? [String: String])
            XCTAssertEqual(violation["blockedURI"], result["url"] as? String)
            XCTAssertEqual(violation["effectiveDirective"], "connect-src")
        }
        XCTAssertEqual(
            Set(fetchResults.compactMap { $0["url"] as? String }),
            Set([urls["remoteFetch"]!, urls["localFetch"]!])
        )
    }

    private func evaluateString(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result = result as? String {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "Inkbeam.EditorWebViewRuntimeTests",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "JavaScript did not return a string"]
                        )
                    )
                }
            }
        }
    }

    private func evaluateBoolean(
        _ script: String,
        in webView: WKWebView
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("Boolean(\(script))") { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result = result as? Bool {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "Inkbeam.EditorWebViewRuntimeTests",
                            code: 3,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "JavaScript did not return a Boolean",
                            ]
                        )
                    )
                }
            }
        }
    }

    private func evaluateAsyncString(
        _ script: String,
        in webView: WKWebView
    ) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            "return await (\(script));",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard let result = result as? String else {
            throw NSError(
                domain: "Inkbeam.EditorWebViewRuntimeTests",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Async JavaScript did not return a string",
                ]
            )
        }
        return result
    }

    private func validProject() throws -> InkbeamProject {
        let annotationJSON = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 3,
            "sourcePixelWidth": Self.runtimeSourcePixelWidth,
            "sourcePixelHeight": Self.runtimeSourcePixelHeight,
            "elements": [],
            "presentation": ["type": "none"],
            "defaults": [
                "color": "#1677FF",
                "strokeWidth": 4,
                "textSize": 24,
                "roughness": 1,
                "opacity": 1,
                "rectangleFillColor": NSNull(),
                "highlighterOpacity": 0.5,
            ],
        ])
        return InkbeamProject(
            manifest: ProjectManifest(
                formatVersion: ProjectManifest.currentFormatVersion,
                documentId: UUID(),
                createdAt: .now,
                updatedAt: .now,
                sourcePixelWidth: Self.runtimeSourcePixelWidth,
                sourcePixelHeight: Self.runtimeSourcePixelHeight,
                sourceKind: .screenRegion
            ),
            originalPNG: try runtimeSourcePNG(),
            annotationJSON: annotationJSON
        )
    }

    private func runtimeSourcePNG() throws -> Data {
        let width = Self.runtimeSourcePixelWidth
        let height = Self.runtimeSourcePixelHeight
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(
            red: 0.95,
            green: 0.93,
            blue: 0.88,
            alpha: 1
        ))
        context.fill(CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        ))
        context.setFillColor(CGColor(
            red: 0.18,
            green: 0.22,
            blue: 0.28,
            alpha: 1
        ))
        context.fill(CGRect(
            x: CGFloat(width) / 4,
            y: CGFloat(height) / 4,
            width: CGFloat(width) / 2,
            height: CGFloat(height) / 2
        ))

        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(
                domain: "Inkbeam.EditorWebViewRuntimeTests",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not finalize the deterministic runtime source PNG",
                ]
            )
        }
        return data as Data
    }

    private func attach(_ webView: WKWebView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

private enum EditorWebViewRuntimeTestError: Error {
    case timedOut(String)
}

private struct RuntimeFocusSnapshot: Equatable {
    let documentFingerprint: String
    let activeOwner: String
}

@MainActor
private final class RuntimeOutputCommandTarget: NSObject {
    weak var firstResponder: NSResponder?
    private(set) var invocationCount = 0
    private(set) var lastDispatchSucceeded = false

    @objc func copyComposite(_ sender: Any?) {
        dispatch(.copyImage)
    }

    @objc func saveProjectAction(_ sender: Any?) {
        dispatch(.saveProject)
    }

    @objc func exportComposite(_ sender: Any?) {
        dispatch(.exportPNG)
    }

    private func dispatch(
        _ definition: DocumentCommandDefinition
    ) {
        invocationCount += 1
        lastDispatchSucceeded =
            DocumentCommandDispatcher.perform(
                definition,
                startingAt: firstResponder
            )
    }
}

private enum RuntimeFocusOwner: String, CaseIterable {
    case inlineTextTextarea
    case shortcutHelpButton

    var expectedActiveOwner: String {
        switch self {
        case .inlineTextTextarea:
            "textarea:Edit annotation text"
        case .shortcutHelpButton:
            "button:Close keyboard shortcuts"
        }
    }
}

@MainActor
private enum RuntimeOutputShortcut: String, CaseIterable {
    case copy
    case save
    case export

    private var definition: DocumentCommandDefinition {
        switch self {
        case .copy:
            .copyImage
        case .save:
            .saveProject
        case .export:
            .exportPNG
        }
    }

    private var keyCode: UInt16 {
        switch self {
        case .copy:
            UInt16(kVK_ANSI_C)
        case .save:
            UInt16(kVK_ANSI_S)
        case .export:
            UInt16(kVK_ANSI_E)
        }
    }

    func makeKeyEvent(windowNumber: Int) throws -> NSEvent {
        let key = definition.appKitKeyEquivalent
        let characters = definition.appKitModifiers.contains(.shift)
            ? key.uppercased()
            : key
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: definition.appKitModifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    func didReachExpectedTerminal(
        annotationSnapshotCount: Int,
        compositeCount: Int,
        clipboardWriteCount: Int,
        exportDestinationCount: Int,
        hideCount: Int,
        saveCount: Int,
        statuses: [EditorOperationStatus]
    ) -> Bool {
        switch self {
        case .copy:
            compositeCount == 1
                && clipboardWriteCount == 1
                && hideCount == 1
        case .save:
            annotationSnapshotCount == 1
                && saveCount == 1
                && statuses.count == 2
        case .export:
            exportDestinationCount == 1
                && compositeCount == 1
                && statuses.count == 2
        }
    }

    func assertExactNativeSeams(
        annotationSnapshotCount: Int,
        compositeCount: Int,
        clipboardWriteCount: Int,
        exportDestinationCount: Int,
        hideCount: Int,
        saveCount: Int,
        statuses: [EditorOperationStatus],
        exportURL: URL
    ) {
        switch self {
        case .copy:
            XCTAssertEqual(annotationSnapshotCount, 0)
            XCTAssertEqual(compositeCount, 1)
            XCTAssertEqual(clipboardWriteCount, 1)
            XCTAssertEqual(exportDestinationCount, 0)
            XCTAssertEqual(hideCount, 1)
            XCTAssertEqual(saveCount, 0)
            XCTAssertTrue(statuses.isEmpty)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: exportURL.path)
            )
        case .save:
            XCTAssertEqual(annotationSnapshotCount, 1)
            XCTAssertEqual(compositeCount, 0)
            XCTAssertEqual(clipboardWriteCount, 0)
            XCTAssertEqual(exportDestinationCount, 0)
            XCTAssertEqual(hideCount, 0)
            XCTAssertEqual(saveCount, 1)
            XCTAssertEqual(
                statuses,
                [.started(.save), .saveCompleted]
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: exportURL.path)
            )
        case .export:
            XCTAssertEqual(annotationSnapshotCount, 0)
            XCTAssertEqual(compositeCount, 1)
            XCTAssertEqual(clipboardWriteCount, 0)
            XCTAssertEqual(exportDestinationCount, 1)
            XCTAssertEqual(hideCount, 0)
            XCTAssertEqual(saveCount, 0)
            XCTAssertEqual(
                statuses,
                [
                    .started(.export),
                    .exportCompleted(
                        displayName: exportURL.lastPathComponent
                    ),
                ]
            )
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: exportURL.path)
            )
        }
    }
}

private final class RuntimeProjectStoreSpy:
    ProjectPackageStoring,
    @unchecked Sendable
{
    private(set) var saveCount = 0

    func load(from url: URL) throws -> InkbeamProject {
        throw RuntimeProjectStoreSpyError.unexpectedLoad
    }

    func save(_ project: InkbeamProject, to url: URL) throws {
        saveCount += 1
    }
}

private enum RuntimeProjectStoreSpyError: Error {
    case unexpectedLoad
}
