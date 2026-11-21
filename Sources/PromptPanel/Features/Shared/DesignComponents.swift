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

enum PPElevationLevel {
    case popover
    case modal
    case toast

    var ambientRadius: CGFloat {
        switch self {
        case .popover: return 6
        case .modal: return 10
        case .toast: return 6
        }
    }

    var keyRadius: CGFloat {
        switch self {
        case .popover: return 18
        case .modal: return 26
        case .toast: return 16
        }
    }

    var keyYOffset: CGFloat {
        switch self {
        case .popover: return 8
        case .modal: return 12
        case .toast: return 6
        }
    }
}

enum Design {
    static let rowCornerRadius: CGFloat = 6
    static let pillCornerRadius: CGFloat = 999
    static let cardCornerRadius: CGFloat = 10
    static let windowCornerRadius: CGFloat = 12
    static let popoverShadowRadius: CGFloat = 36

    /// Type scale. Six steps, whole points only.
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

    /// Reusable focus-ring container for plain text fields and custom search inputs.
    func focusableInputSurface(
        isFocused: Bool,
        cornerRadius: CGFloat = 6,
        fill: Color = Constants.VisualStyle.inputFill
    ) -> some View {
        modifier(FocusableInputSurfaceModifier(isFocused: isFocused, cornerRadius: cornerRadius, fill: fill))
    }

    /// Native macOS vibrancy material backdrop with dynamic surface tint and hairline border.
    func materialSurface(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .followsWindowActiveState,
        tint: Color = Constants.VisualStyle.surface.opacity(0.68),
        cornerRadius: CGFloat = Design.windowCornerRadius,
        borderColor: Color? = Constants.VisualStyle.borderStrong
    ) -> some View {
        background(
            ZStack {
                VisualEffectMaterialView(material: material, blendingMode: blendingMode, state: state)
                tint
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        )
        .overlay {
            if let borderColor {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: Constants.Layout.hairline)
            }
        }
    }

    /// Two-layer diffuse shadow tuned per appearance so light mode stays crisp and airy.
    func themedShadow(_ level: PPElevationLevel = .popover, cornerRadius: CGFloat = Design.cardCornerRadius) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Constants.VisualStyle.borderStrong, lineWidth: Constants.Layout.hairline)
            )
            .shadow(color: Constants.VisualStyle.shadowAmbient, radius: level.ambientRadius, x: 0, y: 2)
            .shadow(color: Constants.VisualStyle.shadowKey, radius: level.keyRadius, x: 0, y: level.keyYOffset)
    }
}

struct HoverHighlightModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isEnabled: Bool
    private var _isHovered = SwiftUI.State(initialValue: false)

    init(cornerRadius: CGFloat, isEnabled: Bool) {
        self.cornerRadius = cornerRadius
        self.isEnabled = isEnabled
    }

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

struct FocusableInputSurfaceModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    let fill: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? Constants.VisualStyle.accentBorder : Constants.VisualStyle.border,
                        lineWidth: isFocused ? 1 : Constants.Layout.hairline
                    )
            )
    }
}

