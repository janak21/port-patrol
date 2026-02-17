import Foundation

struct PortInfo: Identifiable, Hashable {
    var id: String { "\(pid):\(port):\(transportProtocol):\(state)" }
    let port: Int
    let pid: Int
    let processName: String
    let transportProtocol: String   // TCP or UDP
    let state: String               // LISTEN, ESTABLISHED, CLOSE_WAIT, etc.
    let address: String             // *:port or 127.0.0.1:port

    // Intelligence (populated lazily)
    var intelligence: ProcessIntelligence.ProcessDetail?

    var isListening: Bool {
        state.uppercased() == "LISTEN" || state.uppercased() == "(LISTEN)"
    }

    var stateDisplayName: String {
        state
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .uppercased()
    }

    // Hashable conformance (exclude intelligence since it's supplementary)
    static func == (lhs: PortInfo, rhs: PortInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
