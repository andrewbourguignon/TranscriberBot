import Foundation
@preconcurrency import AVFoundation
import Speech

enum VideoTranscriptionError: LocalizedError {
    case speechPermissionDenied
    case noAudioTrack
    case failedToCreateExporter
    case exportFailed(String)
    case recognizerUnavailable
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "Speech Recognition permission was denied. Enable it in System Settings > Privacy & Security > Speech Recognition."
        case .noAudioTrack:
            return "The selected video does not contain an audio track."
        case .failedToCreateExporter:
            return "Could not prepare audio extraction for the selected video."
        case .exportFailed(let message):
            return "Audio extraction failed: \(message)"
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable for the current locale."
        case .emptyTranscript:
            return "No speech was detected in the video."
        }
    }
}

@MainActor
final class VideoTranscriptionService {
    func transcribeVideo(
        at videoURL: URL,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let authorized = await requestSpeechAuthorization()
        guard authorized else {
            throw VideoTranscriptionError.speechPermissionDenied
        }

        progress("Extracting audio from video...")
        let audioURL = try await extractAudio(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        progress("Transcribing audio...")
        let transcript = try await transcribeAudioFile(audioURL)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VideoTranscriptionError.emptyTranscript
        }
        return trimmed
    }

    nonisolated private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw VideoTranscriptionError.noAudioTrack
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw VideoTranscriptionError.failedToCreateExporter
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        try await exportSession.exportAsync()

        switch exportSession.status {
        case .completed:
            return outputURL
        case .failed:
            throw VideoTranscriptionError.exportFailed(
                exportSession.error?.localizedDescription ?? "Unknown error"
            )
        case .cancelled:
            throw VideoTranscriptionError.exportFailed("Cancelled")
        default:
            throw VideoTranscriptionError.exportFailed("Unexpected export status: \(exportSession.status.rawValue)")
        }
    }

    nonisolated private func transcribeAudioFile(_ url: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Locale.current.identifier)),
              recognizer.isAvailable else {
            throw VideoTranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var bestTranscript = ""
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    bestTranscript = result.bestTranscription.formattedString
                    if result.isFinal && !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: bestTranscript)
                    }
                }

                if let error, !hasResumed {
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }

                if result == nil && error == nil && !hasResumed {
                    hasResumed = true
                    continuation.resume(returning: bestTranscript)
                }
            }
        }
    }
}

private extension AVAssetExportSession {
    func exportAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportAsynchronously {
                if let error = self.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
