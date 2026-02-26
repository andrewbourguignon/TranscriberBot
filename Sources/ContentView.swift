import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: TranscriberViewModel
    @State private var importingVideo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("IG Video Transcriber")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                Text("Input")
                    .font(.headline)

                Picker("Input Mode", selection: $model.inputMode) {
                    ForEach(TranscriberViewModel.InputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch model.inputMode {
                case .localFile:
                    HStack(spacing: 8) {
                        Button("Choose Video") {
                            importingVideo = true
                        }

                        if let selectedFileURL = model.selectedFileURL {
                            Text(selectedFileURL.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No file selected")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Pick any local Instagram video file (e.g. .mp4, .mov). The app does not require a fixed folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                case .instagramLink:
                    TextField("https://www.instagram.com/reel/...", text: $model.videoLinkText)
                        .textFieldStyle(.roundedBorder)

                    Text("Paste an Instagram reel/post URL. The app downloads a temporary copy for transcription, then removes it. Private/login-only posts may fail.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button(model.isTranscribing ? "Transcribing..." : "Transcribe") {
                    Task { await model.transcribeCurrentInput() }
                }
                .disabled(model.isTranscribing || !model.canStartTranscription)

                Button("Copy Transcript") {
                    model.copyTranscriptToClipboard()
                }
                .disabled(model.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Save .txt") {
                    model.saveTranscript()
                }
                .disabled(model.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                if model.isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(model.statusIsError ? .red : .secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Transcript")
                    .font(.headline)

                TextEditor(text: $model.transcript)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Text("Uses Apple Speech Recognition on macOS. Instagram link mode uses yt-dlp.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(20)
        .fileImporter(
            isPresented: $importingVideo,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            model.handleVideoImport(result)
        }
    }
}
