import Foundation

enum EditorNavigationDecision: Equatable, Sendable {
    case allow
    case cancel
}

struct EditorNavigationPolicy: Sendable {
    private enum ResourceKind {
        case mainDocument
        case bundledAsset
        case documentPNG
    }

    private static let scheme = "myshottr-editor"
    private static let host = "editor"

    private let allowedAssetPaths: Set<String>

    init(editorBundleRootURL: URL) {
        allowedAssetPaths = Self.referencedAssetPaths(
            in: editorBundleRootURL.standardizedFileURL
        )
    }

    func decision(for url: URL) -> EditorNavigationDecision {
        resourceKind(for: url) == nil ? .cancel : .allow
    }

    func navigationDecision(
        for url: URL?,
        hasTargetFrame: Bool,
        isMainFrame: Bool,
        shouldPerformDownload: Bool
    ) -> EditorNavigationDecision {
        guard hasTargetFrame,
              isMainFrame,
              !shouldPerformDownload,
              let url,
              resourceKind(for: url) == .mainDocument
        else {
            return .cancel
        }
        return .allow
    }

    func responseDecision(
        for url: URL?,
        isForMainFrame: Bool,
        canShowMIMEType: Bool
    ) -> EditorNavigationDecision {
        guard isForMainFrame,
              canShowMIMEType,
              let url,
              resourceKind(for: url) == .mainDocument
        else {
            return .cancel
        }
        return .allow
    }

    private func resourceKind(for url: URL) -> ResourceKind? {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        components.scheme == Self.scheme,
        components.host == Self.host,
        components.port == nil,
        components.user == nil,
        components.password == nil,
        components.query == nil,
        components.fragment == nil,
        let decodedPath = components.percentEncodedPath.removingPercentEncoding,
        isCanonical(path: decodedPath)
        else {
            return nil
        }

        let encodedPath = components.percentEncodedPath
        if encodedPath == "/index.html" {
            return .mainDocument
        }
        if allowedAssetPaths.contains(decodedPath),
           encodedPath.hasPrefix("/assets/")
        {
            return .bundledAsset
        }
        if let documentID = documentID(in: url),
           encodedPath
            == "/document/\(documentID.uuidString)/original.png"
        {
            return .documentPNG
        }
        return nil
    }

    private func isCanonical(path: String) -> Bool {
        guard path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0"),
              !path.contains("//"),
              (path as NSString).standardizingPath == path
        else {
            return false
        }
        return true
    }

    private func documentID(in url: URL) -> UUID? {
        let components = url.pathComponents
        guard components.count == 4,
              components[0] == "/",
              components[1] == "document",
              components[3] == "original.png"
        else {
            return nil
        }
        return UUID(uuidString: components[2])
    }

    private static func referencedAssetPaths(
        in rootURL: URL
    ) -> Set<String> {
        let indexURL = rootURL.appendingPathComponent(
            "index.html",
            isDirectory: false
        )
        guard let index = try? String(
            contentsOf: indexURL,
            encoding: .utf8
        ) else {
            return []
        }
        let pattern = #"\./assets/(index-[A-Za-z0-9_-]+\.(?:js|css))"#
        let range = NSRange(index.startIndex..., in: index)
        guard let expression = try? NSRegularExpression(pattern: pattern)
        else {
            return []
        }
        return Set(expression.matches(in: index, range: range).compactMap {
            guard let filenameRange = Range($0.range(at: 1), in: index)
            else {
                return nil
            }
            return "/assets/\(index[filenameRange])"
        })
    }
}
