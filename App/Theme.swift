import AppKit
import MergeKit
import SwiftUI

// MARK: - Palette

/// A single, restrained palette: deep ink surfaces under cool glass, one accent that
/// carries "active", and semantic colours that only appear for real state.
enum Palette {
    static let accent = Color(red: 0.36, green: 0.55, blue: 1.00)
    static let accentDeep = Color(red: 0.24, green: 0.36, blue: 0.95)
    static let mint = Color(red: 0.30, green: 0.86, blue: 0.66)
    static let amber = Color(red: 1.00, green: 0.72, blue: 0.32)
    static let rose = Color(red: 1.00, green: 0.42, blue: 0.52)
    static let violet = Color(red: 0.68, green: 0.48, blue: 1.00)
    static let cyan = Color(red: 0.34, green: 0.82, blue: 0.96)

    static func forKind(_ kind: LinkKind) -> Color {
        switch kind {
        case .wifi: return accent
        case .wired: return mint
        case .cellular: return amber
        case .other: return violet
        }
    }

    static func forStatus(_ status: DownloadStatus) -> Color {
        switch status {
        case .completed: return mint
        case .downloading: return accent
        case .paused: return amber
        case .probing: return cyan
        case .queued: return .secondary
        case .failed: return rose
        }
    }
}

// MARK: - Motion

/// Shared springs. One vocabulary everywhere beats ad-hoc durations.
enum Motion {
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.9)
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.72)
    static let fade = Animation.easeOut(duration: 0.22)
    static let morph = Animation.spring(response: 0.45, dampingFraction: 0.82)
}

// MARK: - Glass surfaces

/// A layered glass panel.
///
/// Built from system material plus a specular gradient border, an inner top highlight and
/// a soft shadow. This deliberately avoids `.glassEffect` so one surface definition renders
/// identically from the macOS 14 deployment target through macOS 27, instead of splitting the
/// app into two visual languages. The mesh backdrop behind it supplies the colour the glass
/// refracts.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 20
    var tint: Color = .clear
    var tintStrength: Double = 0
    var isElevated: Bool = true
    var strokeOpacity: Double = 0.14

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.02),
                                Color.black.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    if tintStrength > 0 {
                        shape.fill(tint.opacity(tintStrength))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(strokeOpacity * 1.6),
                            Color.white.opacity(strokeOpacity * 0.5),
                            Color.white.opacity(strokeOpacity * 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .overlay {
                // Inner top highlight: the "glass edge" that sells the material.
                shape
                    .inset(by: 0.5)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                    .blur(radius: 0.4)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
            .shadow(
                color: Color.black.opacity(isElevated ? 0.30 : 0.12),
                radius: isElevated ? 22 : 8,
                y: isElevated ? 12 : 3
            )
            .clipShape(shape)
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat = 20,
        tint: Color = .clear,
        tintStrength: Double = 0,
        elevated: Bool = true,
        strokeOpacity: Double = 0.14
    ) -> some View {
        modifier(
            GlassSurface(
                cornerRadius: cornerRadius,
                tint: tint,
                tintStrength: tintStrength,
                isElevated: elevated,
                strokeOpacity: strokeOpacity
            )
        )
    }

    /// Subtle pointer-follow lift used on interactive cards.
    func hoverLift(scale: CGFloat = 1.006, lift: CGFloat = 3) -> some View {
        modifier(HoverLift(scale: scale, lift: lift))
    }

    /// Staggered entrance used for page content.
    func appear(_ index: Int, _ appeared: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(Motion.gentle.delay(Double(index) * 0.05), value: appeared)
    }

    /// A text style for dense uppercase metadata.
    func microLabel(_ color: Color = .secondary) -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

private struct HoverLift: ViewModifier {
    var scale: CGFloat
    var lift: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .offset(y: hovering ? -lift : 0)
            .animation(Motion.snappy, value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Backdrop

/// The colour field behind every window. Slow, cheap, and static enough not to distract.
struct AuroraBackdrop: View {
    var isActive: Bool

    var body: some View {
        ZStack {
            Color(red: 0.047, green: 0.055, blue: 0.086)

            if #available(macOS 15.0, *) {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        .init(0, 0), .init(0.5, 0), .init(1, 0),
                        .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                        .init(0, 1), .init(0.5, 1), .init(1, 1)
                    ],
                    colors: meshColors
                )
                .opacity(0.95)
                .animation(Motion.gentle, value: isActive)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.06, blue: 0.10),
                        Color(red: 0.08, green: 0.10, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Vignette keeps the eye in the centre of the window.
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.45)],
                center: .center,
                startRadius: 240,
                endRadius: 820
            )
        }
        .ignoresSafeArea()
    }

    private var meshColors: [Color] {
        if isActive {
            return [
                Color(red: 0.06, green: 0.07, blue: 0.12),
                Color(red: 0.10, green: 0.13, blue: 0.26),
                Color(red: 0.07, green: 0.09, blue: 0.16),
                Color(red: 0.13, green: 0.16, blue: 0.34),
                Color(red: 0.16, green: 0.20, blue: 0.42),
                Color(red: 0.09, green: 0.12, blue: 0.24),
                Color(red: 0.05, green: 0.07, blue: 0.12),
                Color(red: 0.10, green: 0.14, blue: 0.28),
                Color(red: 0.06, green: 0.08, blue: 0.14)
            ]
        }
        return [
            Color(red: 0.05, green: 0.06, blue: 0.09),
            Color(red: 0.07, green: 0.08, blue: 0.13),
            Color(red: 0.05, green: 0.06, blue: 0.10),
            Color(red: 0.07, green: 0.08, blue: 0.14),
            Color(red: 0.09, green: 0.10, blue: 0.18),
            Color(red: 0.06, green: 0.07, blue: 0.12),
            Color(red: 0.04, green: 0.05, blue: 0.08),
            Color(red: 0.06, green: 0.07, blue: 0.12),
            Color(red: 0.05, green: 0.06, blue: 0.10)
        ]
    }
}

