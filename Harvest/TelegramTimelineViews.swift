import SwiftUI

struct TelegramBotHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let bot: TelegramCheckinBot
    let records: [TelegramCheckinHistory]

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView("暂无执行记录", systemImage: "clock.arrow.circlepath")
                } else {
                    List(records) { record in
                        TelegramHistoryCard(record: record)
                            .listRowInsets(
                                EdgeInsets(
                                    top: HarvestDesignSystem.Spacing.xs,
                                    leading: HarvestDesignSystem.Layout.pageInset,
                                    bottom: HarvestDesignSystem.Spacing.xs,
                                    trailing: HarvestDesignSystem.Layout.pageInset
                                )
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(HarvestDesignSystem.Palette.groupedBackground)
                }
            }
            .navigationTitle(bot.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct TelegramHistoryCard: View {
    let record: TelegramCheckinHistory
    @State private var expandedStepIDs: Set<UUID> = []

    private var steps: [TelegramCheckinStep] {
        if let saved = record.steps, !saved.isEmpty { return saved }
        return [
            TelegramCheckinStep(
                kind: .sendCommand,
                status: .success,
                detail: record.command,
                rawPayload: record.command,
                createdAt: record.createdAt
            ),
            TelegramCheckinStep(
                kind: .parseResult,
                status: record.status,
                detail: record.status.label,
                rawPayload: record.response,
                createdAt: record.createdAt
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HarvestDesignSystem.Spacing.md) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    TelegramTimelineStepRow(
                        step: step,
                        isLast: index == steps.count - 1,
                        isExpanded: expandedStepIDs.contains(step.id),
                        onToggle: { toggle(step.id) }
                    )
                }
            }
        }
        .harvestCard(.compact)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HarvestDesignSystem.Spacing.xs) {
            HStack(spacing: HarvestDesignSystem.Spacing.xs) {
                Label(record.status.label, systemImage: record.status.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(record.status.color)
                Spacer(minLength: HarvestDesignSystem.Spacing.xs)
                Text(record.trigger.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(record.status.color.opacity(0.10), in: Capsule())
                    .foregroundStyle(record.status.color)
            }
            HStack(spacing: HarvestDesignSystem.Spacing.xs) {
                Label(
                    record.createdAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "calendar"
                )
                Spacer(minLength: 0)
                Text(String(format: "%.1f 秒 · %d 次", record.duration, record.attemptCount))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func toggle(_ id: UUID) {
        HarvestHaptics.selection()
        withAnimation(.easeInOut(duration: HarvestDesignSystem.Motion.quick)) {
            if expandedStepIDs.contains(id) {
                expandedStepIDs.remove(id)
            } else {
                expandedStepIDs.insert(id)
            }
        }
    }
}

private struct TelegramTimelineStepRow: View {
    let step: TelegramCheckinStep
    let isLast: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    private var hasPayload: Bool {
        !step.rawPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: HarvestDesignSystem.Spacing.sm) {
                timelineMarker
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(step.kind.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        Text(step.status.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(step.status.color)
                        if hasPayload {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if isExpanded, hasPayload {
                        Text(step.rawPayload)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(HarvestDesignSystem.Spacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Color.primary.opacity(0.045),
                                in: RoundedRectangle(
                                    cornerRadius: HarvestDesignSystem.Radius.small,
                                    style: .continuous
                                )
                            )
                    }
                }
                .padding(.bottom, isLast ? 0 : HarvestDesignSystem.Spacing.md)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasPayload)
        .accessibilityLabel("\(step.kind.title)，\(step.status.label)，\(step.detail)")
        .accessibilityHint(hasPayload ? "轻点查看原始返回" : "")
    }

    private var timelineMarker: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(step.status.color.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: step.kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(step.status.color)
            }
            if !isLast {
                Rectangle()
                    .fill(step.status.color.opacity(0.24))
                    .frame(width: 2)
                    .frame(minHeight: isExpanded ? 64 : 30, maxHeight: .infinity)
            }
        }
        .frame(width: 28)
    }
}
