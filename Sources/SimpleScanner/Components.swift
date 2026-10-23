import SwiftUI

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    init(_ title: String) {
        self.title = title
        self.trailing = nil
    }

    init<V: View>(_ title: String, @ViewBuilder trailing: () -> V) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.textDim.swiftUI)
                .tracking(0.6)
                .textCase(.uppercase)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.bottom, 2)
    }
}

struct FieldRow<Content: View>: View {
    let label: String
    var width: CGFloat = 92
    let content: Content

    init(_ label: String, width: CGFloat = 92, @ViewBuilder content: () -> Content) {
        self.label = label
        self.width = width
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textDim.swiftUI)
                .frame(width: width, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

/// A text field that commits on return or focus loss, in the family's flat style.
struct CommitField: View {
    let value: String
    var placeholder: String = ""
    var monospaced: Bool = false
    var onCommit: (String) -> Void
    /// Called after `onCommit`, on Return only.
    var onSubmit: ((String) -> Void)? = nil

    @State private var text: String
    @FocusState private var focused: Bool

    init(value: String, placeholder: String = "", monospaced: Bool = false, onCommit: @escaping (String) -> Void, onSubmit: ((String) -> Void)? = nil) {
        self.value = value
        self.placeholder = placeholder
        self.monospaced = monospaced
        self.onCommit = onCommit
        self.onSubmit = onSubmit
        self._text = State(initialValue: value)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, design: monospaced ? .monospaced : .default))
            .foregroundStyle(Theme.text.swiftUI)
            .focused($focused)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(focused ? Theme.accent.swiftUI.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .animation(.easeOut(duration: 0.15), value: focused)
            .onAppear { text = value }
            .onChange(of: value) { _, newValue in if !focused { text = newValue } }
            .onSubmit { onCommit(text); onSubmit?(text) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused && text != value { onCommit(text) }
            }
    }
}

struct IconButton: View {
    let symbol: String
    var helpText: String = ""
    var active: Bool = false
    var tint: Color = Theme.accent.swiftUI
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(disabled ? Theme.textFaint.swiftUI : (active ? Theme.background.swiftUI : Theme.text.swiftUI))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? tint : Color.white.opacity(disabled ? 0.02 : (hovering ? 0.1 : 0.06)))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(helpText)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct TextButton: View {
    let title: String
    var symbol: String? = nil
    var prominent: Bool = false
    var destructive: Bool = false
    var compact: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: compact ? 10.5 : 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: compact ? 11 : 11.5, weight: prominent || destructive ? .semibold : .medium))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(
                disabled ? Theme.textFaint.swiftUI
                    : (prominent || destructive ? Theme.background.swiftUI : Theme.text.swiftUI)
            )
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 4 : 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        prominent ? Theme.accent.swiftUI.opacity(disabled ? 0.35 : (hovering ? 0.9 : 1))
                            : destructive ? Theme.danger.swiftUI.opacity(disabled ? 0.35 : (hovering ? 0.9 : 1))
                            : Color.white.opacity(disabled ? 0.02 : (hovering ? 0.11 : 0.07))
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A small rounded tag: a service, a port, a filter.
struct Chip: View {
    let text: String
    var tint: Color = Theme.textDim.swiftUI
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(filled ? Theme.background.swiftUI : tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(filled ? tint : tint.opacity(0.14))
            )
            .lineLimit(1)
    }
}

/// Thin determinate bar with a travelling sheen while work is indeterminate.
struct ScanProgressBar: View {
    let fraction: Double
    let active: Bool
    let indeterminate: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(active ? 0.05 : 0))
                Rectangle()
                    .fill(Theme.accent.swiftUI)
                    .frame(width: max(0, width * (active ? fraction : 0)))
                    .animation(.linear(duration: 0.25), value: fraction)
                if active && indeterminate {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        LinearGradient(colors: [.clear, Theme.text.swiftUI.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 140)
                            .offset(x: -140 + (width + 140) * t)
                    }
                }
            }
        }
        .frame(height: 2)
        .opacity(active ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: active)
    }
}

/// Concentric rings with a sweeping beam: the empty state while scanning, breathing when idle.
struct RadarView: View {
    let active: Bool
    var size: CGFloat = 120

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = Angle(degrees: (t * 120).truncatingRemainder(dividingBy: 360))
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .strokeBorder(Theme.accent.swiftUI.opacity(0.10 + 0.08 * Double(2 - ring)), lineWidth: 1)
                        .frame(width: size * CGFloat(ring + 1) / 3, height: size * CGFloat(ring + 1) / 3)
                }
                Path { p in
                    p.move(to: CGPoint(x: size / 2, y: 0)); p.addLine(to: CGPoint(x: size / 2, y: size))
                    p.move(to: CGPoint(x: 0, y: size / 2)); p.addLine(to: CGPoint(x: size, y: size / 2))
                }
                .stroke(Theme.accent.swiftUI.opacity(0.08), lineWidth: 1)
                .frame(width: size, height: size)
                if active {
                    AngularGradient(colors: [Theme.accent.swiftUI.opacity(0), Theme.accent.swiftUI.opacity(0.55)], center: .center, startAngle: .degrees(-90), endAngle: .degrees(0))
                        .mask(Circle())
                        .frame(width: size, height: size)
                        .rotationEffect(angle)
                }
                Circle()
                    .fill(Theme.accent.swiftUI)
                    .frame(width: 6, height: 6)
                    .shadow(color: Theme.accent.swiftUI.opacity(0.8), radius: active ? 6 : 2)
            }
            .frame(width: size, height: size)
        }
    }
}

/// Minimal line chart of recent samples; gaps mark lost pings.
struct Sparkline: View {
    let samples: [Double?]
    var tint: Color = Theme.alive.swiftUI
    var capacity: Int = 60

    var body: some View {
        Canvas { ctx, size in
            let values = samples.compactMap { $0 }
            let top = max(values.max() ?? 1, 1)
            let stepX = size.width / CGFloat(max(capacity - 1, 1))
            let start = capacity - samples.count
            var path = Path()
            var pen = false
            for (i, sample) in samples.enumerated() {
                let x = CGFloat(start + i) * stepX
                guard let sample else { pen = false; continue }
                let y = size.height - CGFloat(sample / top) * (size.height - 3) - 1.5
                if pen { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)) }
                pen = true
            }
            ctx.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            for (i, sample) in samples.enumerated() where sample == nil {
                let x = CGFloat(start + i) * stepX
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: size.height - 3, width: 3, height: 3)), with: .color(Theme.danger.swiftUI))
            }
        }
    }
}

extension View {
    /// Hidden `List` chrome: flat rows on the family's dark background.
    func flatListRow(background: Color) -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(background)
    }
}
