import SwiftUI

/// Inbox Reference 共享按钮（DESIGN-005）：表面、状态、命中区域与动效集中在这里。
struct MailoButtonStyle: ButtonStyle {
    enum Variant {
        case primary, secondary, ghost, destructive
    }

    var variant: Variant = .ghost
    var accent: Color? = nil
    var isIcon = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(variant: variant, accent: accent, isIcon: isIcon, configuration: configuration)
    }

    struct StyledButton: View {
        let variant: Variant
        let accent: Color?
        let isIcon: Bool
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovered = false
        @FocusState private var focused: Bool

        private var state: DesignTokens.ControlVisualState {
            if !isEnabled { return .disabled }
            if configuration.isPressed { return .pressed }
            if focused { return .focused }
            return hovered ? .hover : .normal
        }

        private var token: DesignTokens.ControlStateToken {
            DesignTokens.controlState(state)
        }

        private var foreground: Color {
            if let accent { return accent }
            switch variant {
            case .primary: return DesignTokens.onAccent
            case .destructive: return DesignTokens.statusDanger
            case .secondary, .ghost: return DesignTokens.inkSecondary
            }
        }

        private var background: Color {
            switch variant {
            case .primary:
                return (accent ?? DesignTokens.brandBlue).opacity(hovered ? 0.90 : 1)
            case .secondary:
                return hovered || configuration.isPressed ? DesignTokens.surfaceHover : DesignTokens.surfaceControl
            case .destructive:
                return hovered || configuration.isPressed ? DesignTokens.statusDanger.opacity(0.14) : Color.clear
            case .ghost:
                return hovered || configuration.isPressed ? DesignTokens.surfaceHover : Color.clear
            }
        }

        private var border: Color {
            if let accent { return accent.opacity(0.45) }
            switch variant {
            case .secondary: return DesignTokens.borderDefault
            case .primary, .ghost: return Color.clear
            case .destructive: return DesignTokens.statusDanger.opacity(0.28)
            }
        }

        private var cornerRadius: CGFloat {
            variant == .primary && !isIcon ? 15 : DesignTokens.radiusButton
        }

        var body: some View {
            configuration.label
                .font(isIcon ? DesignTokens.Typo.iconSmall : DesignTokens.Typo.caption)
                .foregroundColor(foreground)
                .padding(.horizontal, isIcon ? 0 : (variant == .ghost ? 10 : 14))
                .padding(.vertical, isIcon ? 0 : 6)
                .frame(minWidth: isIcon ? 30 : nil, minHeight: isIcon ? 30 : 30)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(token.showsFocusRing ? DesignTokens.brandBlue : border,
                                      lineWidth: token.showsFocusRing ? 2 : 1)
                )
                .opacity(token.opacity)
                .scaleEffect(token.scale)
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.radiusButton))
                .onHover { hovered = $0 }
                .focused($focused)
                .animation(DesignTokens.Motion.animation(duration: DesignTokens.Motion.micro,
                                                         reduceMotion: reduceMotion), value: state)
        }
    }
}

/// 圆形联系人头像（DESIGN-002）：列表与阅读区共用，仅尺寸不同。
struct MailoAvatar: View {
    let address: String?
    let color: Color
    var size: CGFloat = DesignTokens.avatarSize

    var body: some View {
        Group {
            if let image = ReferenceDemoAssets.avatar(for: address) {
                image.resizable().scaledToFill()
            } else {
                Circle()
                    .fill(color.opacity(0.88))
                    .overlay {
                        Text(String((address ?? "?").prefix(1)).uppercased())
                            .font(size <= DesignTokens.avatarSize
                                  ? DesignTokens.Typo.meta.weight(.semibold)
                                  : DesignTokens.Typo.sub)
                            .foregroundColor(DesignTokens.onAccent)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// 上一版用户选定的 m + 圆点品牌标识（DESIGN-001）；侧栏与欢迎页共用。
struct MailoBrandMark: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("m")
                .font(DesignTokens.Typo.iconMedium.weight(.bold))
                .foregroundColor(DesignTokens.accent)
            Circle()
                .fill(DesignTokens.accent)
                .frame(width: 6, height: 6)
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mailo")
    }
}

/// 附件文件名 chip（DESIGN-002）；没有预览能力，因此保持被动、不伪装成按钮。
struct MailoAttachmentChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .font(DesignTokens.Typo.iconTiny)
                .foregroundColor(DesignTokens.brandBlue)
            Text(name)
                .font(DesignTokens.Typo.meta)
                .foregroundColor(DesignTokens.inkSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: DesignTokens.radiusChip).fill(DesignTokens.readerChip))
    }
}

/// 附件 chip 的轻量换行布局（DESIGN-006），不参与邮件内容行为。
struct MailoChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > limit {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            maxWidth = max(maxWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
