import Foundation

struct DisplayDescriptor: Equatable, Sendable {
    let displayID: UInt32
    let frameInAppKitPoints: CGRect
    let scale: CGFloat
    let pixelSize: CGSize
}

struct RegionSelection: Equatable, Sendable {
    let display: DisplayDescriptor
    let rectInDisplayPoints: CGRect
}
