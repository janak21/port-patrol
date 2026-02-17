import Foundation
import Combine

@Observable
final class PortScanner {
    var ports: [PortInfo] = []
    var isScanning: Bool = false
    var lastScanTime: Date? = nil
    var autoRefreshEnabled: Bool = true
    var refreshInterval: TimeInterval = 3.0

    private var timer: Timer?

    var listeningCount: Int {
        ports.filter(\.isListening).count
    }

    var listeningPorts: [PortInfo] {
        ports.filter(\.isListening)
            .sorted { $0.port < $1.port }
    }

    var establishedPorts: [PortInfo] {
        ports.filter { !$0.isListening }
            .sorted { $0.port < $1.port }
    }

    init() {
        scan()
        startAutoRefresh()
    }

    deinit {
        stopAutoRefresh()
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        guard autoRefreshEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    func toggleAutoRefresh() {
        autoRefreshEnabled.toggle()
        if autoRefreshEnabled {
            startAutoRefresh()
        } else {
            stopAutoRefresh()
        }
    }

    func scan() {
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results = Self.runLsof()
            // Enrich with intelligence data
            for i in results.indices {
                results[i].intelligence = ProcessIntelligence.analyze(
                    processName: results[i].processName,
                    pid: results[i].pid
                )
            }
            DispatchQueue.main.async {
                self?.ports = results
                self?.lastScanTime = Date()
                self?.isScanning = false
            }
        }
    }

    // MARK: - lsof parsing

    private static func runLsof() -> [PortInfo] {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-i", "-P", "-n", "-F", "pcnPtT"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return parseLsofFieldOutput(output)
    }

    /// Parses the field-mode output of `lsof -F pcnPtT`
    /// Field prefixes:  p=PID, c=command, n=name, P=protocol, t=type, T=state
    ///
    /// The key insight: lsof outputs fields in this order per file descriptor:
    ///   f (fd), t (type), P (protocol), n (name), T (state flags)
    /// So we must collect ALL fields before emitting, not emit on `n`.
    private static func parseLsofFieldOutput(_ output: String) -> [PortInfo] {
        var results: [PortInfo] = []
        let lines = output.components(separatedBy: "\n")

        var currentPID: Int = 0
        var currentCommand: String = ""
        var currentProtocol: String = ""
        var currentName: String = ""
        var currentState: String = ""
        var hasName = false

        var seenSet = Set<String>()

        /// Try to emit a PortInfo from the currently accumulated fields
        func emitCurrent() {
            guard hasName else { return }
            let portInfo = extractPortInfo(
                pid: currentPID,
                command: currentCommand,
                proto: currentProtocol,
                name: currentName,
                state: currentState
            )
            if let info = portInfo {
                let key = info.id
                if !seenSet.contains(key) {
                    seenSet.insert(key)
                    results.append(info)
                }
            }
            // Reset per-fd fields
            hasName = false
            currentName = ""
            currentState = ""
            currentProtocol = ""
        }

        for line in lines {
            guard !line.isEmpty else { continue }

            let prefix = line.first!
            let value = String(line.dropFirst())

            switch prefix {
            case "p":
                emitCurrent()  // Flush previous fd before new process
                currentPID = Int(value) ?? 0
                currentCommand = ""
            case "c":
                currentCommand = value
            case "f":
                emitCurrent()  // Flush previous fd before new fd
            case "P":
                currentProtocol = value.uppercased()
            case "n":
                currentName = value
                hasName = true
            case "T":
                // State info like TST=LISTEN
                if value.hasPrefix("ST=") {
                    currentState = String(value.dropFirst(3))
                }
            default:
                break
            }
        }

        // Don't forget the last entry
        emitCurrent()

        return results
    }

    private static func extractPortInfo(
        pid: Int,
        command: String,
        proto: String,
        name: String,
        state: String
    ) -> PortInfo? {
        // name looks like "*:8080" or "127.0.0.1:3000" or "[::1]:5432"
        // We want to extract the port from the last colon-separated component
        guard let lastColon = name.lastIndex(of: ":") else { return nil }
        let portString = String(name[name.index(after: lastColon)...])
        guard let port = Int(portString), port > 0 else { return nil }

        // Skip very low-level system ports (like mDNSResponder on 5353) unless they're common dev ports
        // Actually, show everything and let the user filter

        let displayState = state.isEmpty ? (proto == "UDP" ? "UDP" : "UNKNOWN") : state

        return PortInfo(
            port: port,
            pid: pid,
            processName: command,
            transportProtocol: proto,
            state: displayState,
            address: name
        )
    }
}
