import Foundation
@testable import Inkbeam

enum CaptureFixtures {
    static let retinaDisplay = DisplayDescriptor(
        displayID: 1,
        frameInAppKitPoints: CGRect(x: 0, y: 0, width: 1512, height: 982),
        scale: 2,
        pixelSize: CGSize(width: 3024, height: 1964)
    )

    static let leftDisplay = DisplayDescriptor(
        displayID: 2,
        frameInAppKitPoints: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        scale: 1,
        pixelSize: CGSize(width: 1920, height: 1080)
    )

    static let selection = RegionSelection(
        display: leftDisplay,
        rectInDisplayPoints: CGRect(x: 100, y: 100, width: 500, height: 400)
    )

    static let retinaSelection = RegionSelection(
        display: retinaDisplay,
        rectInDisplayPoints: CGRect(x: 100, y: 80, width: 300, height: 200)
    )
}
