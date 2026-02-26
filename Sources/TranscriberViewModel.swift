import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class TranscriberViewModel: ObservableObject {
    enum InputMode: String, CaseIterable, Identifiable {
        case localFile
        case instagramLink

        var id: String { rawValue }

        var title: String {
            switch self {
            case .localFile:
                return "Local File"
            case .instagramLink:
                return "Instagram Link"
            }
        }
    }

    @Published var inputMode: InputMode = .localFile
    @Published var selectedFileURL: URL?
    @Published var videoLinkText = ""
    @Published var transcript = ""
    @Published var isTranscribing = false
    @Published var statusMessage = ""
    @Published var statusIsError = false

    private let transcriber = VideoTranscriptionService()
    private let downloader = VideoDownloadService()

    var canStartTranscription: Bool {
        switch inputMode {
        case .localFile:
            return selectedFileURL != nil
        case .instagramLink:
            return !videoLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func handleVideoImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedFileURL = urls.first
            status("Ready to transcribe \(selectedFileURL?.lastPathComponent ?? "video").")
        case .failure(let error):
            fail("Could not open file: \(error.localizedDescription)")
        }
    }

    func transcribeCurrentInput() async {
        isTranscribing = true
        transcript = ""
        defer { isTranscribing = false }

        do {
            switch inputMode {
            case .localFile:
                try await transcribeFromLocalFile()
            case .instagramLink:
                try await transcribeFromLink()
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    func copyTranscriptToClipboard() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        status("Transcript copied to clipboard.")
    }

    func saveTranscript() {
        guard !transcript.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedTranscriptFilename()

        if panel.runModal() == .OK, let destination = panel.url {
            do {
                try transcript.write(to: destination, atomically: true, encoding: .utf8)
                status("Saved transcript to \(destination.path).")
            } catch {
                fail("Failed to save transcript: \(error.localizedDescription)")
            }
        }
    }

    private func suggestedTranscriptFilename() -> String {
        let base: String
        switch inputMode {
        case .localFile:
            base = selectedFileURL?
                .deletingPathExtension()
                .lastPathComponent ?? "transcript"
        case .instagramLink:
            base = "instagram-transcript"
        }
        return "\(base)-transcript.txt"
    }

    private func transcribeFromLocalFile() async throws {
        guard let selectedFileURL else {
            fail("Choose a video file first.")
            return
        }
        status("Requesting Speech Recognition permission...")
        let text = try await transcriber.transcribeVideo(
            at: selectedFileURL,
            progress: statusUpdater
        )
        transcript = text
        status("Transcription complete.")
    }

    private func transcribeFromLink() async throws {
        guard let sourceURL = normalizedURL(from: videoLinkText) else {
            fail("Paste a valid Instagram URL (for example: https://www.instagram.com/reel/...).")
            return
        }

        status("Downloading video from link...")
        let downloaded = try await downloader.downloadVideo(
            from: sourceURL,
            progress: statusUpdater
        )
        defer { try? FileManager.default.removeItem(at: downloaded.temporaryDirectoryURL) }

        status("Requesting Speech Recognition permission...")
        let text = try await transcriber.transcribeVideo(
            at: downloaded.fileURL,
            progress: statusUpdater
        )
        transcript = text
        status("Transcription complete.")
    }

    private func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = URL(string: trimmed), direct.scheme != nil {
            return direct
        }

        return URL(string: "https://\(trimmed)")
    }

    private var statusUpdater: @Sendable (String) -> Void {
        { [weak self] message in
            Task { @MainActor in
                self?.status(message)
            }
        }
    }

    private func status(_ message: String) {
        statusMessage = message
        statusIsError = false
    }

    private func fail(_ message: String) {
        statusMessage = message
        statusIsError = true
    }
}
