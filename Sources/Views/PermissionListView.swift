import ServiceManagement
import SwiftUI

struct PermissionListView: View {
    @Environment(PermissionManager.self) private var manager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
            if !manager.allowRules.isEmpty {
                activeRulesSection
            }
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text("Checkpoint")
                .font(.headline)
            Spacer()
            if manager.serverRunning {
                Text(verbatim: ":\(manager.port)")
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.tertiary)
            }
            Circle()
                .fill(manager.serverRunning ? Color.green : Color.red)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if manager.pendingRequests.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No pending requests")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(manager.pendingRequests) { request in
                        PermissionDetailView(request: request)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 400)
        }
    }

    private var activeRulesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ACTIVE RULES")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ForEach(manager.allowRules) { rule in
                HStack(spacing: 8) {
                    Image(systemName: iconForTool(rule.toolName))
                        .font(.caption)
                        .foregroundStyle(.green)
                        .frame(width: 14)
                    Text(rule.label)
                        .font(.caption)
                        .monospaced()
                    Spacer()
                    Text(String(rule.sessionId.prefix(8)))
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.quaternary)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            manager.revokeRule(rule)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
            }
            .padding(.bottom, 4)
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .foregroundStyle(.secondary)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

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
}
