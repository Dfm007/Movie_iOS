import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                    .buttonStyle(PressableScaleButtonStyle())
            }
        }
    }
}

struct AppCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = AppTheme.radiusMedium
    let content: Content

    init(
        padding: CGFloat = 16,
        radius: CGFloat = AppTheme.radiusMedium,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppTheme.border.opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: AppTheme.cardShadow, radius: 12, x: 0, y: 5)
    }
}

struct PressableScaleButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(AppTheme.accent)
            )
            .shadow(color: AppTheme.accent.opacity(0.20), radius: 10, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(AppTheme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isSelected ? AppTheme.accent : AppTheme.surface.opacity(0.78))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isSelected ? Color.clear : AppTheme.border.opacity(0.8), lineWidth: 0.5)
                )
                .shadow(
                    color: isSelected ? AppTheme.accent.opacity(0.22) : Color.clear,
                    radius: 7,
                    x: 0,
                    y: 5
                )
        }
        .buttonStyle(PressableScaleButtonStyle())
    }
}

struct AppPill: View {
    let text: String
    var color: Color = AppTheme.accent
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundColor(filled ? .black.opacity(0.82) : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(filled ? color : color.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(filled ? Color.clear : color.opacity(0.28), lineWidth: 0.5)
            )
    }
}

struct RatingBadge: View {
    let rating: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
            Text(rating)
                .font(.caption2.weight(.bold))
        }
        .foregroundColor(.black.opacity(0.82))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(AppTheme.warning))
    }
}

struct PosterArtwork: View {
    let posterURL: String?
    let fallbackTitle: String
    var cornerRadius: CGFloat = AppTheme.radiusMedium

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                posterContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.border.opacity(0.7), lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity)
            .clipped()
    }

    @ViewBuilder
    private var posterContent: some View {
        if let posterURL, let url = URL(string: posterURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder.overlay(ProgressView().tint(AppTheme.accent))
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.surfaceElevated,
                    AppTheme.mutedFill
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                Image(systemName: "film.fill")
                    .font(.title2)
                    .foregroundColor(AppTheme.textSecondary)

                Text(fallbackTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
        }
    }
}

struct MediaCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let rating: String
    let badgeText: String?
    let detailText: String?
    let tagText: String?
    let posterURL: String?
    let destination: () -> Destination

    init(
        title: String,
        subtitle: String,
        rating: String,
        badgeText: String? = nil,
        detailText: String? = nil,
        tagText: String? = nil,
        posterURL: String?,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.rating = rating
        self.badgeText = badgeText
        self.detailText = detailText
        self.tagText = tagText
        self.posterURL = posterURL
        self.destination = destination
    }

    var body: some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 0) {
                PosterArtwork(posterURL: posterURL, fallbackTitle: title, cornerRadius: 17)
                    .frame(maxWidth: .infinity)
                    .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 7)

                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 40, alignment: .topLeading)
                    .padding(.top, 10)

                HStack(spacing: 5) {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)

                    if let badgeText, !badgeText.isEmpty {
                        Text("·")
                            .foregroundColor(AppTheme.textSecondary)
                        Text(badgeText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if !rating.isEmpty && rating != "0.0" {
                        Text("\(rating) 分")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.warning)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleButtonStyle())
    }
}

struct AppSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)

            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textPrimary)
                .textFieldStyle(PlainTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .onSubmit {
                    onSubmit()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(PressableScaleButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                .fill(AppTheme.surface.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                .stroke(AppTheme.border.opacity(0.7), lineWidth: 0.5)
        )
        .shadow(color: AppTheme.cardShadow, radius: 10, x: 0, y: 5)
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(AppTheme.accent)
                .frame(width: 58, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.accentSoft)
                )

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .frame(maxWidth: 200)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 38)
    }
}

struct LoadingStateView: View {
    var title: String = "加载中"

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(AppTheme.accent)
                .scaleEffect(1.08)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MediaRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let rating: String
    let badgeText: String?
    let posterURL: String?
    let destination: () -> Destination

    init(
        title: String,
        subtitle: String,
        rating: String,
        badgeText: String? = nil,
        posterURL: String?,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.rating = rating
        self.badgeText = badgeText
        self.posterURL = posterURL
        self.destination = destination
    }

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                PosterArtwork(posterURL: posterURL, fallbackTitle: title, cornerRadius: 14)
                    .frame(width: 76)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if !rating.isEmpty && rating != "0.0" {
                            RatingBadge(rating: rating)
                        }
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(1)
                    }

                    if let badgeText, !badgeText.isEmpty {
                        AppPill(text: badgeText, color: AppTheme.accentSecondary)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .stroke(AppTheme.border.opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: AppTheme.cardShadow, radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableScaleButtonStyle())
    }
}