// MARK: - Buttons

/// Quiet glass button: material, hairline, press compression.
struct GlassButtonStyle: ButtonStyle {
    var tint: Color = .white
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(isProminent ? Color.white : Color.primary.opacity(0.9))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isProminent
                            ? AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(.ultraThinMaterial)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isProminent ? 0.28 : 0.14), lineWidth: 0.8)
            }
            .shadow(color: isProminent ? tint.opacity(0.35) : .clear, radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Circular icon action used in toolbars and rows.
struct IconActionStyle: ButtonStyle {
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint.opacity(0.92))
            .frame(width: 28, height: 28)
            .background {
                Circle().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.07))
            }
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Small components

/// Uppercase capsule used for state, e.g. STACKED / NOTICE.
struct StatusPill: View {
    var text: String
    var color: Color
    var showsDot: Bool = true
    var pulsing: Bool = false

    @State private var phase: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Circle()
                    .fill(color)
                    .frame(width: 5.5, height: 5.5)
                    .overlay {
                        if pulsing {
                            Circle()
                                .stroke(color.opacity(phase ? 0 : 0.65), lineWidth: 1.2)
                                .scaleEffect(phase ? 2.4 : 1)
                                .opacity(phase ? 0 : 1)
                                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: phase)
                        }
                    }
            }
            Text(text.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.24), lineWidth: 0.6))
        .onAppear { phase = true }
    }
}

/// A metric with a label and a large animated value.
struct MetricBlock: View {
    var label: String
    var value: String
    var caption: String?
    var icon: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label).microLabel()
            }

            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)

            if let caption {
                Text(caption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Section title + trailing control, used to open every card consistently.
struct CardHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var icon: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, icon: String? = nil) {
        self.init(title: title, subtitle: subtitle, icon: icon) { EmptyView() }
    }
}

/// Smooth, gradient-filled sparkline with an optional second series.
struct Sparkline: View {
    var values: [Double]
    var secondary: [Double] = []
    var tint: Color = Palette.accent
    var secondaryTint: Color = Palette.mint
    var lineWidth: CGFloat = 1.8
    var fills: Bool = true

    var body: some View {
        GeometryReader { geo in
            let primary = normalized(values)
            let second = normalized(secondary)
            let maxValue = max(1, values.max() ?? 1, secondary.max() ?? 0)

            ZStack {
                if fills {
                    areaPath(primary, in: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.42), tint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                if !secondary.isEmpty {
                    smoothed(second, in: geo.size)
                        .stroke(secondaryTint.opacity(0.75), style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round, lineJoin: .round))
                }

                smoothed(primary, in: geo.size)
                    .stroke(
                        LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: tint.opacity(0.55), radius: 6)
            }
            .animation(Motion.fade, value: maxValue)
        }
    }

    private func normalized(_ series: [Double]) -> [Double] {
        guard !series.isEmpty else { return [] }
        let peak = max(series.max() ?? 1, 1)
        return series.map { max(0, min(1, $0 / peak)) }
    }

    private func points(_ series: [Double], in size: CGSize) -> [CGPoint] {
        guard series.count > 1 else { return [] }
        let stepX = size.width / CGFloat(series.count - 1)
        return series.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * stepX, y: size.height * (1 - value) * 0.92 + 2)
        }
    }

    private func smoothed(_ series: [Double], in size: CGSize) -> Path {
        let pts = points(series, in: size)
        guard pts.count > 1 else { return Path() }

        var path = Path()
        path.move(to: pts[0])
        for index in 1..<pts.count {
            let previous = pts[index - 1]
            let current = pts[index]
            let midX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: current.y)
            )
        }
        return path
    }

    private func areaPath(_ series: [Double], in size: CGSize) -> Path {
        let line = smoothed(series, in: size)
        var area = line
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()
        return area
    }
}

/// Thin capacity bar used for adapter share and progress.
struct MeterBar: View {
    var fraction: Double
    var tint: Color
    var height: CGFloat = 4
    var animated: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * CGFloat(max(0, min(1, fraction)))))
                    .animation(animated ? Motion.gentle : nil, value: fraction)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Window chrome

/// Makes the hosting window borderless enough to let the backdrop show through while
/// keeping the traffic lights and native resizing.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.toolbarStyle = .unifiedCompact
    }
}
