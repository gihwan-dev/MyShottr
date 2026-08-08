import Dispatch
import Foundation

Task {
    let runner = NativeHostRuntime.makeRunner()
    await runner.run(input: .standardInput, output: .standardOutput)
    exit(EXIT_SUCCESS)
}
dispatchMain()
