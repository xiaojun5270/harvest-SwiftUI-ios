import SwiftUI
import UIKit

enum HarvestDesignSystem {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let card: CGFloat = 24
        static let capsule: CGFloat = 999
    }

    enum Layout {
        static let pageInset: CGFloat = 16
        static let cardInset: CGFloat = 16
        static let compactCardInset: CGFloat = 11
        static let controlHeight: CGFloat = 44
        static let hairline: CGFloat = 0.75
    }

    enum Motion {
        static let quick = 0.18
        static let standard = 0.25
        static let relaxed = 0.35
    }

    enum Palette {
        static let green = Color(red: 0.18, green: 0.56, blue: 0.36)
        static let coral = Color(red: 0.91, green: 0.36, blue: 0.46)
        static let amber = Color(red: 0.94, green: 0.64, blue: 0.10)
        static let blue = Color(red: 0.20, green: 0.52, blue: 0.87)
        static let teal = Color(red: 0.10, green: 0.62, blue: 0.60)
        static let purple = Color(red: 0.50, green: 0.38, blue: 0.82)
        static let orange = Color(red: 0.95, green: 0.43, blue: 0.18)
        static let indigo = Color(red: 0.31, green: 0.38, blue: 0.78)
        static let siteActivity = Color(red: 0.25, green: 0.53, blue: 0.43)
        static let siteTransfer = Color(red: 0.29, green: 0.47, blue: 0.68)
        static let siteValue = Color(red: 0.70, green: 0.50, blue: 0.20)
        static let siteSecondary = Color(red: 0.45, green: 0.41, blue: 0.62)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let groupedBackground = Color(uiColor: .systemGroupedBackground)
        static let separator = Color.primary.opacity(0.06)
    }
}

// Compatibility namespace used throughout the existing feature views.
enum HarvestTheme {
    static let green = HarvestDesignSystem.Palette.green
    static let coral = HarvestDesignSystem.Palette.coral
    static let amber = HarvestDesignSystem.Palette.amber
    static let blue = HarvestDesignSystem.Palette.blue
    static let teal = HarvestDesignSystem.Palette.teal
    static let purple = HarvestDesignSystem.Palette.purple
    static let orange = HarvestDesignSystem.Palette.orange
    static let indigo = HarvestDesignSystem.Palette.indigo
    static let cardCornerRadius = HarvestDesignSystem.Radius.card
}

enum HarvestCardStyle {
    case standard
    case compact
    case elevated
    case warning(Color)

    var inset: CGFloat {
        switch self {
        case .compact: HarvestDesignSystem.Layout.compactCardInset
        case .standard, .elevated, .warning: HarvestDesignSystem.Layout.cardInset
        }
    }

    var strokeColor: Color {
        switch self {
        case .warning(let color): color.opacity(0.34)
        case .standard, .compact, .elevated: HarvestDesignSystem.Palette.separator
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .elevated: 0.10
        case .standard, .compact, .warning: 0
        }
    }
}

private struct HarvestCardModifier: ViewModifier {
    let style: HarvestCardStyle

    func body(content: Content) -> some View {
        content
            .padding(style.inset)
            .background(
                HarvestDesignSystem.Palette.surface,
                in: RoundedRectangle(
                    cornerRadius: HarvestDesignSystem.Radius.card,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: HarvestDesignSystem.Radius.card,
                    style: .continuous
                )
                .stroke(style.strokeColor, lineWidth: HarvestDesignSystem.Layout.hairline)
            }
            .shadow(
                color: Color.black.opacity(style.shadowOpacity),
                radius: style.shadowOpacity > 0 ? 10 : 0,
                y: style.shadowOpacity > 0 ? 4 : 0
            )
    }
}

private struct HarvestGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.075), lineWidth: HarvestDesignSystem.Layout.hairline)
                }
        }
    }
}

extension View {
    func harvestCard(_ style: HarvestCardStyle = .standard) -> some View {
        modifier(HarvestCardModifier(style: style))
    }

    func harvestGlassSurface(cornerRadius: CGFloat = HarvestDesignSystem.Radius.card) -> some View {
        modifier(HarvestGlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}

struct HarvestSkeletonCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.harvestFlowEffectsPaused) private var flowEffectsPaused
    var rows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: HarvestDesignSystem.Spacing.sm) {
            HStack(spacing: HarvestDesignSystem.Spacing.sm) {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: HarvestDesignSystem.Spacing.xs) {
                    placeholder(width: 132, height: 13)
                    placeholder(width: 84, height: 9)
                }
            }
            ForEach(0..<max(1, rows), id: \.self) { index in
                placeholder(width: index == rows - 1 ? 176 : nil, height: 11)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .harvestCard(.compact)
        .overlay {
            HardwareProgressShimmer(
                color: HarvestTheme.blue,
                paused: reduceMotion || flowEffectsPaused
            )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: HarvestDesignSystem.Radius.card,
                        style: .continuous
                    )
                )
                .opacity(0.42)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入内容")
    }

    private func placeholder(width: CGFloat? = nil, height: CGFloat) -> some View {
        Group {
            if let width {
                Capsule()
                    .fill(Color.primary.opacity(0.075))
                    .frame(width: width, height: height)
            } else {
                Capsule()
                    .fill(Color.primary.opacity(0.075))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
    }
}

struct HarvestSelectionChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = HarvestTheme.blue
    let action: () -> Void

    var body: some View {
        Button {
            HarvestHaptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? color : .secondary)
            .padding(.horizontal, HarvestDesignSystem.Spacing.xs)
            .frame(minHeight: 34)
            .background(
                isSelected ? color.opacity(0.12) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: HarvestDesignSystem.Radius.small, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HarvestDesignSystem.Radius.small, style: .continuous)
                    .stroke(
                        isSelected ? color.opacity(0.30) : Color.primary.opacity(0.06),
                        lineWidth: HarvestDesignSystem.Layout.hairline
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: HarvestDesignSystem.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

@MainActor
enum HarvestHaptics {
    static func notify(_ phase: ManualTaskFeedback.Phase) {
        guard UIApplication.shared.applicationState == .active else { return }
        switch phase {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failure:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .cancelled:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .running:
            break
        }
    }

    static func selection() {
        guard UIApplication.shared.applicationState == .active else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
