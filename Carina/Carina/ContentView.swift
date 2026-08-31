//
//  ContentView.swift
//  Carina
//
//  Created by dinosaur on 8/9/26.
//

import SwiftUI

struct ContentView: View {
    @State private var command = ""
    @State private var selectedSection: CommandSection = .cockpit

    private let quickActions = [
        QuickAction(title: "Ask Maya", subtitle: "Reason and plan", icon: "sparkles"),
        QuickAction(title: "System Status", subtitle: "Check CARINA", icon: "waveform.path.ecg"),
        QuickAction(title: "Playground", subtitle: "Open workspace", icon: "square.grid.2x2"),
        QuickAction(title: "Engineering", subtitle: "Send to Codex", icon: "hammer")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.04, green: 0.07, blue: 0.12),
                        Color(red: 0.05, green: 0.10, blue: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        header
                        statusCard
                        sectionPicker
                        quickActionGrid
                        recentActivity
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 130)
                }
            }
            .safeAreaInset(edge: .bottom) {
                commandComposer
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 52, height: 52)

                Image(systemName: "star.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("CARINA")
                    .font(.title2.weight(.bold))
                Text("Command Center")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label("CARINA READY", systemImage: "checkmark.seal.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.green)

                    Text("Systems are standing by for your next command.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(.green.opacity(0.2), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: 0.92)
                        .stroke(.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("92")
                        .font(.caption.weight(.bold))
                }
                .frame(width: 54, height: 54)
                .accessibilityLabel("System health 92 percent")
            }

            Divider().overlay(.white.opacity(0.08))

            HStack(spacing: 0) {
                Metric(title: "Bridge", value: "Online", icon: "link")
                Divider().frame(height: 34)
                Metric(title: "Policy", value: "Guarded", icon: "lock.shield")
                Divider().frame(height: 34)
                Metric(title: "Local AI", value: "Ready", icon: "cpu")
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CommandSection.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = section
                        }
                    } label: {
                        Label(section.title, systemImage: section.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(
                                selectedSection == section
                                    ? Color.cyan.opacity(0.22)
                                    : Color.white.opacity(0.06),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        selectedSection == section
                                            ? Color.cyan.opacity(0.55)
                                            : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var quickActionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(quickActions) { action in
                    Button(action: {}) {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: action.icon)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.cyan)
                                .frame(width: 42, height: 42)
                                .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(action.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(action.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
                        .padding(15)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                Button("View All") {}
                    .font(.caption.weight(.semibold))
            }

            VStack(spacing: 0) {
                ActivityRow(
                    icon: "checkmark.shield.fill",
                    title: "Approval boundary",
                    detail: "Validation rules loaded",
                    time: "Now"
                )
                Divider().padding(.leading, 52)
                ActivityRow(
                    icon: "hammer.fill",
                    title: "Engineering",
                    detail: "Recovery tests prepared",
                    time: "Recent"
                )
                Divider().padding(.leading, 52)
                ActivityRow(
                    icon: "iphone",
                    title: "iPhone link",
                    detail: "Device surface available",
                    time: "Recent"
                )
            }
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private var commandComposer: some View {
        VStack(spacing: 0) {
            Divider().overlay(.white.opacity(0.08))

            HStack(spacing: 10) {
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add attachment")

                TextField("Tell CARINA what you need", text: $command, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button(action: submitCommand) {
                    Image(systemName: command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "waveform" : "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.black)
                        .background(Color.cyan, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(command.isEmpty ? "Voice command" : "Send command")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private func submitCommand() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        command = ""
    }
}

private struct Metric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActivityRow: View {
    let icon: String
    let title: String
    let detail: String
    let time: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.cyan)
                .frame(width: 36, height: 36)
                .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
    }
}

private struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
}

private enum CommandSection: String, CaseIterable, Identifiable {
    case cockpit
    case engineering
    case operations
    case playground

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cockpit: "Cockpit"
        case .engineering: "Engineering"
        case .operations: "Operations"
        case .playground: "Playground"
        }
    }

    var icon: String {
        switch self {
        case .cockpit: "scope"
        case .engineering: "wrench.and.screwdriver"
        case .operations: "shield.lefthalf.filled"
        case .playground: "square.grid.2x2"
        }
    }
}

#Preview {
    ContentView()
}
