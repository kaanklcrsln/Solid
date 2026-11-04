import SwiftUI

enum T {
    static let bg = Color(white: 0.055)
    static let sidebar = Color(white: 0.075)
    static let panel = Color(white: 0.095)
    static let row = Color(white: 0.12)
    static let border = Color(white: 0.20)
    static let text = Color(white: 0.90)
    static let dim = Color(white: 0.55)
    static let faint = Color(white: 0.35)
    static let radius: CGFloat = 5

    static func mono(_ size: CGFloat = 11, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func ui(_ size: CGFloat = 12, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

struct Panel<Content: View>: View {
    var title: String?
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack {
                    Text(title).font(T.mono(10, .semibold)).foregroundColor(T.dim).tracking(1)
                    Spacer()
                    trailing
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                Rectangle().fill(T.border).frame(height: 1)
            }
            content.padding(10)
        }
        .background(T.panel)
        .clipShape(RoundedRectangle(cornerRadius: T.radius))
        .overlay(RoundedRectangle(cornerRadius: T.radius).stroke(T.border, lineWidth: 1))
    }
}

struct SolidButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(T.mono(11, .semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundColor(primary ? .black : T.text)
            .background(primary ? T.text.opacity(c.isPressed ? 0.7 : 1) : (c.isPressed ? T.row : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(primary ? Color.clear : T.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .opacity(enabled ? 1 : 0.35)
    }
}

struct SButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    init(_ title: String, primary: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.primary = primary; self.action = action
    }

    var body: some View {
        Button(action: action) { Text("[ \(title) ]") }.buttonStyle(SolidButtonStyle(primary: primary))
    }
}

struct RiskBadge: View {
    let risk: Risk
    var body: some View {
        Text(risk.label)
            .font(T.mono(9, .bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundColor(risk == .high ? .black : (risk == .protected ? T.faint : T.text))
            .background(risk == .high ? T.text : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(risk == .low ? T.faint : T.border, lineWidth: risk == .medium ? 1 : 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

struct Stat: View {
    let label: String
    let value: String
    var sub: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(T.mono(9, .semibold)).foregroundColor(T.dim).tracking(1)
            Text(value).font(T.mono(15, .semibold)).foregroundColor(T.text)
            if let sub { Text(sub).font(T.mono(9)).foregroundColor(T.faint) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KV: View {
    let k: String
    let v: String
    var body: some View {
        HStack(alignment: .top) {
            Text(k).font(T.mono(10)).foregroundColor(T.dim).frame(width: 120, alignment: .leading)
            Text(v).font(T.mono(10)).foregroundColor(T.text).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

struct Segment: Identifiable {
    let id = UUID()
    let label: String
    let value: Int64
    let shade: Double
}

struct UsageBar: View {
    let segments: [Segment]
    let total: Int64
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 1) {
                ForEach(segments) { s in
                    Rectangle().fill(Color(white: s.shade))
                        .frame(width: max(0, g.size.width * CGFloat(Double(s.value) / Double(max(total, 1))) - 1))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Color(white: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(T.border, lineWidth: 1))
    }
}

struct Legend: View {
    let segments: [Segment]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), alignment: .leading, spacing: 6) {
            ForEach(segments) { s in
                HStack(spacing: 6) {
                    Rectangle().fill(Color(white: s.shade)).frame(width: 9, height: 9)
                        .overlay(Rectangle().stroke(T.border, lineWidth: 0.5))
                    Text(s.label).font(T.mono(10)).foregroundColor(T.dim)
                    Text(Fmt.bytes(s.value)).font(T.mono(10, .semibold)).foregroundColor(T.text)
                }
            }
        }
    }
}

struct Check: View {
    let on: Bool
    var enabled = true
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            Text(on ? "[x]" : "[ ]").font(T.mono(11, .semibold)).foregroundColor(enabled ? T.text : T.faint)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct Note: View {
    let text: String
    var body: some View {
        Text(text).font(T.mono(10)).foregroundColor(T.dim).fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    func solidField() -> some View {
        self.textFieldStyle(.plain)
            .font(T.mono(11))
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(Color(white: 0.07))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(T.border, lineWidth: 1))
    }
}
