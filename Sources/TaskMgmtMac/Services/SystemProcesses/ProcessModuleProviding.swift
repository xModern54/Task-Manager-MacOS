import Foundation

protocol ProcessModuleProviding: Sendable {
    func modules(for pid: Int, executablePath: String?) -> [ProcessModuleInfo]
}
