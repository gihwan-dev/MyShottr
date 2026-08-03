import Foundation
@testable import Inkbeam

@MainActor
final class FakeRegionSelector: RegionSelecting {
    var result: RegionSelectionOutcome
    private(set) var selectionCount = 0

    init(result: RegionSelectionOutcome) {
        self.result = result
    }

    func selectRegion() async throws -> RegionSelectionOutcome {
        selectionCount += 1
        return result
    }

    func cancel() {}
}

actor CaptureInvocationRecorder {
    private(set) var selections: [RegionSelection] = []

    func record(_ selection: RegionSelection) {
        selections.append(selection)
    }
}

struct FakeScreenCapturer: ScreenCapturing {
    let result: CaptureArtifact
    let recorder: CaptureInvocationRecorder?

    init(
        result: CaptureArtifact,
        recorder: CaptureInvocationRecorder? = nil
    ) {
        self.result = result
        self.recorder = recorder
    }

    func capture(selection: RegionSelection) async throws -> CaptureArtifact {
        await recorder?.record(selection)
        return result
    }
}

struct StubNewProjectFactory: NewProjectCreating {
    func make(
        artifact: CaptureArtifact,
        now: Date
    ) throws -> InkbeamProject {
        try NewProjectFactory(
            preferences: StubPreferences(.approvedDefaults)
        ).make(
            artifact: artifact,
            now: now
        )
    }
}

@MainActor
final class SpyDocumentWindowPresenter: DocumentWindowPresenting {
    var presentationError: (any Error)?
    var suspendsPresentation = false
    private(set) var presentedProjects: [InkbeamProject] = []
    private(set) var presentationAttempts: [InkbeamProject] = []
    private var presentationContinuations: [
        CheckedContinuation<Void, Never>
    ] = []
    private var startedContinuations: [
        CheckedContinuation<Void, Never>
    ] = []

    func present(
        project: InkbeamProject
    ) async throws {
        presentationAttempts.append(project)
        let waiting = startedContinuations
        startedContinuations.removeAll()
        waiting.forEach { $0.resume() }
        if suspendsPresentation {
            await withCheckedContinuation {
                presentationContinuations.append($0)
            }
        }
        if let presentationError {
            throw presentationError
        }
        presentedProjects.append(project)
    }

    func waitUntilPresentationStarts() async {
        guard presentationAttempts.isEmpty else {
            return
        }
        await withCheckedContinuation {
            startedContinuations.append($0)
        }
    }

    func resumePresentation() {
        suspendsPresentation = false
        let continuations = presentationContinuations
        presentationContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
final class SuspendingRegionSelector: RegionSelecting {
    private(set) var selectionCount = 0
    private var selectionContinuation:
        CheckedContinuation<RegionSelectionOutcome, any Error>?
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []

    func selectRegion() async throws -> RegionSelectionOutcome {
        selectionCount += 1
        let waiting = startedContinuations
        startedContinuations.removeAll()
        waiting.forEach { $0.resume() }

        return try await withCheckedThrowingContinuation { continuation in
            selectionContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard selectionCount == 0 else {
            return
        }

        await withCheckedContinuation { continuation in
            startedContinuations.append(continuation)
        }
    }

    func finish(with outcome: RegionSelectionOutcome) {
        selectionContinuation?.resume(returning: outcome)
        selectionContinuation = nil
    }

    func cancel() {
        finish(with: .cancelled)
    }
}

enum CapturePipelineTestError: Error, Equatable {
    case selection
    case capture
    case projectCreation
    case presentation
}

@MainActor
final class ThrowingRegionSelector: RegionSelecting {
    private(set) var selectionCount = 0

    func selectRegion() async throws -> RegionSelectionOutcome {
        selectionCount += 1
        throw CapturePipelineTestError.selection
    }

    func cancel() {}
}

struct ThrowingScreenCapturer: ScreenCapturing {
    let error: CapturePipelineTestError
    let recorder: CaptureInvocationRecorder

    func capture(selection: RegionSelection) async throws -> CaptureArtifact {
        await recorder.record(selection)
        throw error
    }
}

struct ThrowingNewProjectFactory: NewProjectCreating {
    let error: CapturePipelineTestError

    func make(
        artifact: CaptureArtifact,
        now: Date
    ) throws -> InkbeamProject {
        throw error
    }
}
