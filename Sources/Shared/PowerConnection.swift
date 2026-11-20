import Foundation
import Security

typealias ModeReply = @Sendable (String) -> Void

@objc protocol PowerServiceProtocol {
    func setMode(_ enabled: Bool, displayMinutes: Int, reply: @escaping ModeReply)
    func status(reply: @escaping ModeReply)
}

enum ConnectionSigning {
    static func teamID() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var signingInfo: CFDictionary?
        let flags = SecCSFlags()
        guard SecCodeCopySelf(flags, &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, flags, &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &signingInfo
              ) == errSecSuccess,
              let information = signingInfo as? [String: Any],
              let team = information[kSecCodeInfoTeamIdentifier as String] as? String,
              team.utf8.count == 10,
              team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) })
        else { return nil }
        return team
    }

    static func requirement(identifier: String, team: String) -> String {
        #"identifier "\#(identifier)" and anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#
    }
}
