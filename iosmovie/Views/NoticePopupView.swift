import SwiftUI

struct NoticePopupView: View {
    let notice: Notice
    /// 顶部图标（公告用 megaphone，更新提示用 arrow.down.circle.fill）
    var icon: String = "megaphone.fill"
    /// 主按钮标题
    var primaryTitle: String = "知道了"
    /// 主按钮动作；为 nil 时等同关闭
    var onPrimary: (() -> Void)? = nil
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black.opacity(0.82))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(AppTheme.accent))

                Text(attributedText(from: notice.titleSegments, fontSize: 18, fontWeight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.textPrimary)

                Text(attributedText(from: notice.messageSegments, fontSize: 15, fontWeight: .regular))
                    .multilineTextAlignment(.leading)
                    .foregroundColor(AppTheme.textSecondary)
                    .lineSpacing(4)

                Button(primaryTitle) {
                    if let onPrimary = onPrimary {
                        onPrimary()
                    } else {
                        onDismiss()
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
            .padding(24)
            .frame(maxWidth: 330)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusLarge, style: .continuous)
                    .fill(AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLarge, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 12)
        }
    }

    private func attributedText(from segments: [NoticeTextSegment], fontSize: CGFloat, fontWeight: Font.Weight) -> AttributedString {
        var result = AttributedString()

        for segment in segments {
            if segment.isLineBreak {
                result += AttributedString("\n")
                continue
            }

            var part = AttributedString(segment.text)
            part.font = .system(size: fontSize, weight: fontWeight)

            if let color = segment.color {
                part.foregroundColor = color
            } else {
                part.foregroundColor = .primary
            }

            result += part
        }

        return result
    }
}
