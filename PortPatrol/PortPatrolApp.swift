import SwiftUI

@main
struct PortPatrolApp: App {
    @State private var portScanner = PortScanner()

    var body: some Scene {
        MenuBarExtra {
            ContentView(portScanner: portScanner)
                .frame(width: 480, height: 540)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "network")
                if portScanner.listeningCount > 0 {
                    Text("\(portScanner.listeningCount)")
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
