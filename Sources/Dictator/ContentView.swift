import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var dictation: DictationController

    var onOpenSettings: () -> Void = {}

    @State private var entryPendingDeletion: TranscriptionEntry?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(RamblrTheme.border)
            historyList
        }
        .background(RamblrTheme.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 560, minHeight: 420)
        .ignoresSafeArea(edges: .top)
        .alert("Delete Transcript?", isPresented: pendingDeletionPresented) {
            Button("Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                if let id = entryPendingDeletion?.id {
                    settings.deleteHistory(id: id)
                }
                entryPendingDeletion = nil
            }
        } message: {
            Text("This can’t be undone.")
        }
    }

    private var pendingDeletionPresented: Binding<Bool> {
        Binding(
            get: { entryPendingDeletion != nil },
            set: { if !$0 { entryPendingDeletion = nil } }
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(RamblrTheme.accent)
                        .frame(width: 28, height: 28)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                }
                Text("Ramblr")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("Press")
                        .foregroundStyle(RamblrTheme.secondaryText)
                    ForEach(Array(settings.shortcut.keycapLabels.enumerated()), id: \.offset) { _, label in
                        KeycapView(label: label)
                    }
                    Text("to start ramblin'")
                        .foregroundStyle(RamblrTheme.secondaryText)
                }
                .font(.system(size: 13))

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(RamblrTheme.elevated, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 38)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var historyList: some View {
        if settings.history.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedHistory, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(RamblrTheme.secondaryText)
                                .padding(.horizontal, 4)

                            ForEach(group.entries) { entry in
                                historyRow(entry)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(RamblrTheme.tertiaryText)
            Text("No ramblings yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 6) {
                Text("Hold")
                ForEach(Array(settings.shortcut.keycapLabels.enumerated()), id: \.offset) { _, label in
                    KeycapView(label: label)
                }
                Text("to start")
            }
            .font(.system(size: 13))
            .foregroundStyle(RamblrTheme.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func historyRow(_ entry: TranscriptionEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(timeLabel(for: entry.createdAt))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(RamblrTheme.secondaryText)
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if entry.kind == .dictateAndSend {
                    Text("Sent")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(RamblrTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
            }

            HStack(spacing: 4) {
                Button {
                    FocusPasteService.copyToClipboard(entry.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RamblrTheme.secondaryText)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Copy")

                Button {
                    entryPendingDeletion = entry
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RamblrTheme.secondaryText)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(14)
        .background(RamblrTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private struct HistoryGroup {
        let title: String
        let entries: [TranscriptionEntry]
    }

    private var groupedHistory: [HistoryGroup] {
        let calendar = Calendar.current
        var buckets: [(String, [TranscriptionEntry])] = []
        var indexByTitle: [String: Int] = [:]

        for entry in settings.history {
            let title = dayTitle(for: entry.createdAt, calendar: calendar)
            if let index = indexByTitle[title] {
                buckets[index].1.append(entry)
            } else {
                indexByTitle[title] = buckets.count
                buckets.append((title, [entry]))
            }
        }

        return buckets.map { HistoryGroup(title: $0.0, entries: $0.1) }
    }

    private func dayTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private func timeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter.string(from: date).lowercased()
    }
}
