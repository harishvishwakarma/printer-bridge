import PrinterBridgeCore
import SwiftUI

struct ContentView: View {
    private enum Destination: String, CaseIterable, Identifiable {
        case printers = "Printers"
        case jobs = "Print Jobs"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .printers: "printer"
            case .jobs: "list.bullet.rectangle"
            case .settings: "gearshape"
            }
        }
    }

    @ObservedObject var model: PrinterBridgeViewModel
    @Binding var appearanceMode: AppAppearanceMode
    let appearanceRefreshToken: UUID

    @State private var selection: Destination? = .printers

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .tint(PrinterBridgeDesign.accent)
        .accentColor(PrinterBridgeDesign.accent)
        .toolbar(removing: .title)
        .id(appearanceRefreshToken)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 600)
        .task {
            model.loadBridgeState(forceBackgroundSync: true)
        }
    }

    private var sidebar: some View {
        List(Destination.allCases) { destination in
            Button {
                selection = destination
            } label: {
                Label(destination.rawValue, systemImage: destination.icon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(selection == destination ? PrinterBridgeDesign.accent : .primary)
            .padding(.horizontal, PrinterBridgeDesign.Space.xs)
            .padding(.vertical, 6)
            .background(
                selection == destination ? PrinterBridgeDesign.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: PrinterBridgeDesign.Radius.control, style: .continuous)
            )
            .accessibilityAddTraits(selection == destination ? .isSelected : [])
        }
        .navigationTitle(ProjectMetadata.appDisplayName)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: PrinterBridgeDesign.Space.xs) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.publicationState.title)
                        .font(.caption.weight(.semibold))
                    Text(sidebarStatusDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, PrinterBridgeDesign.Space.sm)
            .padding(.vertical, PrinterBridgeDesign.Space.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("AirPrint status")
            .accessibilityValue("\(model.publicationState.title), \(sidebarStatusDetail)")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .printers {
        case .printers:
            printersPage
        case .jobs:
            jobsPage
        case .settings:
            settingsPage
        }
    }

    private var printersPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.lg) {
                pageHeader(
                    title: "Printers",
                    subtitle: "Choose which Mac printers appear in AirPrint.",
                    actionTitle: "Refresh printers",
                    isWorking: model.isRefreshingBridgeState,
                    action: { model.loadBridgeState() }
                )

                statusCard

                VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.sm) {
                    Text("Available on this Mac")
                        .font(.headline)

                    if model.printerStatuses.isEmpty {
                        PrinterBridgeCard {
                            ContentUnavailableView(
                                "No printers found",
                                systemImage: "printer.slash",
                                description: Text("Add a printer in System Settings, then refresh this list.")
                            )
                            .frame(minHeight: 150)
                        }
                    } else {
                        VStack(spacing: PrinterBridgeDesign.Space.xs) {
                            ForEach(model.printerStatuses) { printer in
                                printerRow(printer)
                            }
                        }
                    }
                }
            }
            .padding(PrinterBridgeDesign.Space.lg)
            .frame(maxWidth: 780, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var jobsPage: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.md) {
                pageHeader(
                    title: "Print Jobs",
                    subtitle: "Monitor and manage the selected Mac print queue.",
                    actionTitle: "Refresh print jobs",
                    isWorking: model.isUpdatingJobs,
                    action: { model.reloadJobs() }
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PrinterBridgeDesign.Space.sm) {
                        queuePicker
                        Spacer()
                        jobActions
                    }

                    VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.sm) {
                        queuePicker
                        jobActions
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        jobSectionHeader("Active")

                        if model.jobSnapshot.activeJobs.isEmpty {
                            emptyJobsRow(
                                title: "No active jobs",
                                detail: "New jobs for this printer will appear here."
                            )
                        } else {
                            ForEach(model.jobSnapshot.activeJobs) { job in
                                jobRow(job, stateLabel: "Printing") {
                                    model.cancelJob(job)
                                }
                                Divider()
                            }
                        }

                        jobSectionHeader("Recent")

                        if model.recentCompletedJobs.isEmpty {
                            emptyJobsRow(
                                title: "No recent jobs",
                                detail: "Completed jobs are kept here for this session."
                            )
                        } else {
                            ForEach(model.recentCompletedJobs) { job in
                                jobRow(job, stateLabel: "Completed")
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, PrinterBridgeDesign.Space.sm)
                }
                .frame(height: max(140, geometry.size.height - 220))
                .background(PrinterBridgeDesign.surface)
                .clipShape(RoundedRectangle(cornerRadius: PrinterBridgeDesign.Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PrinterBridgeDesign.Radius.card, style: .continuous)
                        .stroke(PrinterBridgeDesign.separator, lineWidth: 1)
                }

                if let jobsMessage = model.jobsMessage, !jobsMessage.isEmpty {
                    PrinterBridgeMessage(
                        text: jobsMessage,
                        tone: messageTone(for: jobsMessage)
                    )
                    .accessibilityAddTraits(.isStaticText)
                }
            }
            .padding(PrinterBridgeDesign.Space.lg)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.lg) {
                pageHeader(
                    title: "Settings",
                    subtitle: "Control background sharing, appearance, and the AirPrint identity."
                )

                settingsSection(title: "Sharing") {
                    Toggle(
                        "Keep sharing in the background",
                        isOn: Binding(
                            get: { model.bridgeConfiguration.keepRunningInBackground },
                            set: { model.updateKeepRunningInBackground($0) }
                        )
                    )
                    Text("AirPrint remains available after you close this window.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                settingsSection(title: "Appearance") {
                    Picker("App appearance", selection: $appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Controls whether Printer Bridge uses the system, light, or dark appearance.")
                }

                settingsSection(title: "AirPrint name") {
                    Text("This is the printer name shown on iPhone and iPad.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if model.bridgeConfiguration.selectedQueueName == nil {
                        Label("Select a printer before changing its AirPrint name.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    TextField("AirPrint name", text: $model.advertisedNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.applyAdvertisedName() }
                        .disabled(model.bridgeConfiguration.selectedQueueName == nil)

                    HStack(spacing: PrinterBridgeDesign.Space.xs) {
                        Button("Save name") {
                            model.applyAdvertisedName()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            model.bridgeConfiguration.selectedQueueName == nil
                                || model.advertisedNameDraft == (model.bridgeConfiguration.advertisedNameOverride ?? "")
                        )
                        .help("Publish this name through AirPrint")

                        Button("Use printer name") {
                            model.resetAdvertisedName()
                        }
                        .disabled(
                            model.bridgeConfiguration.selectedQueueName == nil
                                || ((model.bridgeConfiguration.advertisedNameOverride ?? "").isEmpty && model.advertisedNameDraft.isEmpty)
                        )
                        .help("Remove the custom AirPrint name")
                    }
                }

                settingsSection(title: "Connection details") {
                    detailRow(title: "Published name", value: model.currentAirPrintName)
                    detailRow(title: "IPP endpoint", value: model.currentEndpointDescription, monospace: true)

                    if let lastBonjourEvent = model.lastBonjourEvent, !lastBonjourEvent.isEmpty {
                        detailRow(title: "Last Bonjour event", value: lastBonjourEvent, monospace: true)
                    }
                }

                if let bridgeMessage = model.bridgeMessage, !bridgeMessage.isEmpty {
                    PrinterBridgeMessage(
                        text: bridgeMessage,
                        tone: messageTone(for: bridgeMessage)
                    )
                }

                if let warnings = model.focusedPrinterStatus?.advertisement?.warnings, !warnings.isEmpty {
                    VStack(spacing: PrinterBridgeDesign.Space.xs) {
                        ForEach(warnings, id: \.self) { warning in
                            PrinterBridgeMessage(text: warning, tone: .warning)
                        }
                    }
                }
            }
            .padding(PrinterBridgeDesign.Space.lg)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func pageHeader(
        title: String,
        subtitle: String,
        actionTitle: String? = nil,
        isWorking: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: PrinterBridgeDesign.Space.lg) {
            VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.xs) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(action: action) {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(actionTitle, systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                }
                .disabled(isWorking)
                .help(isWorking ? "Refreshing…" : actionTitle)
                .accessibilityLabel(isWorking ? "Refreshing" : actionTitle)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var statusCard: some View {
        PrinterBridgeCard {
            HStack(alignment: .top, spacing: PrinterBridgeDesign.Space.md) {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusTint)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.xs) {
                    Text("AirPrint sharing")
                        .font(.title3.weight(.semibold))

                    Text(model.statusSummary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label {
                        Text(model.printerEnablementSummary)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: enablementIcon)
                            .foregroundStyle(enablementSummaryColor)
                    }
                    .font(.footnote)

                    if let statusDetail = model.statusDetail {
                        Label {
                            Text(statusDetail)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: statusMessageTone.icon)
                                .foregroundStyle(statusMessageTone.tint)
                        }
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, PrinterBridgeDesign.Space.xxs)
                    }
                }

                Spacer(minLength: PrinterBridgeDesign.Space.sm)

                PrinterBridgeStatusBadge(
                    title: model.publicationState.title,
                    systemImage: statusIcon,
                    tint: statusTint
                )
            }
        }
    }

    private func printerRow(_ printer: ManagedPrinterStatus) -> some View {
        let isSelected = model.bridgeConfiguration.selectedQueueName == printer.configuration.queueName

        return HStack(spacing: PrinterBridgeDesign.Space.sm) {
            Button {
                model.updateSelectedQueue(printer.configuration.queueName)
            } label: {
                HStack(spacing: PrinterBridgeDesign.Space.sm) {
                    Image(systemName: isSelected ? "printer.fill" : "printer")
                        .font(.title3)
                        .foregroundStyle(isSelected ? PrinterBridgeDesign.accent : .secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.xxs) {
                        Text(queueDisplayName(printer.configuration.queueName))
                            .font(.body.weight(.semibold))
                        Text(printerRowSubtitle(printer))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: PrinterBridgeDesign.Space.xs)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(queueDisplayName(printer.configuration.queueName))
            .accessibilityValue(isSelected ? "Selected printer" : "Available printer")
            .accessibilityHint("Selects this printer for details and print jobs.")

            PrinterBridgeStatusBadge(
                title: printer.configuration.isEnabled && printer.activationState == .ready ? "Live" : printerRowStateTitle(printer),
                systemImage: printerRowIcon(printer),
                tint: printerRowTint(printer)
            )

            Toggle(
                "Share \(queueDisplayName(printer.configuration.queueName)) with AirPrint",
                isOn: Binding(
                    get: { printer.configuration.isEnabled },
                    set: { model.setPrinterEnabled($0, forQueueNamed: printer.configuration.queueName) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel("Share \(queueDisplayName(printer.configuration.queueName)) with AirPrint")
            .accessibilityHint(printer.configuration.isEnabled ? "Turns off AirPrint sharing for this printer." : "Turns on AirPrint sharing for this printer.")
        }
        .padding(PrinterBridgeDesign.Space.sm)
        .background(isSelected ? PrinterBridgeDesign.accent.opacity(0.08) : PrinterBridgeDesign.surface)
        .clipShape(RoundedRectangle(cornerRadius: PrinterBridgeDesign.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PrinterBridgeDesign.Radius.card, style: .continuous)
                .stroke(isSelected ? PrinterBridgeDesign.accent.opacity(0.55) : PrinterBridgeDesign.separator, lineWidth: 1)
        }
    }

    private var queuePicker: some View {
        Picker("Printer queue", selection: selectedQueueBinding) {
            ForEach(model.printerStatuses) { printer in
                Text(queueDisplayName(printer.configuration.queueName))
                    .tag(Optional(printer.configuration.queueName))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 300, alignment: .leading)
        .disabled(model.printerStatuses.isEmpty)
        .help(model.printerStatuses.isEmpty ? "No printer queues are available" : "Choose the queue to monitor")
    }

    private var jobActions: some View {
        HStack(spacing: PrinterBridgeDesign.Space.xs) {
            Button("Cancel active", role: .destructive) {
                model.cancelActiveJobs()
            }
            .disabled(model.jobSnapshot.activeJobs.isEmpty || model.isUpdatingJobs)
            .help(model.jobSnapshot.activeJobs.isEmpty ? "There are no active jobs to cancel" : "Cancel every active job in this queue")

            Button("Clear recent") {
                model.clearRecentJobs()
            }
            .disabled(model.recentCompletedJobs.isEmpty || !model.jobSnapshot.activeJobs.isEmpty || model.isUpdatingJobs)
            .help(clearRecentHelp)
        }
    }

    private func jobSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, PrinterBridgeDesign.Space.sm)
            .padding(.bottom, PrinterBridgeDesign.Space.xs)
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.sm) {
            Text(title)
                .font(.headline)
            PrinterBridgeCard {
                VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.sm) {
                    content()
                }
            }
        }
    }

    @ViewBuilder
    private func jobRow(_ job: PrintJob, stateLabel: String, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: PrinterBridgeDesign.Space.sm) {
            Image(systemName: stateLabel == "Printing" ? "printer.fill" : "checkmark.circle.fill")
                .foregroundStyle(stateLabel == "Printing" ? PrinterBridgeDesign.accent : .green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.xxs) {
                Text(job.id)
                    .font(.subheadline.weight(.medium))
                    .textSelection(.enabled)
                Text("\(job.owner) · \(job.submittedAt)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: PrinterBridgeDesign.Space.xxs) {
                Text(stateLabel)
                    .font(.caption.weight(.semibold))
                if let sizeBytes = job.sizeBytes {
                    Text(byteCountFormatter.string(fromByteCount: Int64(sizeBytes)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let action {
                Button(role: .destructive, action: action) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Cancel this print job")
                .accessibilityLabel("Cancel print job \(job.id)")
            }
        }
        .padding(.vertical, PrinterBridgeDesign.Space.xxs)
    }

    @ViewBuilder
    private func emptyJobsRow(title: String, detail: String) -> some View {
        HStack(spacing: PrinterBridgeDesign.Space.sm) {
            Image(systemName: "tray")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, PrinterBridgeDesign.Space.xs)
    }

    @ViewBuilder
    private func detailRow(title: String, value: String, monospace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: PrinterBridgeDesign.Space.xxs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospace ? .system(.footnote, design: .monospaced) : .body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var selectedQueueBinding: Binding<String?> {
        Binding(
            get: { model.bridgeConfiguration.selectedQueueName },
            set: { model.updateSelectedQueue($0) }
        )
    }

    private var sidebarStatusDetail: String {
        model.livePrinterCount == 1 ? "1 printer live" : "\(model.livePrinterCount) printers live"
    }

    private var statusTint: Color {
        switch model.publicationState {
        case .inactive: .secondary
        case .waiting: .orange
        case .advertising: .green
        case .failed: .red
        }
    }

    private var statusIcon: String {
        switch model.publicationState {
        case .inactive: "pause.circle"
        case .waiting: "exclamationmark.triangle.fill"
        case .advertising: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var statusMessageTone: PrinterBridgeMessage.Tone {
        switch model.publicationState {
        case .failed: .error
        case .waiting: .warning
        case .inactive, .advertising: .information
        }
    }

    private var enablementSummaryColor: Color {
        model.printerStatuses.isEmpty || model.enabledPrinterCount == 0 ? .orange : .green
    }

    private var enablementIcon: String {
        model.printerStatuses.isEmpty || model.enabledPrinterCount == 0
            ? "exclamationmark.circle"
            : "checkmark.circle"
    }

    private func printerRowSubtitle(_ printer: ManagedPrinterStatus) -> String {
        if printer.configuration.isEnabled {
            return printer.message
        }
        return printer.inspection?.summary.status.capitalized ?? "Available on this Mac"
    }

    private func printerRowStateTitle(_ printer: ManagedPrinterStatus) -> String {
        switch printer.activationState {
        case .disabled: "Off"
        case .ready: "Ready"
        case .needsReview: "Needs Review"
        case .unavailable: "Unavailable"
        }
    }

    private func printerRowIcon(_ printer: ManagedPrinterStatus) -> String {
        switch printer.activationState {
        case .disabled: "pause.circle"
        case .ready: "checkmark.circle.fill"
        case .needsReview: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.octagon.fill"
        }
    }

    private func printerRowTint(_ printer: ManagedPrinterStatus) -> Color {
        switch printer.activationState {
        case .disabled: .secondary
        case .ready: .green
        case .needsReview: .orange
        case .unavailable: .red
        }
    }

    private var clearRecentHelp: String {
        if !model.jobSnapshot.activeJobs.isEmpty {
            return "Wait for active jobs to finish before clearing recent jobs"
        }
        if model.recentCompletedJobs.isEmpty {
            return "There are no recent jobs to clear"
        }
        return "Clear completed jobs from this session"
    }

    private func messageTone(for message: String) -> PrinterBridgeMessage.Tone {
        if message.localizedCaseInsensitiveContains("failed")
            || message.localizedCaseInsensitiveContains("could not") {
            return .error
        }
        if message.localizedCaseInsensitiveContains("select a printer") {
            return .warning
        }
        return .information
    }

    private func queueDisplayName(_ queueName: String) -> String {
        queueName.replacingOccurrences(of: "_", with: " ")
    }

    private var byteCountFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }
}

#Preview {
    ContentView(
        model: PrinterBridgeViewModel(),
        appearanceMode: .constant(.system),
        appearanceRefreshToken: UUID()
    )
}
