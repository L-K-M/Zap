import SwiftUI
import AppKit

/// A small About tab: app identity, version, and a telemetry-free running tally of
/// how many switches Zap has performed — today and all-time.
struct AboutView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
            }

            VStack(spacing: 2) {
                Text("Zap")
                    .font(.title2.bold())
                Text("Version \(Self.appVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(maxWidth: 220)

            VStack(spacing: 4) {
                Text("⚡ Switches today: \(preferences.switchCountToday.formatted())")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text("\(preferences.switchCountTotal.formatted()) all-time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("A fast, customizable macOS app switcher.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `CFBundleShortVersionString`, with the build number appended when it differs.
    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, build != short {
            return "\(short) (\(build))"
        }
        return short
    }
}
