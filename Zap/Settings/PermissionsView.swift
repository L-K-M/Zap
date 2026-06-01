import SwiftUI
import Combine

/// Shows Accessibility permission status and guidance for granting it.
struct PermissionsView: View {
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
                    Text(isTrusted ? "Granted — ⌘-Tab interception is active." : "Not granted — Zap is using the ⌥-Tab fallback.")
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
}
