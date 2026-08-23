// Hallmark · genre: modern-minimal · macrostructure: Workbench · theme: Cobalt · designed-as-app
// Hallmark · pre-emit critique: P4 H4 E4 S5 R5 V4 · slop: pass (1–58) · native contrast: pass
import SwiftUI

enum PrinterBridgeDesign {
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 12
    }

    // Keep the product's Cobalt identity even when macOS uses a custom system accent.
    static let accent = Color(red: 0.02, green: 0.42, blue: 0.95)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
}

struct PrinterBridgeCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(PrinterBridgeDesign.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PrinterBridgeDesign.surface)
            .clipShape(RoundedRectangle(cornerRadius: PrinterBridgeDesign.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PrinterBridgeDesign.Radius.card, style: .continuous)
                    .stroke(PrinterBridgeDesign.separator, lineWidth: 1)
            }
    }
}

struct PrinterBridgeStatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, PrinterBridgeDesign.Space.sm)
        .padding(.vertical, PrinterBridgeDesign.Space.xs)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct PrinterBridgeMessage: View {
    enum Tone {
        case information
        case warning
        case error

        var icon: String {
            switch self {
            case .information: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .information: .secondary
            case .warning: .orange
            case .error: .red
            }
        }
    }

    let text: String
    let tone: Tone

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: tone.icon)
                .foregroundStyle(tone.tint)
        }
        .font(.footnote)
        .padding(PrinterBridgeDesign.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: PrinterBridgeDesign.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
