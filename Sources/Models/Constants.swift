import Foundation

enum Constants {
    /// Time (in seconds) before a pending request expires and falls back to CLI prompt.
    /// Set 5 seconds below the hook timeout to account for network overhead.
    static let requestTimeout: TimeInterval = 55

    /// Timeout (in seconds) registered with Claude Code for the HTTP hook.
    /// Claude Code cancels the hook call after this interval. Must be greater
    /// than `requestTimeout` so Checkpoint can respond with `ask` before
    /// Claude Code gives up and errors out.
    static let hookTimeout: Int = 60
}
