import SwiftUI

struct NoticePopupView: View {
    let notice: Notice
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(spacing: 18) {
                Image(systemName: "megaphone.fill")
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

                Button("知道了") {
                    onDismiss()
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
