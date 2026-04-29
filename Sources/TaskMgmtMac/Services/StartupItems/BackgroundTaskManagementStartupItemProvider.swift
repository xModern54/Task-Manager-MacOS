import Darwin
import Foundation

struct BackgroundTaskManagementStartupItemProvider: StartupItemProviding {
    func startupItems() async -> [StartupItem] {
        await Task.detached(priority: .utility) {
            readBackgroundTaskManagementItems()
        }.value
    }
}

private func readBackgroundTaskManagementItems() -> [StartupItem] {
    let result = runSFLToolDump()
    guard result.status == 0 else { return [] }

    let records = parseBTMRecords(result.output)
    return makeStartupItems(from: records)
}

private func runSFLToolDump() -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sfltool")
    process.arguments = ["dumpbtm"]

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    } catch {
        return (1, "")
    }
}

private struct BTMRecord: Hashable {
    var uid: Int?
    var uuid: String?
    var name: String?
    var developerName: String?
    var teamIdentifier: String?
    var type: String?
    var flags: Set<String> = []
    var disposition: Set<String> = []
    var identifier: String?
    var url: String?
    var executablePath: String?
    var bundleIdentifier: String?
    var parentIdentifier: String?
    var embeddedItemIdentifiers: [String] = []
    var associatedBundleIdentifiers: [String] = []
}

private func parseBTMRecords(_ output: String) -> [BTMRecord] {
    var records: [BTMRecord] = []
    var currentUID: Int?
    var currentRecord: BTMRecord?
    var isReadingEmbeddedIdentifiers = false

    func finishRecord() {
        if let currentRecord {
            records.append(currentRecord)
        }
        currentRecord = nil
        isReadingEmbeddedIdentifiers = false
    }

    for line in output.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }

        if let uid = parseUID(from: trimmed) {
            finishRecord()
            currentUID = uid
            continue
        }

        if trimmed.hasPrefix("#"), trimmed.hasSuffix(":") {
            finishRecord()
            currentRecord = BTMRecord(uid: currentUID)
            continue
        }

        if trimmed == "Embedded Item Identifiers:" {
            isReadingEmbeddedIdentifiers = true
            continue
        }

        if isReadingEmbeddedIdentifiers, let identifier = parseNumberedValue(trimmed) {
            currentRecord?.embeddedItemIdentifiers.append(identifier)
            continue
        }

        isReadingEmbeddedIdentifiers = false

        guard let separatorIndex = trimmed.firstIndex(of: ":") else {
            continue
        }

        let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
        let rawValue = String(trimmed[trimmed.index(after: separatorIndex)...])
            .trimmingCharacters(in: .whitespaces)

        switch key {
        case "UUID":
            currentRecord?.uuid = nilIfNull(rawValue)
        case "Name":
            currentRecord?.name = nilIfNull(rawValue)
        case "Developer Name":
            currentRecord?.developerName = nilIfNull(rawValue)
        case "Team Identifier":
            currentRecord?.teamIdentifier = nilIfNull(rawValue)
        case "Type":
            currentRecord?.type = parseLeadingValue(rawValue)
        case "Flags":
            currentRecord?.flags = parseBracketedList(rawValue)
        case "Disposition":
            currentRecord?.disposition = parseBracketedList(rawValue)
        case "Identifier":
            currentRecord?.identifier = nilIfNull(rawValue)
        case "URL":
            currentRecord?.url = nilIfNull(rawValue)
        case "Executable Path":
            currentRecord?.executablePath = nilIfNull(rawValue)
        case "Bundle Identifier":
            currentRecord?.bundleIdentifier = nilIfNull(rawValue)
        case "Parent Identifier":
            currentRecord?.parentIdentifier = nilIfNull(rawValue)
        case "Assoc. Bundle IDs":
            currentRecord?.associatedBundleIdentifiers = Array(parseBracketedList(rawValue))
        default:
            continue
        }
    }

    finishRecord()
    return records
}

private func parseUID(from line: String) -> Int? {
    guard line.hasPrefix("Records for UID ") else { return nil }
    let remainder = line.dropFirst("Records for UID ".count)
    let uidText = remainder.prefix { character in
        character == "-" || character.isNumber
    }
    return Int(uidText)
}

private func parseNumberedValue(_ line: String) -> String? {
    guard line.hasPrefix("#"),
          let separatorIndex = line.firstIndex(of: ":") else {
        return nil
    }

    let value = String(line[line.index(after: separatorIndex)...])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return nilIfNull(value)
}

