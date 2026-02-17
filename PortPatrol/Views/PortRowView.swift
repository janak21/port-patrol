import SwiftUI

struct PortRowView: View {
    let port: PortInfo
    let onKill: () -> Void

    @State private var isHovered: Bool = false
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: 10) {
                // Category icon
                if let intel = port.intelligence {
                    categoryIcon(intel)
                }

                // Port number
                Text(port.port, format: .number.grouping(.never))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .frame(width: 58, alignment: .trailing)

                // Process info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(port.processName)
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                            .lineLimit(1)

                        // Safety badge
                        if let intel = port.intelligence {
                            safetyBadge(intel.safetyLevel)
                        }
                    }

                    // Short description
                    if let intel = port.intelligence {
                        Text(intel.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        HStack(spacing: 6) {
                            Text("PID \(port.pid)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(port.address)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Protocol badge
                Text(port.transportProtocol)
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(port.transportProtocol == "TCP" ? .blue.opacity(0.15) : .purple.opacity(0.15))
                    )
                    .foregroundColor(port.transportProtocol == "TCP" ? .blue : .purple)

                // State badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)
                    Text(port.stateDisplayName)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(stateColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(stateColor.opacity(0.1))
                )

                // Kill button
                Button {
                    onKill()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isHovered ? .red : .secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Stop this process")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            }

            // Expandable detail section
            if isExpanded, let intel = port.intelligence {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.horizontal, 8)

                    // Explanation lines
                    ForEach(intel.explanation.components(separatedBy: "\n"), id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundColor(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Technical details
                    HStack(spacing: 16) {
                        // Parent process
                        if intel.parentPID > 0 {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("PARENT")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.6))
                                Text("\(intel.parentName) (\(intel.parentPID))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("PID")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text("\(port.pid)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("ADDRESS")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text(port.address)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Full command
                    VStack(alignment: .leading, spacing: 1) {
                        Text("COMMAND")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(intel.fullCommand)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    // Dependents
                    if !intel.dependents.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("DEPENDS ON THIS")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text(intel.dependents.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.orange)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isExpanded ? .white.opacity(0.04) : (isHovered ? .white.opacity(0.06) : .clear))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func categoryIcon(_ intel: ProcessIntelligence.ProcessDetail) -> some View {
        Image(systemName: intel.category.icon)
            .font(.system(size: 14))
            .foregroundColor(categoryColor(intel.category))
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(categoryColor(intel.category).opacity(0.15))
            )
    }

    @ViewBuilder
    private func safetyBadge(_ level: ProcessIntelligence.SafetyLevel) -> some View {
        HStack(spacing: 2) {
            Image(systemName: level.icon)
                .font(.system(size: 8))
            Text(level.rawValue)
                .font(.system(size: 9))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            Capsule()
                .fill(safetyColor(level).opacity(0.15))
        )
        .foregroundColor(safetyColor(level))
    }

    private func categoryColor(_ cat: ProcessIntelligence.ProcessCategory) -> Color {
        switch cat {
        case .database: return .purple
        case .webServer: return .blue
        case .devTool: return .orange
        case .aiTool: return .pink
        case .languageRuntime: return .green
        case .systemService: return .gray
        case .container: return .cyan
        case .networking: return .teal
        case .unknown: return .secondary
        }
    }

    private func safetyColor(_ level: ProcessIntelligence.SafetyLevel) -> Color {
        switch level {
        case .safe: return .green
        case .caution: return .orange
        case .dangerous: return .red
        }
    }

    private var stateColor: Color {
        switch port.stateDisplayName {
        case "LISTEN":
            return .green
        case "ESTABLISHED":
            return .blue
        case "CLOSE_WAIT":
            return .orange
        case "TIME_WAIT":
            return .yellow
        default:
            return .secondary
        }
    }
}
