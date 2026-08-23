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
                richText(titleSegments: notice.titleSegments, fontSize: 18, fontWeight: .bold)
                    .multilineTextAlignment(.center)

                richText(titleSegments: notice.messageSegments, fontSize: 15, fontWeight: .regular)
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

    private func richText(titleSegments: [NoticeTextSegment], fontSize: CGFloat, fontWeight: Font.Weight) -> Text {
        var combined = Text("")
        for segment in titleSegments {
            if segment.isLineBreak {
                combined = combined + Text("\n")
            } else {
                let part = Text(segment.text)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundColor(segment.color ?? .primary)
                combined = combined + part
            }
        }
        return combined
    }
}