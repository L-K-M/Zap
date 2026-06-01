import SwiftUI
import Combine

/// Shows Accessibility permission status and guidance for granting it.
struct PermissionsView: View {
    @ObservedObject var inputMode: InputModeReporter
    @State private var isTrusted = AccessibilityAuthorizer.isTrusted
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isTrusted ? .green : .orange)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text("Accessibility")
                        .font(.headline)
                    Text(statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("""
            Zap needs Accessibility access to intercept ⌘-Tab and replace the system \
            switcher. Without it, Zap still works via the ⌥-Tab fallback, but cannot \
            override the native ⌘-Tab.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button("Request Access") { AccessibilityAuthorizer.prompt() }
                Button("Open System Settings") { AccessibilityAuthorizer.openSystemSettings() }
            }

            if !isTrusted {
                Text("After granting access, quit and relaunch Zap to enable ⌘-Tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(timer) { _ in
            isTrusted = AccessibilityAuthorizer.isTrusted
        }
    }

    /// Describes the *actual* trigger mode, not just the permission grant — the
    /// event tap can fail to install even when Accessibility is granted.
    private var statusDescription: String {
        switch inputMode.mode {
        case .eventTap:
            return "Granted — ⌘-Tab interception is active."
        case .fallback:
            return isTrusted
                ? "Using the ⌥-Tab fallback (⌘-Tab interception is off)."
                : "Not granted — Zap is using the ⌥-Tab fallback."
        case .unavailable:
            return "No trigger active — ⌘-Tab interception and the ⌥-Tab fallback both failed."
        case .paused:
            return "Paused — Zap is not intercepting any shortcut."
        }
    }
}
