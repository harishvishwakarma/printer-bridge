import PrinterBridgeCore
import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.lg) {
                VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.xs) {
                    Text("Printer Bridge Help")
                        .font(.largeTitle.weight(.bold))
                    Text("Share Mac printers with iPhone and iPad through AirPrint.")
                        .foregroundStyle(.secondary)
                }

                helpSection(
                    "What It Does",
                    systemImage: "airplayaudio",
                    [
                        "Turn on AirPrint sharing for printers already installed on this Mac.",
                        "Keep older printers useful longer instead of turning working equipment into e-waste.",
                        "Run in the background so you do not need to keep the window open.",
                    ]
                )

                helpSection(
                    "Printer States",
                    systemImage: "dot.radiowaves.left.and.right",
                    [
                        "`Live` means this printer is being advertised over AirPrint right now.",
                        "`Off` means Printer Bridge is not sharing that printer.",
                        "`Needs Review` means the printer is installed, but Printer Bridge still needs something to line up before it can share it reliably.",
                        "`Unavailable` means the queue is not currently available on this Mac.",
                    ]
                )

                helpSection(
                    "Jobs",
                    systemImage: "list.bullet.rectangle",
                    [
                        "`Refresh` reloads the current queue from CUPS.",
                        "`Cancel Active` stops jobs that are still in progress at the Mac queue.",
                        "`Clear Recent` removes completed history for the selected queue when there are no active jobs.",
                    ]
                )

                helpSection(
                    "Settings",
                    systemImage: "gearshape",
                    [
                        "`Keep sharing in the background` installs and uses the bundled background service so AirPrint stays available after the window closes.",
                        "`AirPrint name` lets you publish a friendlier printer name than the raw CUPS queue name.",
                        "`Endpoint` shows the IPP address currently being advertised for the selected printer.",
                    ]
                )

                VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.sm) {
                    Label("Open Source", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.headline)

                    PrinterBridgeCard {
                        VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.sm) {
                            Text("Read the source, report a problem, or suggest an improvement.")
                                .foregroundStyle(.secondary)

                            Link("View source on GitHub", destination: URL(string: ProjectMetadata.repositoryURL)!)
                            Link("Report a bug", destination: URL(string: ProjectMetadata.bugReportURL)!)
                            Link("Request a feature", destination: URL(string: ProjectMetadata.featureRequestURL)!)

                            Divider()

                            HStack(spacing: PrinterBridgeDesign.Space.md) {
                                Link("Privacy policy", destination: URL(string: ProjectMetadata.privacyURL)!)
                                Link("Terms", destination: URL(string: ProjectMetadata.termsURL)!)
                            }
                            .font(.footnote)
                        }
                    }
                }
            }
            .padding(PrinterBridgeDesign.Space.lg)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 540, minHeight: 500)
    }

    private func helpSection(_ title: String, systemImage: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.sm) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            PrinterBridgeCard {
                VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.sm) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: PrinterBridgeDesign.Space.xs) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                            Text(.init(item))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}
