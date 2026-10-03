//
//  SharedComponents.swift
//  PocketSync
//

import SwiftUI

struct Y2KPanel<Content: View>: View {
    let title: String
    let tint: Color
    var searchAction: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(PocketStyle.text)

                Spacer()

                if let searchAction {
                    Button(action: searchAction) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(PocketStyle.border)
                    }
                    .buttonStyle(.plain)
                    .help("Search videos")
                    .accessibilityLabel("Search videos")
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PocketStyle.border)
                }
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: PocketStyle.panelCorner, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: PocketStyle.panelCorner, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: PocketStyle.thinLine)
                )
        )
        .shadow(color: tint.opacity(0.20), radius: 8, x: 0, y: 6)
    }
}

struct CuteActionButton: View {
    let title: String
    let icon: String
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .black))

                Text(title)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundStyle(PocketStyle.text)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 76)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: PocketStyle.buttonCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.64), fill.opacity(0.88)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PocketStyle.buttonCorner, style: .continuous)
                            .stroke(Color.white.opacity(0.82), lineWidth: PocketStyle.borderWidth)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct CuteGhostButton: View {
    let title: String
    let icon: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .black))

                Text(title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(PocketStyle.text)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: PocketStyle.buttonCorner, style: .continuous)
                    .fill(Color.white.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: PocketStyle.buttonCorner, style: .continuous)
                            .stroke(PocketStyle.border.opacity(0.36), lineWidth: PocketStyle.borderWidth)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct MiniButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(PocketStyle.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: PocketStyle.buttonCorner, style: .continuous)
                        .fill(Color.white.opacity(0.66))
                        .overlay(
                            RoundedRectangle(cornerRadius: PocketStyle.buttonCorner, style: .continuous)
                                .stroke(PocketStyle.border.opacity(0.35), lineWidth: PocketStyle.thinLine)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

struct Pill: View {
    let title: String
    let fill: Color

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .tracking(1.0)
            .foregroundStyle(PocketStyle.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: PocketStyle.buttonCorner, style: .continuous)
                    .fill(fill.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: PocketStyle.buttonCorner, style: .continuous)
                            .stroke(Color.white.opacity(0.8), lineWidth: PocketStyle.thinLine)
                    )
            )
    }
}

struct MediaChip: View {
    let label: String
    let active: Bool

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(active ? PocketStyle.text : PocketStyle.mutedText.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? PocketStyle.mint.opacity(0.72) : Color.white.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(PocketStyle.border.opacity(active ? 0.35 : 0.18), lineWidth: PocketStyle.thinLine)
                    )
            )
    }
}
