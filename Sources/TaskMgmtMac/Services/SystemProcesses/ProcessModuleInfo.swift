import Foundation

struct ProcessModuleInfo: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let kind: ProcessModuleKind
    let mappedBytes: UInt64
    let residentBytes: UInt64
    let privateResidentBytes: UInt64
    let sharedResidentBytes: UInt64
    let diskBytes: UInt64?
    let regionCount: Int
    let protectionSummary: String

    var id: String { path }
}

enum ProcessModuleKind: String, Hashable, Sendable {
    case executable = "Executable"
    case dynamicLibrary = "Dynamic library"
    case framework = "Framework"
    case bundle = "Bundle"
    case mappedFile = "Mapped file"
}
