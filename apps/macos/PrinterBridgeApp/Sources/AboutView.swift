import AppKit
import PrinterBridgeCore
import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.lg) {
                HStack(spacing: PrinterBridgeDesign.Space.md) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.xxs) {
                        Text(ProjectMetadata.appDisplayName)
                            .font(.largeTitle.weight(.bold))
                        Text(ProjectMetadata.appStoreName)
                            .foregroundStyle(.secondary)
                        Text(versionDescription)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Keep working printers useful by making them available to Apple devices through AirPrint.")
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)

                PrinterBridgeCard {
                    VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.sm) {
                        Text("Compatibility")
                            .font(.headline)
                        Text("Printer Bridge works with printers that already print successfully from this Mac. It has been exercised with Epson L8050 and Brother HL-2170W series printers; other macOS printer queues are expected to work as well.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.sm) {
                    Link("View source on GitHub", destination: URL(string: ProjectMetadata.repositoryURL)!)
                    Link("Report a bug", destination: URL(string: ProjectMetadata.bugReportURL)!)
                    Link("Request a feature", destination: URL(string: ProjectMetadata.featureRequestURL)!)
                }

                Divider()

                HStack(spacing: PrinterBridgeDesign.Space.md) {
                    Link("Privacy policy", destination: URL(string: ProjectMetadata.privacyURL)!)
                    Link("Terms", destination: URL(string: ProjectMetadata.termsURL)!)
                }
                .font(.footnote)
            }
            .padding(PrinterBridgeDesign.Space.lg)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(minWidth: 460, minHeight: 460)
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)) where version != build:
            return "Version \(version) (\(build))"
        case let (.some(version), _):
            return "Version \(version)"
        case let (_, .some(build)):
            return "Build \(build)"
        default:
            return "Development build"
        }
    }
}
