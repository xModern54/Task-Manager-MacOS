import Foundation

public enum PrivilegedHelperConstants {
    public static let daemonLabel = "com.xmodern.TaskMgmtMac.PrivilegedHelper"
    public static let daemonPlistName = "com.xmodern.TaskMgmtMac.PrivilegedHelper.plist"
    public static let machServiceName = "com.xmodern.TaskMgmtMac.PrivilegedHelper"
    public static let mainApplicationIdentifier = "com.xmodern.TaskMgmtMac"
    public static let legacySudoersRulePath = "/etc/sudoers.d/taskmgmtmac-root-launch"
}

@objc public protocol PrivilegedHelperXPCProtocol {
    func helperVersion(reply: @escaping (String) -> Void)
    func collectPowerMetrics(reply: @escaping (String?, String?) -> Void)
    func terminateProcess(_ pid: Int32, reply: @escaping (Bool, String?) -> Void)
    func setLaunchItemEnabled(_ enabled: Bool, target: String, reply: @escaping (Bool, String?) -> Void)
    func removeLegacyRootLaunchRule(reply: @escaping (Bool, String?) -> Void)
}
