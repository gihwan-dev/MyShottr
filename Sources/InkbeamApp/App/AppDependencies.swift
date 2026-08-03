import Foundation

@MainActor
struct AppDependencies {
    let selector: any RegionSelecting
    let capturer: any ScreenCapturing
    let projectFactory: any NewProjectCreating
    let projectStore: any ProjectPackageStoring

    init(
        selector: any RegionSelecting = RegionSelectionController(),
        capturer: any ScreenCapturing = ScreenCaptureClient(),
        projectFactory: any NewProjectCreating = NewProjectFactory(),
        projectStore: any ProjectPackageStoring = ProjectPackageStore()
    ) {
        self.selector = selector
        self.capturer = capturer
        self.projectFactory = projectFactory
        self.projectStore = projectStore
    }

    func makeCaptureCoordinator(
        windows: any DocumentWindowPresenting
    ) -> RegionCaptureCoordinator {
        RegionCaptureCoordinator(
            selector: selector,
            capturer: capturer,
            projectFactory: projectFactory,
            windows: windows
        )
    }
}