private func parseLeadingValue(_ value: String) -> String {
    if let range = value.range(of: " (") {
        return String(value[..<range.lowerBound])
    }

    return value
}

private func parseBracketedList(_ value: String) -> Set<String> {
    guard let start = value.firstIndex(of: "["),
          let end = value[start...].firstIndex(of: "]") else {
        return []
    }

    let rawItems = value[value.index(after: start)..<end]
    return Set(rawItems
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty })
}

private func nilIfNull(_ value: String) -> String? {
    value == "(null)" || value.isEmpty ? nil : value
}

private func makeStartupItems(from records: [BTMRecord]) -> [StartupItem] {
    let filteredRecords = filterUserVisibleRecords(records)
    let recordsByIdentifier = recordsByIdentifier(filteredRecords)
    let childRecordsByParent = Dictionary(grouping: filteredRecords) { record in
        record.parentIdentifier ?? ""
    }
    let parentIdentifiers = displayParentIdentifiers(in: filteredRecords)

    let displayRecords = filteredRecords.filter { record in
        guard let identifier = record.identifier else { return false }

        if parentIdentifiers.contains(identifier) {
            return true
        }

        if let parentIdentifier = record.parentIdentifier,
           parentIdentifiers.contains(parentIdentifier) {
            return false
        }

        return isConcreteBackgroundRecord(record)
    }

    return displayRecords
        .compactMap { record in
            makeStartupItem(
                for: record,
                children: childRecordsByParent[record.identifier ?? ""] ?? [],
                recordsByIdentifier: recordsByIdentifier
            )
        }
        .uniqueByID()
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
}

private func recordsByIdentifier(_ records: [BTMRecord]) -> [String: BTMRecord] {
    var result: [String: BTMRecord] = [:]

    for record in records {
        guard let identifier = record.identifier else { continue }
        result[identifier] = result[identifier] ?? record
    }

    return result
}

private func filterUserVisibleRecords(_ records: [BTMRecord]) -> [BTMRecord] {
    let visibleUIDs = Set([-2, consoleUserUID() ?? Int(getuid())])
    return records.filter { record in
        guard let uid = record.uid else { return true }
        return visibleUIDs.contains(uid)
    }
}

private func consoleUserUID() -> Int? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: "/dev/console"),
          let ownerID = attributes[.ownerAccountID] as? NSNumber else {
        return nil
    }

    let uid = ownerID.intValue
    return uid == 0 ? nil : uid
}

private func displayParentIdentifiers(in records: [BTMRecord]) -> Set<String> {
    let childRecordsByParent = Dictionary(grouping: records) { record in
        record.parentIdentifier ?? ""
    }

    return Set(records.compactMap { record in
        guard let identifier = record.identifier,
              isDisplayParent(record),
              childRecordsByParent[identifier]?.isEmpty == false else {
            return nil
        }

        return identifier
    })
}

private func isDisplayParent(_ record: BTMRecord) -> Bool {
    guard let type = record.type else { return false }

    if record.identifier == "Unknown Developer" {
        return false
    }

    return type == "app" || type == "developer"
}

private func isConcreteBackgroundRecord(_ record: BTMRecord) -> Bool {
    guard let type = record.type else { return false }

    if type == "developer", record.name == nil {
        return false
    }

    return true
}

private func makeStartupItem(
    for record: BTMRecord,
    children: [BTMRecord],
    recordsByIdentifier: [String: BTMRecord]
) -> StartupItem? {
    let groupRecords = ([record] + children).filter { isConcreteBackgroundRecord($0) }
    guard !groupRecords.isEmpty else { return nil }

    let name = displayName(for: record)
    let itemCount = max(children.count, concreteItemCount(for: record, recordsByIdentifier: recordsByIdentifier))
    let affectsAllUsers = groupRecords.contains { $0.uid == -2 || $0.type == "legacy daemon" }
    let path = displayPath(for: record, children: children)
    let publisher = displayPublisher(for: record, children: children)
    let source = source(for: record)
    let targets = controlTargets(for: groupRecords)

    return StartupItem(
        id: record.identifier ?? record.uuid ?? "\(StartupItemSource.backgroundItem.rawValue)-\(name)",
        name: name,
        publisher: publisher,
        status: status(for: groupRecords),
        impact: .notMeasured,
        source: source,
        path: path,
        detail: detailText(itemCount: itemCount, source: source, affectsAllUsers: affectsAllUsers, path: path),
        isHidden: false,
        controlTargets: targets,
        properties: properties(for: record, children: children, targets: targets)
    )
}

