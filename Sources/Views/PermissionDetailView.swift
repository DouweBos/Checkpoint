import SwiftUI

struct PermissionDetailView: View {
    @Environment(PermissionManager.self) private var manager
    let request: PermissionManager.PendingRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tool header
            HStack(spacing: 8) {
                Image(systemName: iconForTool(request.request.toolName))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                Text(displayName(for: request.request.toolName))
                    .font(.system(.subheadline, weight: .semibold))
                Spacer()
                Text(String(request.request.sessionId.prefix(8)))
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Tool input detail
            toolInputSummary
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            // Timer
            TimeRemainingView(since: request.receivedAt)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 8)

            // Actions
            HStack(spacing: 6) {
                Button {
                    manager.deny(request)
                } label: {
                    Text("Deny")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.red.opacity(0.08))
                )
                .keyboardShortcut(.escape, modifiers: [])

                Button {
                    manager.createRule(from: request)
                } label: {
                    Text(request.request.allowRuleLabel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )

                Button {
                    manager.approve(request)
                } label: {
                    Text("Allow")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor)
                )
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var toolInputSummary: some View {
        let input = request.request.toolInput
        let tool = request.request.toolName

        switch tool {
        case "Bash":
            if let command = input["command"]?.stringValue {
                codeBlock(command, lineLimit: 3)
            }
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            if let filePath = input["file_path"]?.stringValue {
                pathLabel(filePath)
            }
        case "WebFetch":
            if let url = input["url"]?.stringValue {
                iconLabel(systemName: "globe", text: url, truncation: .middle)
            }
        case "WebSearch":
            if let query = input["query"]?.stringValue {
                iconLabel(systemName: "magnifyingglass", text: query)
            }
        case "Skill":
            if let skill = input["skill"]?.stringValue {
                iconLabel(systemName: "sparkles", text: skill)
            }
        default:
            if tool.hasPrefix("mcp__") {
                mcpSummary(tool: tool, input: input)
            }
        }
    }

    // MARK: - Reusable display components

    private func codeBlock(_ text: String, lineLimit: Int) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.8))
            .lineLimit(lineLimit)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )
    }

    private func pathLabel(_ path: String) -> some View {
        iconLabel(systemName: "doc", text: path, lineLimit: 2, truncation: .middle)
    }

    private func iconLabel(
        systemName: String,
        text: String,
        lineLimit: Int = 1,
        truncation: Text.TruncationMode = .tail
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                .truncationMode(truncation)
        }
    }

    @ViewBuilder
    private func mcpSummary(tool: String, input: [String: JSONValue]) -> some View {
        // MCP tool names look like "mcp__server__tool_name"
        let parts = tool.split(separator: "_", maxSplits: 4, omittingEmptySubsequences: true)
        let displayTool = parts.count >= 2 ? parts.dropFirst().joined(separator: "/") : tool
        iconLabel(systemName: "puzzlepiece", text: displayTool)
    }

    // MARK: - Tool icons

    private func iconForTool(_ tool: String) -> String {
        switch tool {
        case "Write": return "doc.badge.plus"
        case "Edit", "MultiEdit": return "pencil"
        case "NotebookEdit": return "tablecells"
        case "Bash": return "terminal"
        case "WebFetch": return "globe"
        case "WebSearch": return "magnifyingglass"
        case "Skill": return "sparkles"
        default:
            if tool.hasPrefix("mcp__") { return "puzzlepiece" }
            return "wrench"
        }
    }

    /// Formats MCP tool names like `mcp__server__tool` into `server/tool`.
    private func displayName(for tool: String) -> String {
        guard tool.hasPrefix("mcp__") else { return tool }
        let stripped = String(tool.dropFirst(5)) // drop "mcp__"
        let parts = stripped.split(separator: "__", maxSplits: 1)
        if parts.count == 2 {
            return "\(parts[0])/\(parts[1])"
        }
        return stripped
    }
}

struct TimeRemainingView: View {
    let since: Date

    @State private var remaining: TimeInterval = Constants.requestTimeout

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var progress: Double {
        max(0, remaining) / Constants.requestTimeout
    }

    private var tint: Color {
        if remaining < 10 { return .red }
        if remaining < 25 { return .orange }
        return .accentColor
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint.opacity(0.5))
                    .frame(width: geo.size.width * progress)
                    .animation(.linear(duration: 1), value: remaining)
            }
        }
        .frame(height: 3)
        .onReceive(timer) { _ in
            remaining = Constants.requestTimeout - Date().timeIntervalSince(since)
        }
        .onAppear {
            remaining = Constants.requestTimeout - Date().timeIntervalSince(since)
        }
    }
}
