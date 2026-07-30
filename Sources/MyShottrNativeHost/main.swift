import Foundation

let runner = HostRunner(
    staging: HostInboxStore(),
    activator: AppActivator()
)
runner.run(input: .standardInput, output: .standardOutput)