private func displayName(for record: BTMRecord) -> String {
    if let name = record.name, !name.isEmpty {
        return name
    }

    if let executablePath = record.executablePath {
        return URL(fileURLWithPath: executablePath).lastPathComponent
    }

    if let urlPath = filePath(from: record.url) {
        return URL(fileURLWithPath: urlPath).deletingPathExtension().lastPathComponent
    }

    if let bundleIdentifier = record.bundleIdentifier {
        return bundleIdentifier
    }

    return record.identifier ?? "Background item"
}

private func displayPath(for record: BTMRecord, children: [BTMRecord]) -> String? {
    if let path = filePath(from: record.url), FileManager.default.fileExists(atPath: path) {
        return path
    }

    if let executablePath = record.executablePath, FileManager.default.fileExists(atPath: executablePath) {
        return executablePath
    }

    for child in children {
        if let path = filePath(from: child.url), FileManager.default.fileExists(atPath: path) {
            return path
        }

        if let executablePath = child.executablePath, FileManager.default.fileExists(atPath: executablePath) {
            return executablePath
        }
    }

    return nil
}

private func displayPublisher(for record: BTMRecord, children: [BTMRecord]) -> String {
    let candidates = [record] + children

    for candidate in candidates {
        if let developerName = candidate.developerName, !developerName.isEmpty {
            return developerName
        }
    }

    for candidate in candidates {
        if let teamIdentifier = candidate.teamIdentifier, !teamIdentifier.isEmpty {
            return candidate.bundleIdentifier.map { "\($0) · \(teamIdentifier)" } ?? teamIdentifier
        }
    }

    for candidate in candidates {
        if let bundleIdentifier = candidate.bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }
    }

    return "Unknown"
}

private func status(for records: [BTMRecord]) -> StartupItemStatus {
    if records.contains(where: { $0.disposition.contains("enabled") && $0.disposition.contains("allowed") }) {
        return .enabled
    }

    if records.contains(where: { $0.disposition.contains("disabled") || $0.disposition.contains("disallowed") }) {
        return .disabled
    }

    return .unknown
}

private func source(for record: BTMRecord) -> StartupItemSource {
    switch record.type {
    case "legacy agent", "agent":
        return .launchAgent
    case "legacy daemon", "daemon":
        return .launchDaemon
    case "login item":
        return .loginItem
    default:
        return .backgroundItem
    }
}

private func controlTargets(for records: [BTMRecord]) -> [StartupItemControlTarget] {
    var seenIDs: Set<String> = []
    var targets: [StartupItemControlTarget] = []

    for record in records {
        guard isLaunchdControllable(record),
              let label = launchdLabel(for: record) else {
            continue
        }

        let domain = launchdDomain(for: record)
        let plistPath = plistPath(for: record)
        let executablePath = absoluteExecutablePath(for: record)
        let target = StartupItemControlTarget(
            label: label,
            domain: domain,
            plistPath: plistPath,
            executablePath: executablePath
        )

        guard seenIDs.insert(target.id).inserted else { continue }
        targets.append(target)
    }

    return targets
}

private func isLaunchdControllable(_ record: BTMRecord) -> Bool {
    switch record.type {
    case "legacy agent", "agent", "legacy daemon", "daemon", "login item":
        return true
    default:
        return false
    }
}

private func launchdLabel(for record: BTMRecord) -> String? {
    if let plistPath = plistPath(for: record),
       let label = plistLabel(at: plistPath) {
        return label
    }

    guard let identifier = record.identifier else { return nil }

    if let dotIndex = identifier.firstIndex(of: "."),
       identifier[..<dotIndex].allSatisfy(\.isNumber) {
        return String(identifier[identifier.index(after: dotIndex)...])
    }

    return identifier
}

private func plistLabel(at path: String) -> String? {
    guard let dictionary = NSDictionary(contentsOfFile: path),
          let label = dictionary["Label"] as? String,
          !label.isEmpty else {
        return nil
    }

    return label
}

private func launchdDomain(for record: BTMRecord) -> String {
    if record.uid == -2 || record.type == "legacy daemon" || record.type == "daemon" {
        return "system"
    }

    let uid = record.uid.flatMap { $0 >= 0 ? $0 : nil } ?? consoleUserUID() ?? Int(getuid())
    return "gui/\(uid)"
}

