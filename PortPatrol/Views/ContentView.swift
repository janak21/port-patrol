import SwiftUI

struct ContentView: View {
    @Bindable var portScanner: PortScanner
    @State private var searchText: String = ""
    @State private var selectedTab: PortTab = .listening
    @State private var killConfirmation: PortInfo? = nil
    @State private var killError: String? = nil
    @State private var showKillError: Bool = false

    enum PortTab: String, CaseIterable {
        case listening = "Listening"
        case established = "Established"
        case all = "All"
    }

    private var filteredPorts: [PortInfo] {
        let base: [PortInfo]
        switch selectedTab {
        case .listening:
            base = portScanner.listeningPorts
        case .established:
            base = portScanner.establishedPorts
        case .all:
            base = portScanner.ports.sorted { $0.port < $1.port }
        }

        if searchText.isEmpty { return base }

        let query = searchText.lowercased()
        return base.filter {
            String($0.port).contains(query) ||
            $0.processName.lowercased().contains(query) ||
            String($0.pid).contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            searchBar
            tabBar
            Divider()
            portList
            footerView
        }
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
        )
        .overlay {
            if let port = killConfirmation {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { killConfirmation = nil }

                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                        Text("Stop Process?")
                            .font(.headline)
                        Text("Stop \"\(port.processName)\" (PID \(port.pid)) on port \(port.port)?")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            killConfirmation = nil
                        }
                        .keyboardShortcut(.escape, modifiers: [])

                        Button("Terminate") {
                            killProcess(port, force: false)
                        }
                        .keyboardShortcut(.defaultAction)

                        Button("Force Kill") {
                            killProcess(port, force: true)
                        }
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .shadow(radius: 10)
                )
                .padding(40)
            }

            if showKillError {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { showKillError = false }

                VStack(spacing: 12) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.red)
                    Text("Error")
                        .font(.headline)
                    Text(killError ?? "Unknown error")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)

                    Button("OK") {
                        showKillError = false
                        killError = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .shadow(radius: 10)
                )
                .padding(40)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Port Patrol")
                    .font(.headline)
                    .fontWeight(.bold)
            }

            Spacer()

            HStack(spacing: 6) {
                // Port count badge
                Text("\(portScanner.listeningCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(.blue.opacity(0.2))
                    )
                    .foregroundColor(.blue)

                // Auto-refresh toggle
                Button {
                    portScanner.toggleAutoRefresh()
                } label: {
                    Image(systemName: portScanner.autoRefreshEnabled ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(portScanner.autoRefreshEnabled ? .green : .secondary)
                        .opacity(portScanner.isScanning && portScanner.autoRefreshEnabled ? 0.4 : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: portScanner.isScanning)
                }
                .buttonStyle(.plain)
                .help(portScanner.autoRefreshEnabled ? "Auto-refresh ON (3s)" : "Auto-refresh OFF")

                // Manual refresh
                Button {
                    portScanner.scan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh now")

                // Quit
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Quit Port Patrol")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Search port, process, or PID…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .default))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PortTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(.subheadline)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                            Text("\(countForTab(tab))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)

                        Rectangle()
                            .fill(selectedTab == tab ? Color.blue : .clear)
                            .frame(height: 2)
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
    }

    private func countForTab(_ tab: PortTab) -> Int {
        switch tab {
        case .listening: return portScanner.listeningPorts.count
        case .established: return portScanner.establishedPorts.count
        case .all: return portScanner.ports.count
        }
    }

    // MARK: - Port List

    private var portList: some View {
        Group {
            if filteredPorts.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "network.slash" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(searchText.isEmpty ? "No ports found" : "No matching ports")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredPorts) { port in
                            PortRowView(port: port) {
                                killConfirmation = port
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let time = portScanner.lastScanTime {
                HStack(spacing: 4) {
                    Circle()
                        .fill(portScanner.autoRefreshEnabled ? .green : .orange)
                        .frame(width: 6, height: 6)
                        .opacity(portScanner.isScanning ? 0.5 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: portScanner.isScanning)

                    Text("Updated \(time.formatted(.dateTime.hour().minute().second()))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("⌘Q to quit")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Actions

    private func killProcess(_ port: PortInfo, force: Bool) {
        let result = force
            ? ProcessManager.forceKill(pid: port.pid)
            : ProcessManager.terminate(pid: port.pid)

        switch result {
        case .success:
            // Refresh ports after a short delay to allow process to exit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                portScanner.scan()
            }
        case .failure(let message):
            killError = "Failed to kill \(port.processName) (PID \(port.pid)): \(message)"
            showKillError = true
        }
        if killConfirmation != nil {
            killConfirmation = nil
        }
    }
}

// MARK: - Visual Effect Blur (NSVisualEffectView wrapper)

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