/// Shared button style providing macOS tactile press feedback (`0.985` scale) and
/// automatic `@Environment(\.isEnabled)` dimming.
struct PPInteractiveButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 6
    var pressedScale: CGFloat = 0.985
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed && isEnabled ? Constants.VisualStyle.tintSubtle : Color.clear)
            )
            .scaleEffect(configuration.isPressed && isEnabled ? pressedScale : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Unified macOS action button primitive covering primary, secondary, ghost, and danger variants
/// across `compact` (24pt) and `regular` (28pt) control heights.
struct PPActionButton: View {
    enum Variant {
        case primary
        case secondary
        case ghost
        case danger
    }

    enum ControlSize {
        case compact
        case regular

        var height: CGFloat {
            switch self {
            case .compact: return Constants.Layout.compactControlHeight
            case .regular: return Constants.Layout.regularControlHeight
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact: return 9
            case .regular: return 11
            }
        }

        var textSize: PPDesign.TextSize {
            switch self {
            case .compact: return .caption
            case .regular: return .body
            }
        }
    }

    let title: String?
    let systemImage: String?
    let shortcut: String?
    let variant: Variant
    let size: ControlSize
    let fillsAvailableWidth: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    private var _isHovered = SwiftUI.State(initialValue: false)

    private var isHovered: Bool {
        get { _isHovered.wrappedValue }
        nonmutating set { _isHovered.wrappedValue = newValue }
    }

    init(
        _ title: String? = nil,
        systemImage: String? = nil,
        shortcut: String? = nil,
        variant: Variant = .secondary,
        size: ControlSize = .compact,
        fillsAvailableWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.variant = variant
        self.size = size
        self.fillsAvailableWidth = fillsAvailableWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.icon(size == .compact ? .small : .base, weight: variant == .primary ? .semibold : .medium))
                }
                if let title {
                    Text(title)
                        .font(.ui(size.textSize, weight: variant == .primary ? .semibold : .medium))
                        .lineLimit(1)
                }
                if let shortcut {
                    Text(shortcut)
                        .font(.ui(.micro, weight: .medium, mono: true))
                        .foregroundStyle(variant == .primary ? Color.white.opacity(0.82) : Constants.VisualStyle.textTertiary)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, title == nil ? 0 : size.horizontalPadding)
            .frame(minWidth: title == nil ? size.height : nil, maxWidth: fillsAvailableWidth ? .infinity : nil)
            .frame(height: size.height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: Constants.Layout.hairline)
            )
            .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 6))
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return .white
        case .secondary: return Constants.VisualStyle.text
        case .ghost: return isHovered && isEnabled ? Constants.VisualStyle.text : Constants.VisualStyle.textSecondary
        case .danger: return Constants.VisualStyle.danger
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary:
            return isHovered && isEnabled
                ? Constants.VisualStyle.accentSolid.opacity(0.9)
                : Constants.VisualStyle.accentSolid
        case .secondary:
            return isHovered && isEnabled
                ? Constants.VisualStyle.surfaceHover
                : Constants.VisualStyle.tintMedium
        case .ghost:
            return isHovered && isEnabled
                ? Constants.VisualStyle.surfaceHover
                : Constants.VisualStyle.tintSubtle
        case .danger:
            return isHovered && isEnabled
                ? Constants.VisualStyle.dangerDim
                : Color.clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary: return .clear
        case .secondary: return Constants.VisualStyle.borderStrong
        case .ghost: return Constants.VisualStyle.border
        case .danger: return Constants.VisualStyle.danger.opacity(0.32)
        }
    }
}

/// Structured cloud sync badge shared by MainWindow header and SettingsView.
enum SyncBadgeState: Equatable {
    case unconfigured
    case syncing
    case autoSynced(revision: Int?)
    case autoPending(pendingCount: Int?)
    case manualIdle(revision: Int?, hasPending: Bool)
    case error(String?)

    var label: String {
        switch self {
        case .unconfigured:
            return "未配置"
        case .syncing:
            return "同步中…"
        case .autoSynced(let revision):
            if let revision, revision > 0 {
                return "自动 · r\(revision)"
            }
            return "自动同步"
        case .autoPending(let count):
            if let count, count > 0 {
                return "待上传 \(count)"
            }
            return "待同步"
        case .manualIdle(let revision, let hasPending):
            if hasPending {
                return "手动 · 待推送"
            }
            if let revision, revision > 0 {
                return "手动 · r\(revision)"
            }
            return "手动模式"
        case .error:
            return "同步异常"
        }
    }

    var systemImage: String {
        switch self {
        case .unconfigured: return "cloud"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .autoSynced: return "checkmark.icloud"
        case .autoPending: return "icloud.and.arrow.up"
        case .manualIdle(_, let hasPending): return hasPending ? "icloud.and.arrow.up" : "icloud"
        case .error: return "exclamationmark.icloud"
        }
    }
}