private func plistPath(for record: BTMRecord) -> String? {
    guard let path = filePath(from: record.url), path.hasSuffix(".plist") else {
        return nil
    }

    return path
}

private func absoluteExecutablePath(for record: BTMRecord) -> String? {
    guard let executablePath = record.executablePath,
          executablePath.hasPrefix("/") else {
        return nil
    }

    return executablePath
}

private func properties(
    for record: BTMRecord,
    children: [BTMRecord],
    targets: [StartupItemControlTarget]
) -> [StartupItemProperty] {
    var properties: [StartupItemProperty] = []

    appendProperty("name", "Name", displayName(for: record), to: &properties)
    appendProperty("publisher", "Publisher", displayPublisher(for: record, children: children), to: &properties)
    appendProperty("status", "Status", status(for: ([record] + children).filter { isConcreteBackgroundRecord($0) }).rawValue, to: &properties)
    appendProperty("source", "Source", source(for: record).rawValue, to: &properties)
    appendProperty("uuid", "UUID", record.uuid, to: &properties)
    appendProperty("identifier", "Identifier", record.identifier, to: &properties)
    appendProperty("parentIdentifier", "Parent identifier", record.parentIdentifier, to: &properties)
    appendProperty("bundleIdentifier", "Bundle identifier", record.bundleIdentifier, to: &properties)
    appendProperty("teamIdentifier", "Team identifier", record.teamIdentifier, to: &properties)
    appendProperty("type", "BTM type", record.type, to: &properties)
    appendProperty("flags", "BTM flags", record.flags.sorted().joined(separator: ", "), to: &properties)
    appendProperty("disposition", "BTM disposition", record.disposition.sorted().joined(separator: ", "), to: &properties)
    appendProperty("url", "URL", record.url, to: &properties)
    appendProperty("executablePath", "Executable path", record.executablePath, to: &properties)

    let childIdentifiers = children.compactMap(\.identifier).joined(separator: ", ")
    appendProperty("children", "Child items", childIdentifiers, to: &properties)
    appendProperty("embeddedItems", "Embedded items", record.embeddedItemIdentifiers.joined(separator: ", "), to: &properties)
    appendProperty("associatedBundles", "Associated bundles", record.associatedBundleIdentifiers.joined(separator: ", "), to: &properties)

    let targetText = targets.map(\.id).joined(separator: ", ")
    appendProperty("launchdTargets", "Launchd targets", targetText, to: &properties)

    for target in targets {
        appendProperty("target-\(target.id)-plist", "Plist for \(target.label)", target.plistPath, to: &properties)
        appendProperty("target-\(target.id)-executable", "Executable for \(target.label)", target.executablePath, to: &properties)
    }

    return properties
}

private func appendProperty(
    _ id: String,
    _ name: String,
    _ value: String?,
    to properties: inout [StartupItemProperty]
) {
    guard let value, !value.isEmpty else { return }
    properties.append(StartupItemProperty(id: id, name: name, value: value))
}

private func concreteItemCount(for record: BTMRecord, recordsByIdentifier: [String: BTMRecord]) -> Int {
    let embeddedCount = record.embeddedItemIdentifiers
        .compactMap { recordsByIdentifier[$0] }
        .filter { isConcreteBackgroundRecord($0) }
        .count

    return max(embeddedCount, isDisplayParent(record) ? 0 : 1)
}

private func detailText(itemCount: Int, source: StartupItemSource, affectsAllUsers: Bool, path: String?) -> String {
    let countText: String

    if itemCount > 0 {
        countText = itemCount == 1 ? "1 item" : "\(itemCount) items"
    } else {
        countText = source.rawValue
    }

    if affectsAllUsers {
        return "\(countText): affects all users"
    }

    if let path {
        return path
    }

    return countText
}

private func filePath(from urlValue: String?) -> String? {
    guard let urlValue else { return nil }

    if urlValue.hasPrefix("file://"), let url = URL(string: urlValue) {
        return url.path
    }

    if urlValue.hasPrefix("/") {
        return urlValue
    }

    return nil
}

private extension Array where Element == StartupItem {
    func uniqueByID() -> [StartupItem] {
        var seenIDs: Set<String> = []
        var items: [StartupItem] = []

        for item in self where seenIDs.insert(item.id).inserted {
            items.append(item)
        }

        return items
    }
}
