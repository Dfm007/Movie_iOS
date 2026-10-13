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
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppTheme.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.accent)
                    .buttonStyle(PressableScaleButtonStyle())
            }
        }
    }
}

struct AppCard<Content: View>: View {
    var padding: CGFloat = 14
    var radius: CGFloat = AppTheme.radiusMedium
    let content: Content

    init(
        padding: CGFloat = 14,
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
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )
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
            .foregroundColor(.black.opacity(0.86))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                    .fill(AppTheme.accent)
            )
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
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .black.opacity(0.86) : AppTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.accent : AppTheme.mutedFill)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : AppTheme.border, lineWidth: 0.5)
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
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundColor(filled ? .black.opacity(0.82) : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(filled ? color : color.opacity(0.14))
            )
            .overlay(
                Capsule()
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
        .background(Capsule().fill(AppTheme.accent))
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
            VStack(alignment: .leading, spacing: 10) {
                PosterArtwork(posterURL: posterURL, fallbackTitle: title)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        if !rating.isEmpty && rating != "0.0" {
                            RatingBadge(rating: rating)
                        }

                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if let badgeText, !badgeText.isEmpty {
                            AppPill(text: badgeText, color: AppTheme.accentSecondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
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
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppTheme.textSecondary)

            TextField(placeholder, text: $text)
                .font(.body)
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
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
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
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)

            Text(title)
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary)

            Text(message)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .frame(maxWidth: 180)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, 34)
    }
}

struct LoadingStateView: View {
    var title: String = "加载中"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.accent)
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
