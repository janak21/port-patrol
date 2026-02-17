import Foundation

/// Provides human-friendly intelligence about processes: what they are, who started them,
/// whether they're safe to kill, and what depends on them.
enum ProcessIntelligence {

    // MARK: - Process Info Gathering

    struct ProcessDetail {
        let parentName: String
        let parentPID: Int
        let fullCommand: String
        let user: String
        let description: String
        let category: ProcessCategory
        let safetyLevel: SafetyLevel
        let dependents: [String]        // processes that depend on this one
        let explanation: String          // human-friendly "why is this running?"
    }

    enum ProcessCategory: String {
        case database = "Database"
        case webServer = "Web Server"
        case devTool = "Dev Tool"
        case aiTool = "AI Tool"
        case languageRuntime = "Runtime"
        case systemService = "System"
        case container = "Container"
        case networking = "Networking"
        case unknown = "Other"

        var icon: String {
            switch self {
            case .database: return "cylinder"
            case .webServer: return "globe"
            case .devTool: return "hammer"
            case .aiTool: return "brain"
            case .languageRuntime: return "chevron.left.forwardslash.chevron.right"
            case .systemService: return "gearshape"
            case .container: return "shippingbox"
            case .networking: return "network"
            case .unknown: return "questionmark.circle"
            }
        }

        var color: String {
            switch self {
            case .database: return "purple"
            case .webServer: return "blue"
            case .devTool: return "orange"
            case .aiTool: return "pink"
            case .languageRuntime: return "green"
            case .systemService: return "gray"
            case .container: return "cyan"
            case .networking: return "teal"
            case .unknown: return "secondary"
            }
        }
    }

    enum SafetyLevel: String {
        case safe = "Safe to Stop"
        case caution = "Stop with Caution"
        case dangerous = "System Process"

        var icon: String {
            switch self {
            case .safe: return "checkmark.shield"
            case .caution: return "exclamationmark.shield"
            case .dangerous: return "xmark.shield"
            }
        }

        var colorName: String {
            switch self {
            case .safe: return "green"
            case .caution: return "orange"
            case .dangerous: return "red"
            }
        }
    }

    // MARK: - Caching

    private struct CacheEntry {
        let detail: ProcessDetail
        let timestamp: Date
    }

    private static var cache: [Int: CacheEntry] = [:]
    private static let cacheTTL: TimeInterval = 30.0 // Cache for 30 seconds

    // MARK: - Gather Intelligence

    static func analyze(processName: String, pid: Int) -> ProcessDetail {
        // Check cache
        if let entry = cache[pid], Date().timeIntervalSince(entry.timestamp) < cacheTTL {
            // Even if cached, we might want to verify the process name hasn't changed (PID recycling)
            // But for 30s TTL, it's acceptable risk for a UI tool.
            return entry.detail
        }

        // Fetch raw info in one go
        let rawInfo = getRawProcessInfo(pid: pid)
        
        let dependents = getDependentProcesses(pid: pid) // This still needs a separate call
        let knownInfo = knowledgeBase[processName.lowercased()]
        let category = knownInfo?.category ?? guessCategory(processName: processName, command: rawInfo.command)
        let safetyLevel = knownInfo?.safety ?? guessSafety(processName: processName, user: rawInfo.user)
        let description = knownInfo?.description ?? "Process: \(processName)"
        let explanation = buildExplanation(
            processName: processName,
            description: description,
            parentName: rawInfo.parentName,
            category: category,
            fullCommand: rawInfo.command,
            user: rawInfo.user,
            dependents: dependents
        )

        let detail = ProcessDetail(
            parentName: rawInfo.parentName,
            parentPID: rawInfo.ppid,
            fullCommand: rawInfo.command,
            user: rawInfo.user,
            description: description,
            category: category,
            safetyLevel: safetyLevel,
            dependents: dependents,
            explanation: explanation
        )

        // Update cache
        cache[pid] = CacheEntry(detail: detail, timestamp: Date())

        // Periodic cleanup: if cache grows too large, remove stale entries
        if cache.count > 200 {
            let now = Date()
            let staleThreshold = 60.0 // 1 minute
            for (key, value) in cache {
                if now.timeIntervalSince(value.timestamp) > staleThreshold {
                    cache.removeValue(forKey: key)
                }
            }
        }

        return detail
    }

