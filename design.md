# Design — Printer Bridge

A locked native macOS design system for Printer Bridge. Every app screen should
use the shared SwiftUI tokens in `PrinterBridgeDesignSystem.swift` and preserve
standard macOS control behaviour.

## Genre

Modern-minimal: technical, calm, and specific.

## Macrostructure family

- App screens: Workbench — persistent navigation, one primary task per detail view, live state visible without drilling in.
- Help: Long Document within the same type, colour, and surface system.
- About: compact product colophon within the same system.

## Theme

Cobalt, adapted to semantic macOS colours:

- Paper and raised surfaces use `NSColor.windowBackgroundColor` and `NSColor.controlBackgroundColor` so Light, Dark, and increased-contrast modes remain native.
- Ink and muted ink use SwiftUI primary and secondary foreground styles.
- The single interaction accent uses the explicit adaptive Cobalt token in `PrinterBridgeDesign.accent`, so it is not replaced by a user's unrelated macOS accent colour.
- Green, orange, and red are reserved for status, always paired with an icon and text.

## Typography

- Display: San Francisco through SwiftUI semantic title styles, bold.
- Body: San Francisco through SwiftUI semantic body styles, regular.
- Mono: system monospaced face for IPP endpoints and diagnostic values only.
- Dynamic semantic styles are required; fixed point sizes are reserved for tiny decorative bullets.

## Spacing

Use the named 4-point Swift scale in `PrinterBridgeDesign.Space`: 4, 8, 12, 16, 24, and 32 points.

## Motion

- No decorative entrance or hover motion.
- Native control and navigation transitions only.
- Functional progress indicators communicate refresh activity.
- Reduced Motion is inherited from macOS automatically.

## Microinteractions stance

- Successful actions update in place without celebratory alerts.
- Long-running refreshes replace the refresh icon with an inline progress indicator.
- Disabled actions explain why through help text.
- Every status uses icon, text, and colour; never colour alone.

## CTA voice

- Use specific verbs: “Save name”, “Refresh printers”, “Cancel active”.
- Icon-only controls require a visible tooltip and accessibility label.
- Destructive controls use the native destructive role where the context supports it.

## Per-page allowances

- App pages use no enrichment; the live printer state is the content.
- Help and About use the app icon and SF Symbols only.

## What pages MUST share

- Native semantic typography and surfaces.
- Cobalt interaction accent placement.
- Twelve-point card radius and one-point semantic separators.
- Left-aligned page title, factual subtitle, and 24-point page inset.
- VoiceOver labels, keyboard focus, and text-selection support for technical values.

## What pages MAY differ on

- Main app pages use sidebar navigation; Help and About are standalone windows.
- Print Jobs may use a bounded lazy scroll card; Settings uses grouped surface sections.
- Status-heavy screens may use badges, but badges always pair an SF Symbol with text.

## Native token export

The executable token source is `apps/macos/PrinterBridgeApp/Sources/PrinterBridgeDesignSystem.swift`.
CSS, Tailwind, DTCG, and shadcn exports are intentionally omitted because this is a native SwiftUI application and unused web tokens would be misleading.
