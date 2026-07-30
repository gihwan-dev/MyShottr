import Foundation

let runner = NativeHostRuntime.makeRunner()
runner.run(input: .standardInput, output: .standardOutput)
