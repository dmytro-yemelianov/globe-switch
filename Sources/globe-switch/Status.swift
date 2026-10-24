import Foundation
import GlobeSwitchCore

/// `globe-switch doctor` asks the running agent for its state with a distributed notification,
/// and the agent answers with this, JSON-encoded as the reply's object.
struct AgentStatus: Codable {
    var pid: Int32
    var version: String
    /// Input Monitoring is granted and the event tap is on.
    var listening: Bool
    var switches: Int
    var bounces: Int
    var secondsSinceSwitch: Int?
}

let statusRequest = Notification.Name("\(GlobeSwitch.label).status-request")
let statusReply = Notification.Name("\(GlobeSwitch.label).status")

extension AgentStatus {
    var json: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    init?(json: String) {
        guard let status = try? JSONDecoder().decode(AgentStatus.self, from: Data(json.utf8)) else { return nil }
        self = status
    }
}
