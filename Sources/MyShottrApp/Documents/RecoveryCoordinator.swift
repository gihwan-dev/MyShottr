import AppKit
import Foundation

enum RecoveryPromptDecision: Equatable {
    case restore([UUID])
    case discardAll
    case cancel
}

@MainActor
protocol RecoveryPrompting {
    func present(
        projects: [RecoveredProject]
    ) -> RecoveryPromptDecision
}

enum RecoveryCoordinatorError: Error, Equatable {
    case invalidSelection(UUID)
    case restoreFailed(UUID)
}

@MainActor
final class RecoveryCoordinator {
    typealias Restore = (RecoveredProject) throws -> Void

    private let recoveryStore: any RecoveryStoring
    private let previousSessionWasClean: Bool
    private let prompt: any RecoveryPrompting
    private let restore: Restore
    private var cachedProjects: [RecoveredProject]?
    private var didOfferRecovery = false

    init(
        recoveryStore: any RecoveryStoring,
        previousSessionWasClean: Bool,
        prompt: any RecoveryPrompting,
        restore: @escaping Restore
    ) {
        self.recoveryStore = recoveryStore
        self.previousSessionWasClean = previousSessionWasClean
        self.prompt = prompt
        self.restore = restore
    }

    func shouldOfferRecovery() throws -> Bool {
        guard !previousSessionWasClean,
              !didOfferRecovery
        else {
            return false
        }
        if let cachedProjects {
            return !cachedProjects.isEmpty
        }
        let projects = try recoveryStore.recoverableProjects()
        cachedProjects = projects
        return !projects.isEmpty
    }

    func offerRecoveryIfNeeded() throws {
        guard try shouldOfferRecovery() else {
            return
        }
        guard let projects = cachedProjects else {
            return
        }
        didOfferRecovery = true

        switch prompt.present(projects: projects) {
        case .restore(let selectedDocumentIDs):
            let selected = Set(selectedDocumentIDs)
            guard selected.isSubset(
                of: Set(projects.map(\.documentId))
            ) else {
                let invalid = selected.subtracting(
                    projects.map(\.documentId)
                )
                throw RecoveryCoordinatorError.invalidSelection(
                    invalid.sorted {
                        $0.uuidString < $1.uuidString
                    }[0]
                )
            }
            for project in projects
            where selected.contains(project.documentId) {
                do {
                    try restore(project)
                } catch {
                    throw RecoveryCoordinatorError.restoreFailed(
                        project.documentId
                    )
                }
            }
        case .discardAll:
            for project in projects {
                try recoveryStore.remove(
                    documentId: project.documentId
                )
            }
        case .cancel:
            break
        }
    }
}

@MainActor
final class RecoveryAlertPrompt: RecoveryPrompting {
    func present(
        projects: [RecoveredProject]
    ) -> RecoveryPromptDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Recover unsaved MyShottr documents?"
        alert.informativeText =
            "MyShottr did not exit normally. Select the documents to restore. Nothing is opened or deleted until you choose an action."

        let buttons = projects.map { project in
            let button = NSButton(
                checkboxWithTitle: label(for: project),
                target: nil,
                action: nil
            )
            button.state = .on
            button.identifier = NSUserInterfaceItemIdentifier(
                project.documentId.uuidString
            )
            return button
        }
        let stack = NSStackView(views: buttons)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(
            x: 0,
            y: 0,
            width: 520,
            height: max(
                30,
                CGFloat(buttons.count) * 28
            )
        )
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 540, height: 180)
        )
        scrollView.documentView = stack
        scrollView.hasVerticalScroller = buttons.count > 6
        scrollView.drawsBackground = false
        alert.accessoryView = scrollView

        alert.addButton(withTitle: "Restore Selected")
        alert.addButton(withTitle: "Discard All")
        alert.addButton(withTitle: "Not Now")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let selected = buttons.compactMap { button -> UUID? in
                guard button.state == .on,
                      let identifier = button.identifier?.rawValue
                else {
                    return nil
                }
                return UUID(uuidString: identifier)
            }
            return .restore(selected)
        case .alertSecondButtonReturn:
            return .discardAll
        default:
            return .cancel
        }
    }

    private func label(for project: RecoveredProject) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return "\(project.documentId.uuidString) — \(formatter.string(from: project.modifiedAt))"
    }
}