    // MARK: - System Queries

    private static func getRawProcessInfo(pid: Int) -> (ppid: Int, parentName: String, user: String, command: String) {
        // Fetch ppid
        let ppidStr = runCommand("/bin/ps", arguments: ["-o", "ppid=", "-p", "\(pid)"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ppid = Int(ppidStr) ?? 0

        // Fetch user
        let user = runCommand("/bin/ps", arguments: ["-o", "user=", "-p", "\(pid)"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Fetch full command
        let command = runCommand("/bin/ps", arguments: ["-o", "command=", "-p", "\(pid)"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Resolve parent name
        var parentName = "Unknown"
        if ppid > 0 {
            let pName = runCommand("/bin/ps", arguments: ["-o", "comm=", "-p", "\(ppid)"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !pName.isEmpty {
                parentName = (pName as NSString).lastPathComponent
            }
        }

        return (
            ppid,
            parentName,
            user.isEmpty ? "Unknown" : user,
            command.isEmpty ? "Unknown" : command
        )
    }

    private static func getDependentProcesses(pid: Int) -> [String] {
        let output = runCommand("/bin/ps", arguments: ["-o", "comm=", "--ppid", "\(pid)"])
        let children = output
            .components(separatedBy: "\n")
            .map { ($0.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).lastPathComponent }
            .filter { !$0.isEmpty }
            .filter { $0 != "ps" } // Exclude the ps command itself if it shows up
        return children
    }

    private static func runCommand(_ path: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    // MARK: - Explanation Builder

    private static func buildExplanation(
        processName: String,
        description: String,
        parentName: String,
        category: ProcessCategory,
        fullCommand: String,
        user: String,
        dependents: [String]
    ) -> String {
        var parts: [String] = []

        // What is it?
        parts.append("📦 \(description)")

        // Who started it?
        if parentName != "Unknown" && parentName != processName {
            parts.append("🚀 Started by: \(parentName)")
        }

        // Running as?
        if user != "Unknown" {
            parts.append("👤 Running as: \(user)")
        }

        // What depends on it?
        if !dependents.isEmpty {
            let depList = dependents.prefix(5).joined(separator: ", ")
            let extra = dependents.count > 5 ? " (+\(dependents.count - 5) more)" : ""
            parts.append("🔗 Used by: \(depList)\(extra)")
        }

        // Should I keep it?
        switch category {
        case .database:
            parts.append("💡 This is a database. Other apps may depend on it. Stop only if you're sure nothing needs it.")
        case .webServer:
            parts.append("💡 This is a web/API server. It may be serving a dev project or a background tool.")
        case .aiTool:
            parts.append("💡 This is from an AI coding tool. Safe to stop if you're not actively using that tool.")
        case .devTool:
            parts.append("💡 This is a development tool. Safe to stop if you're done with that project.")
        case .systemService:
            parts.append("⚠️ This is a system service. Stopping it may affect other apps or macOS itself.")
        case .container:
            parts.append("💡 This is a container service. Other containers or databases may depend on it.")
        case .languageRuntime:
            parts.append("💡 This is a language runtime (Node, Python, etc). Usually safe to stop dev servers.")
        case .networking:
            parts.append("💡 This is a networking service. Check if you need it before stopping.")
        case .unknown:
            if dependents.isEmpty {
                parts.append("💡 No other processes depend on this. Likely safe to stop.")
            } else {
                parts.append("⚠️ Other processes depend on this. Stopping it may affect them.")
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Category & Safety Guessing

    private static func guessCategory(processName: String, command: String) -> ProcessCategory {
        let name = processName.lowercased()
        let cmd = command.lowercased()

        if ["postgres", "mysql", "mongod", "redis", "sqlite", "mariadb", "cockroach"].contains(where: { name.contains($0) }) {
            return .database
        }
        if ["nginx", "apache", "httpd", "caddy"].contains(where: { name.contains($0) }) {
            return .webServer
        }
        if ["docker", "containerd", "kubelet", "podman"].contains(where: { name.contains($0) }) {
            return .container
        }
        if ["cursor", "code", "codex", "claude", "copilot", "windsurf", "aider"].contains(where: { name.contains($0) || cmd.contains($0) }) {
            return .aiTool
        }
        if ["node", "python", "ruby", "java", "go", "deno", "bun", "php"].contains(where: { name.contains($0) }) {
            return .languageRuntime
        }
        if cmd.contains("dev") || cmd.contains("serve") || cmd.contains("watch") || cmd.contains("vite") || cmd.contains("next") || cmd.contains("webpack") {
            return .devTool
        }
        return .unknown
    }

    private static func guessSafety(processName: String, user: String) -> SafetyLevel {
        let name = processName.lowercased()
        if user == "root" || ["launchd", "kernel_task", "windowserver", "mds", "coreaudio"].contains(where: { name.contains($0) }) {
            return .dangerous
        }
        if ["postgres", "mysql", "docker", "redis", "mongod"].contains(where: { name.contains($0) }) {
            return .caution
        }
        return .safe
    }

    // MARK: - Knowledge Base

    private struct KnownProcess {
        let description: String
        let category: ProcessCategory
        let safety: SafetyLevel
    }

    private static let knowledgeBase: [String: KnownProcess] = [
        // Databases
        "postgres": KnownProcess(description: "PostgreSQL database server — stores data for apps and dev tools", category: .database, safety: .caution),
        "mysqld": KnownProcess(description: "MySQL database server — stores data for web apps", category: .database, safety: .caution),
        "mongod": KnownProcess(description: "MongoDB database server — NoSQL document database", category: .database, safety: .caution),
        "redis-server": KnownProcess(description: "Redis in-memory cache & message broker", category: .database, safety: .caution),
        "redis": KnownProcess(description: "Redis in-memory cache & message broker", category: .database, safety: .caution),

        // Web servers
        "nginx": KnownProcess(description: "Nginx web server / reverse proxy", category: .webServer, safety: .caution),
        "httpd": KnownProcess(description: "Apache HTTP server", category: .webServer, safety: .caution),
        "caddy": KnownProcess(description: "Caddy web server with automatic HTTPS", category: .webServer, safety: .safe),

        // Language runtimes
        "node": KnownProcess(description: "Node.js JavaScript runtime — likely a dev server or build tool", category: .languageRuntime, safety: .safe),
        "python3": KnownProcess(description: "Python 3 runtime — could be a script, dev server, or AI tool backend", category: .languageRuntime, safety: .safe),
        "python": KnownProcess(description: "Python runtime — could be a script, dev server, or AI tool backend", category: .languageRuntime, safety: .safe),
        "ruby": KnownProcess(description: "Ruby runtime — likely Rails or a dev tool", category: .languageRuntime, safety: .safe),
        "java": KnownProcess(description: "Java runtime — enterprise app or build tool (Gradle/Maven)", category: .languageRuntime, safety: .safe),
        "deno": KnownProcess(description: "Deno JavaScript/TypeScript runtime", category: .languageRuntime, safety: .safe),
        "bun": KnownProcess(description: "Bun JavaScript runtime & bundler", category: .languageRuntime, safety: .safe),
        "php": KnownProcess(description: "PHP runtime — likely a local dev server", category: .languageRuntime, safety: .safe),
        "go": KnownProcess(description: "Go runtime — likely a compiled server binary", category: .languageRuntime, safety: .safe),

        // Dev tools
        "vite": KnownProcess(description: "Vite dev server — frontend hot-reload server for a web project", category: .devTool, safety: .safe),
        "next-server": KnownProcess(description: "Next.js dev server — React framework dev server", category: .devTool, safety: .safe),
        "webpack": KnownProcess(description: "Webpack bundler — JavaScript build tool in watch mode", category: .devTool, safety: .safe),
        "esbuild": KnownProcess(description: "esbuild — fast JavaScript/TypeScript bundler", category: .devTool, safety: .safe),
        "turbopack": KnownProcess(description: "Turbopack — Vercel's fast bundler for Next.js", category: .devTool, safety: .safe),
        "expo": KnownProcess(description: "Expo dev server — React Native development tool", category: .devTool, safety: .safe),
        "metro": KnownProcess(description: "Metro bundler — React Native JavaScript bundler", category: .devTool, safety: .safe),

        // AI tools
        "cursor": KnownProcess(description: "Cursor AI code editor — background language server", category: .aiTool, safety: .safe),
        "code": KnownProcess(description: "VS Code / Cursor — editor background process", category: .aiTool, safety: .safe),
        "claude": KnownProcess(description: "Claude AI coding assistant — local server component", category: .aiTool, safety: .safe),
        "copilot": KnownProcess(description: "GitHub Copilot — AI code completion service", category: .aiTool, safety: .safe),
        "windsurf": KnownProcess(description: "Windsurf AI code editor — background process", category: .aiTool, safety: .safe),
        "codex": KnownProcess(description: "OpenAI Codex — AI coding tool backend", category: .aiTool, safety: .safe),

        // Containers
        "docker": KnownProcess(description: "Docker daemon — manages containers (databases, services)", category: .container, safety: .caution),
        "containerd": KnownProcess(description: "Container runtime — backend for Docker", category: .container, safety: .caution),
        "com.docker.backend": KnownProcess(description: "Docker Desktop backend — manages Docker engine on macOS", category: .container, safety: .caution),
        "vpnkit": KnownProcess(description: "Docker Desktop networking — handles container networking", category: .container, safety: .caution),
        "kubectl": KnownProcess(description: "Kubernetes CLI — port-forwarding to a cluster service", category: .container, safety: .safe),

        // System / macOS
        "rapportd": KnownProcess(description: "macOS Rapport daemon — handles device-to-device communication (AirPlay, Handoff)", category: .systemService, safety: .dangerous),
        "mDNSResponder": KnownProcess(description: "macOS DNS resolver — handles all DNS lookups on your Mac", category: .systemService, safety: .dangerous),
        "controlce": KnownProcess(description: "macOS Control Center — system UI component", category: .systemService, safety: .dangerous),
        "sharingd": KnownProcess(description: "macOS Sharing daemon — AirDrop, Handoff, shared clipboard", category: .systemService, safety: .dangerous),
        "identityservicesd": KnownProcess(description: "macOS Identity Services — iMessage, FaceTime, iCloud auth", category: .systemService, safety: .dangerous),
        "remoted": KnownProcess(description: "macOS Remote Services — Xcode device communication", category: .systemService, safety: .dangerous),
        "WiFiAgent": KnownProcess(description: "macOS WiFi agent — manages wireless connections", category: .systemService, safety: .dangerous),
        "AirPlayXPCHelper": KnownProcess(description: "macOS AirPlay helper — screen mirroring and streaming", category: .systemService, safety: .dangerous),

        // Networking
        "ssh": KnownProcess(description: "SSH client — secure tunnel, possibly port forwarding", category: .networking, safety: .safe),
        "sshd": KnownProcess(description: "SSH server — remote access to this machine", category: .networking, safety: .caution),
        "wireguard-go": KnownProcess(description: "WireGuard VPN — secure networking tunnel", category: .networking, safety: .caution),
        "openvpn": KnownProcess(description: "OpenVPN client — VPN connection", category: .networking, safety: .caution),
        "tailscaled": KnownProcess(description: "Tailscale VPN daemon — mesh networking", category: .networking, safety: .caution),
        "ngrok": KnownProcess(description: "ngrok tunnel — exposes local ports to the internet", category: .networking, safety: .safe),
    ]
}
