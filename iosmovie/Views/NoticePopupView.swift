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

            VStack(spacing: 16) {
                Text(attributedText(from: notice.titleSegments, fontSize: 18, fontWeight: .bold))
                    .multilineTextAlignment(.center)

                Text(attributedText(from: notice.messageSegments, fontSize: 15, fontWeight: .regular))
                    .multilineTextAlignment(.leading)

                Button("知道了") {
                    onDismiss()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(Color.blue)
                .clipShape(Capsule())
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
            )
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