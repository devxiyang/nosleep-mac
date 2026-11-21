import Darwin
import Foundation
import MCP

@main
struct NoSleepMCP {
    static func main() async {
        let server = Server(
            name: "nosleep",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            capabilities: .init(tools: .init())
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: NoSleepTool.allCases.map(\.specification))
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            guard let tool = NoSleepTool(rawValue: parameters.name) else {
                throw MCPError.invalidParams("Unknown NoSleep tool.")
            }
            guard let request = tool.request(arguments: parameters.arguments ?? [:]) else {
                return try result(for: .failure(.invalidArguments), tool: tool)
            }
            return try await result(for: requestApp(request), tool: tool)
        }

        do {
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
        } catch {
            FileHandle.standardError.write(Data("NoSleepMCP could not start the stdio transport.\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func requestApp(_ request: AgentControlRequest) async -> AgentControlReply {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let reply: AgentControlReply
                do {
                    reply = try AgentControlSocket.call(request, at: .currentUser())
                } catch let error as AgentControlError {
                    reply = .failure(error)
                } catch {
                    reply = .failure(.connectionFailed)
                }
                continuation.resume(returning: reply)
            }
        }
    }

    private static func result(for reply: AgentControlReply, tool: NoSleepTool) throws -> CallTool.Result {
        let value: Value
        let isError: Bool
        switch reply {
        case let .status(status):
            var fields: [String: Value] = [
                "power_source": .string(status.powerSource.rawValue),
                "keep_awake_on_ac": .bool(status.keepAwakeOnAC),
                "keep_awake_status": .string(status.keepAwakeStatus.rawValue),
                "idle_lock_after_minutes": .int(status.idleLockAfterMinutes),
                "display_sleep_after_minutes": status.displaySleepAfterMinutes.map(Value.int) ?? .null,
                "idle_lock_status": .string(status.idleLockStatus.rawValue),
            ]
            if tool != .getStatus { fields["saved"] = .bool(true) }
            value = .object(fields)
            isError = false
        case let .failure(error):
            value = .object(["error": .string(error.rawValue), "message": .string(error.message)])
            isError = true
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = String(decoding: try encoder.encode(value), as: UTF8.self)
        return CallTool.Result(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            structuredContent: Optional.some(value),
            isError: isError
        )
    }
}

private enum NoSleepTool: String, CaseIterable {
    case getStatus = "get_status"
    case setKeepAwakeOnAC = "set_keep_awake_on_ac"
    case setIdleLockAfter = "set_idle_lock_after"

    var specification: Tool {
        let description: String
        let properties: [String: Value]
        let required: [Value]
        switch self {
        case .getStatus:
            description = "Read NoSleep's configured settings and current power and idle-lock status."
            properties = [:]
            required = []
        case .setKeepAwakeOnAC:
            description = "Save the keep-awake switch used by the NoSleep menu. Applies on external power. The result reports current status separately."
            properties = ["enabled": .object(["type": "boolean"])]
            required = ["enabled"]
        case .setIdleLockAfter:
            description = "Save the idle display and lock delay in whole minutes. The result reports current status separately."
            properties = ["minutes": .object([
                "type": "integer",
                "minimum": .int(DurationUnit.validMinutes.lowerBound),
                "maximum": .int(DurationUnit.validMinutes.upperBound)
            ])]
            required = ["minutes"]
        }
        return Tool(
            name: rawValue,
            description: description,
            inputSchema: .object([
                "type": "object",
                "properties": .object(properties),
                "required": .array(required),
                "additionalProperties": false,
            ]),
            annotations: .init(
                readOnlyHint: self == .getStatus,
                idempotentHint: self == .getStatus ? nil : true,
                openWorldHint: false
            )
        )
    }

    func request(arguments: [String: Value]) -> AgentControlRequest? {
        switch self {
        case .getStatus:
            return arguments.isEmpty ? .getStatus : nil
        case .setKeepAwakeOnAC:
            guard arguments.count == 1, case let .bool(enabled)? = arguments["enabled"] else { return nil }
            return .setKeepAwakeOnAC(enabled: enabled)
        case .setIdleLockAfter:
            guard arguments.count == 1, case let .int(minutes)? = arguments["minutes"],
                  DurationUnit.validMinutes.contains(minutes)
            else { return nil }
            return .setIdleLockAfter(minutes: minutes)
        }
    }
}
