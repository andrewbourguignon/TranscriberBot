import Foundation

enum VideoDownloadError: LocalizedError {
    case invalidURL
    case ytDlpNotFound
    case ytDlpFailed(String)
    case noDownloadedFile
    case unsupportedURL
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The link is not a valid URL."
        case .ytDlpNotFound:
            return "Instagram link downloads require yt-dlp. Rebuild the DMG with yt-dlp bundled, or install yt-dlp on this Mac."
        case .ytDlpFailed(let details):
            if details.isEmpty {
                return "yt-dlp could not download that Instagram link."
            }
            return "yt-dlp download failed: \(details)"
        case .noDownloadedFile:
            return "The video download finished, but no media file was found."
        case .unsupportedURL:
            return "Only Instagram links or direct video URLs are supported."
        case .httpError(let statusCode):
            return "Download failed with HTTP status \(statusCode)."
        }
    }
}

struct DownloadedVideo {
    let fileURL: URL
    let temporaryDirectoryURL: URL
}

@MainActor
final class VideoDownloadService {
    func downloadVideo(
        from sourceURL: URL,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> DownloadedVideo {
        guard let scheme = sourceURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw VideoDownloadError.invalidURL
        }

        if isInstagramLink(sourceURL) {
            progress("Downloading Instagram link with yt-dlp...")
            return try await downloadInstagramVideo(from: sourceURL)
        }

        if looksLikeDirectVideoURL(sourceURL) {
            progress("Downloading video URL...")
            return try await downloadDirectVideo(from: sourceURL)
        }

        throw VideoDownloadError.unsupportedURL
    }

    private func isInstagramLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "instagram.com"
            || host == "www.instagram.com"
            || host == "m.instagram.com"
            || host == "instagr.am"
    }

    private func looksLikeDirectVideoURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "webm"].contains(ext)
    }

    private func downloadDirectVideo(from sourceURL: URL) async throws -> DownloadedVideo {
        let temporaryDirectoryURL = makeTemporaryDownloadDirectory()
        let (downloadedTempURL, response) = try await URLSession.shared.download(from: sourceURL)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw VideoDownloadError.httpError(statusCode: httpResponse.statusCode)
        }

        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        let destinationURL = temporaryDirectoryURL
            .appendingPathComponent("video")
            .appendingPathExtension(ext)

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: downloadedTempURL, to: destinationURL)

        return DownloadedVideo(
            fileURL: destinationURL,
            temporaryDirectoryURL: temporaryDirectoryURL
        )
    }

    private func downloadInstagramVideo(from sourceURL: URL) async throws -> DownloadedVideo {
        guard let ytDlpURL = resolveYtDlpExecutableURL() else {
            throw VideoDownloadError.ytDlpNotFound
        }

        let temporaryDirectoryURL = makeTemporaryDownloadDirectory()
        let outputTemplate = temporaryDirectoryURL
            .appendingPathComponent("%(id)s.%(ext)s")
            .path

        let result = try await runProcess(
            executableURL: ytDlpURL,
            arguments: [
                "--no-playlist",
                "--no-progress",
                "--restrict-filenames",
                "-o", outputTemplate,
                sourceURL.absoluteString
            ]
        )

        guard result.exitCode == 0 else {
            let details = [result.standardError, result.standardOutput]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw VideoDownloadError.ytDlpFailed(details)
        }

        guard let fileURL = try findDownloadedMedia(in: temporaryDirectoryURL) else {
            throw VideoDownloadError.noDownloadedFile
        }

        return DownloadedVideo(
            fileURL: fileURL,
            temporaryDirectoryURL: temporaryDirectoryURL
        )
    }

    private func makeTemporaryDownloadDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("igtranscriber-download-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func findDownloadedMedia(in directoryURL: URL) throws -> URL? {
        let candidates = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let media = candidates
            .filter { !$0.lastPathComponent.hasSuffix(".part") }
            .filter {
                let ext = $0.pathExtension.lowercased()
                return ["mp4", "mov", "m4v", "webm", "mp3", "m4a"].contains(ext)
            }

        return media.first
    }

    private func resolveYtDlpExecutableURL() -> URL? {
        let fileManager = FileManager.default

        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("yt-dlp"),
           fileManager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let commonPaths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        for path in commonPaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let pathValue = ProcessInfo.processInfo.environment["PATH"] {
            for entry in pathValue.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(entry))
                    .appendingPathComponent("yt-dlp")
                if fileManager.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String]
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            return ProcessResult(
                exitCode: Int(process.terminationStatus),
                standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
                standardError: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }.value
    }
}

private struct ProcessResult {
    let exitCode: Int
    let standardOutput: String
    let standardError: String
}
