import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private enum Pane {
        case general
        case duplicates
    }

    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPane: Pane = .general
    @State private var showDirPicker = false
    @State private var showClearConfirm = false
    @AppStorage("uiScale") private var uiScale = 1.0
    @AppStorage("compactLists") private var compactLists = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.spSubtext)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close settings")
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                paneButton(.general, title: "General", icon: "slider.horizontal.3")
                paneButton(.duplicates, title: "Duplicates", icon: "square.on.square")
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)

            if selectedPane == .general {
                generalSettings
            } else {
                DuplicateCleanerView()
            }
        }
        .frame(width: 640, height: 640)
        .background(Color.spBackground)
    }

    private func paneButton(_ pane: Pane, title: String, icon: String) -> some View {
        Button { selectedPane = pane } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: selectedPane == pane ? .semibold : .medium))
                .foregroundColor(selectedPane == pane ? .white : .spSubtext)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedPane == pane ? Color.spCard : Color.clear)
                }
        }
        .buttonStyle(.plain)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            // MARK: Playback

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("PLAYBACK")

                HStack {
                    Text("Crossfade")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    Spacer()
                    Text(player.crossfadeDuration < 0.5 ? "Off" : "\(Int(player.crossfadeDuration)) s")
                        .font(.system(size: 12))
                        .foregroundColor(.spSubtext)
                        .frame(width: 36, alignment: .trailing)
                }
                Slider(value: $player.crossfadeDuration, in: 0...12, step: 1)
                Text("Smoothly blends the end of one track into the next.")
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
            }

            Divider().background(Color.white.opacity(0.1))

            Toggle("Compact track lists", isOn: $compactLists)
                .font(.system(size: 13))

            Divider().background(Color.white.opacity(0.1))

            // MARK: Zoom

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("ZOOM LEVEL")

                HStack {
                    Text("Interface scale")
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int((uiScale * 100).rounded()))%")
                        .font(.system(size: 12))
                        .foregroundColor(.spSubtext)
                        .frame(width: 44, alignment: .trailing)
                    Button("Reset") { uiScale = 1.0 }
                        .controlSize(.small)
                        .disabled(abs(uiScale - 1.0) < 0.01)
                }
                Slider(value: $uiScale, in: 0.7...1.3, step: 0.1)
                Text("Also ⌘+ / ⌘− / ⌘0 anywhere in the app.")
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
            }

            Divider().background(Color.white.opacity(0.1))

            // MARK: Offline cache

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("OFFLINE CACHE")

                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundColor(.spSubtext)
                    Text(downloads.cacheDirectory.path)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change…") { showDirPicker = true }
                        .controlSize(.small)
                }

                HStack {
                    Text("Size: \(formatBytes(downloads.cacheSizeBytes)) • \(downloads.cachedFiles.count) tracks")
                        .font(.system(size: 12))
                        .foregroundColor(.spSubtext)
                    Spacer()
                    Button("Clear Cache", role: .destructive) {
                        showClearConfirm = true
                    }
                    .controlSize(.small)
                    .disabled(downloads.cachedFiles.isEmpty)
                }

                DownloadProgressView()

                if let error = downloads.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }

                Text("Downloaded playlists play from disk and survive being offline. Changing the folder doesn't move existing files.")
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.spBackground)
        .fileImporter(isPresented: $showDirPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                downloads.setCacheDirectory(url)
            }
        }
        .confirmationDialog("Delete all downloaded tracks?", isPresented: $showClearConfirm) {
            Button("Clear Cache", role: .destructive) { downloads.clearCache() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { downloads.refresh() }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.3)
            .foregroundColor(.spSubtext)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
