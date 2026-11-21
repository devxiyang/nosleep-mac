import Darwin
import SystemConfiguration

enum ConsoleUser {
    static func isActive(_ user: uid_t) -> Bool {
        var uid: uid_t = 0
        let name = SCDynamicStoreCopyConsoleUser(nil, &uid, nil) as String?
        return name != nil && name != "loginwindow" && uid != 0 && user == uid
    }
}