struct SyncStatusBadge: View {
    let state: SyncBadgeState
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if case .syncing = state {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 11, height: 11)
            } else {
                Circle()
                    .fill(foregroundColor)
                    .frame(width: 5, height: 5)
                if !compact {
                    Image(systemName: state.systemImage)
                        .font(.icon(.micro, weight: .semibold))
                }
            }

            Text(state.label)
                .font(.ui(compact ? .caption : .body, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, compact ? 7 : 8)
        .frame(height: compact ? 22 : Constants.Layout.compactControlHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(borderColor, lineWidth: Constants.Layout.hairline)
        )
    }

    private var foregroundColor: Color {
        switch state {
        case .unconfigured: return Constants.VisualStyle.textTertiary
        case .syncing: return Constants.VisualStyle.accent
        case .autoSynced: return Constants.VisualStyle.success
        case .autoPending: return Constants.VisualStyle.warn
        case .manualIdle(_, let hasPending):
            return hasPending ? Constants.VisualStyle.warn : Constants.VisualStyle.accent
        case .error: return Constants.VisualStyle.danger
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .unconfigured: return Constants.VisualStyle.tintSubtle
        case .syncing: return Constants.VisualStyle.accentDim
        case .autoSynced: return Constants.VisualStyle.successDim
        case .autoPending: return Constants.VisualStyle.warnDim
        case .manualIdle(_, let hasPending):
            return hasPending ? Constants.VisualStyle.warnDim : Constants.VisualStyle.accentDim
        case .error: return Constants.VisualStyle.dangerDim
        }
    }

    private var borderColor: Color {
        switch state {
        case .unconfigured: return Constants.VisualStyle.border
        case .syncing: return Constants.VisualStyle.accentBorder
        case .autoSynced: return Constants.VisualStyle.success.opacity(0.26)
        case .autoPending: return Constants.VisualStyle.warn.opacity(0.28)
        case .manualIdle(_, let hasPending):
            return hasPending ? Constants.VisualStyle.warn.opacity(0.28) : Constants.VisualStyle.accentBorder
        case .error: return Constants.VisualStyle.danger.opacity(0.28)
        }
    }
}

/// Shared, time-bucket cached relative time formatter so dense list rows avoid
/// allocating `Date()` and `RelativeDateTimeFormatter` per row per frame.
enum PPRelativeTimeFormatter {
    private struct CacheKey: Hashable {
        let targetBucket: Int64
        let nowBucket: Int64
        let isCompact: Bool
    }

    private static let lock = NSLock()
    private static var cache: [CacheKey: String] = [:]
    private static let bucketSeconds: TimeInterval = 30
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func compactRecency(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "未用" }
        let key = CacheKey(
            targetBucket: Int64(date.timeIntervalSince1970 / bucketSeconds),
            nowBucket: Int64(now.timeIntervalSince1970 / bucketSeconds),
            isCompact: true
        )
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let days = Int(max(now.timeIntervalSince(date), 0) / 86_400)
        let result: String
        switch days {
        case 0: result = "今天"
        case 1: result = "昨天"
        case 2..<7: result = "\(days)天"
        case 7..<31: result = "\(days / 7)周"
        case 31..<365: result = "\(days / 30)月"
        default: result = "\(days / 365)年"
        }

        store(result, for: key)
        return result
    }

    static func relativeString(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "未使用" }
        let key = CacheKey(
            targetBucket: Int64(date.timeIntervalSince1970 / bucketSeconds),
            nowBucket: Int64(now.timeIntervalSince1970 / bucketSeconds),
            isCompact: false
        )
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        let result = relativeFormatter.localizedString(for: date, relativeTo: now)
        if cache.count > 512 {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = result
        lock.unlock()
        return result
    }

    private static func store(_ value: String, for key: CacheKey) {
        lock.lock()
        if cache.count > 512 {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = value
        lock.unlock()
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
            .hoverHighlight(cornerRadius: 4, isEnabled: !isActive)
            .roundedHitTarget(cornerRadius: 4)
        }
        .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 4))
    }
}

struct SectionHeading: View {
    let text: String

    init(text: String) {
        self.text = text
    }

    init(_ text: String) {
        self.text = text
    }

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
        PPActionButton(
            title,
            systemImage: systemImage,
            shortcut: shortcut,
            variant: .primary,
            size: .regular,
            action: action
        )
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
        PPActionButton(
            title,
            systemImage: systemImage,
            shortcut: shortcut,
            variant: tone == .danger ? .danger : .secondary,
            size: .regular,
            action: action
        )
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
                .hoverHighlight(cornerRadius: 6)
                .roundedHitTarget(cornerRadius: 6)
        }
        .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 6))
        .help(help ?? "")
    }
}
