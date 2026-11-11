import AppKit
import SwiftUI

/// Native macOS NSVisualEffectView bridge for sidebars, HUD panels, and popovers.
struct VisualEffectMaterialView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

enum Design {
    static let rowCornerRadius: CGFloat = 6
    static let pillCornerRadius: CGFloat = 999
    static let cardCornerRadius: CGFloat = 10
    static let windowCornerRadius: CGFloat = 12
    static let popoverShadowRadius: CGFloat = 36

    /// Type scale. Six steps, whole points only.
    ///
    /// Half-point sizes and a dozen near-identical steps used to be scattered
    /// across the views; they cost legibility (9pt labels) without buying any
    /// hierarchy. Everything now snaps to one of these, so density comes from
    /// tighter spacing rather than from shrinking text.
    enum TextSize: CGFloat {
        /// Counters, keycaps, badge text. Almost always monospaced.
        case micro = 10
        /// Meta lines, hints, section headings.
        case caption = 11
        /// Default UI text: labels, buttons, secondary copy.
        case body = 12
        /// Row titles and editable content.
        case title = 13
        /// Sheet headers.
        case heading = 15
        /// The preview pane's entry title — the one place that needs to shout.
        case display = 18
    }

    /// Glyph scale for SF Symbols, deliberately one step finer than the type
    /// scale because symbols read larger than text at the same point size.
    enum IconSize: CGFloat {
        /// Ultra-compact chevrons.
        case nano = 8
        /// Chevrons and inline pin markers.
        case micro = 9
        case small = 11
        case base = 12
        /// Empty-state glyph inside a list column.
        case large = 16
        /// Empty-state glyph for a full pane.
        case hero = 22
    }

    /// Vertical/horizontal spacing scale. 2pt grid.
    enum Space {
        static let hairline: CGFloat = 0.5
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 14
    }
}

/// `Font.Design` shadows the app's `Design` enum inside `extension Font`,
/// so the scales are reached through this alias.
typealias PPDesign = Design

extension Font {
    /// Text in the PromptPanel type scale. Prefer this over raw point sizes.
    static func ui(_ size: PPDesign.TextSize, weight: Font.Weight = .regular, mono: Bool = false) -> Font {
        .system(size: size.rawValue, weight: weight, design: mono ? .monospaced : .default)
    }

    /// SF Symbol glyph in the PromptPanel icon scale.
    static func icon(_ size: PPDesign.IconSize, weight: Font.Weight = .medium) -> Font {
        .system(size: size.rawValue, weight: weight)
    }
}

extension View {
    func fullHitTarget() -> some View {
        contentShape(Rectangle())
    }

    func roundedHitTarget(cornerRadius: CGFloat) -> some View {
        contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Subtle macOS pointer hover surface feedback without stealing clicks or focus.
    func hoverHighlight(cornerRadius: CGFloat = 6, isEnabled: Bool = true) -> some View {
        modifier(HoverHighlightModifier(cornerRadius: cornerRadius, isEnabled: isEnabled))
    }
}

struct HoverHighlightModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isEnabled: Bool
    private var _isHovered = SwiftUI.State(initialValue: false)

    private var isHovered: Bool {
        get { _isHovered.wrappedValue }
        nonmutating set { _isHovered.wrappedValue = newValue }
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered && isEnabled ? Constants.VisualStyle.surfaceHover : Color.clear)
            )
            .onHover { hovering in
                if isHovered != hovering {
                    isHovered = hovering
                }
            }
    }
}

struct KbdLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ui(.micro, weight: .medium, mono: true))
            .foregroundStyle(Constants.VisualStyle.textSecondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Constants.VisualStyle.tintSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Constants.VisualStyle.border, lineWidth: Constants.Layout.hairline)
            )
    }
}

struct FilterChip: View {
    let label: String
    let systemImage: String?
    let count: Int?
    let isActive: Bool
    let action: () -> Void

    init(
        label: String,
        systemImage: String? = nil,
        count: Int? = nil,
        isActive: Bool,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.count = count
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.icon(.small))
                }
                Text(label)
                    .font(.ui(.caption, weight: .medium))
                if let count {
                    Text("\(count)")
                        .font(.ui(.micro, weight: .medium, mono: true))
                        .opacity(0.8)
                }
            }
            .padding(.horizontal, Design.Space.sm)
            .frame(height: Constants.Layout.compactControlHeight - 2)
            .foregroundStyle(isActive ? Constants.VisualStyle.accent : Constants.VisualStyle.textTertiary)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? Constants.VisualStyle.accentDim : Color.clear)
            )
            .roundedHitTarget(cornerRadius: 4)
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.ui(.caption, weight: .semibold))
            .tracking(0.2)
            .foregroundStyle(Constants.VisualStyle.textTertiary)
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String?
    let shortcut: String?
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.icon(.small, weight: .semibold))
                }
                Text(title)
                    .font(.ui(.body, weight: .semibold))
                if let shortcut {
                    Text(shortcut)
                        .font(.ui(.micro, weight: .medium, mono: true))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Design.Space.lg)
            .frame(height: Constants.Layout.regularControlHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Constants.VisualStyle.accent)
            )
            .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(.plain)
    }
}

struct GhostActionButton: View {
    let title: String
    let systemImage: String?
    let shortcut: String?
    let tone: Tone
    let action: () -> Void

    enum Tone {
        case neutral
        case danger
    }

    init(
        title: String,
        systemImage: String? = nil,
        shortcut: String? = nil,
        tone: Tone = .neutral,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.tone = tone
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.icon(.small))
                }
                Text(title)
                    .font(.ui(.body, weight: .medium))
                if let shortcut {
                    Text(shortcut)
                        .font(.ui(.micro, weight: .medium, mono: true))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Design.Space.lg)
            .frame(height: Constants.Layout.regularControlHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Constants.VisualStyle.tintMedium)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: Constants.Layout.hairline)
            )
            .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Constants.VisualStyle.text
        case .danger: return Constants.VisualStyle.danger
        }
    }

    private var strokeColor: Color {
        switch tone {
        case .neutral: return Constants.VisualStyle.border
        case .danger: return Constants.VisualStyle.danger.opacity(0.3)
        }
    }
}

struct QuietIconButton: View {
    let systemImage: String
    let tint: Color?
    let help: String?
    let action: () -> Void

    init(systemImage: String, tint: Color? = nil, help: String? = nil, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.tint = tint
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.icon(.base))
                .foregroundStyle(tint ?? Constants.VisualStyle.textTertiary)
                .frame(width: Constants.Layout.compactControlHeight, height: Constants.Layout.compactControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.clear)
                )
                .roundedHitTarget(cornerRadius: 5)
        }
        .buttonStyle(.plain)
        .help(help ?? "")
    }
}
