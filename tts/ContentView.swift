//
//  ContentView.swift
//  tts
//
//  Main screen: text input with live spoken-word highlighting, playback
//  controls, voice selection and prosody (speed / pitch / volume) settings.
//

import SwiftUI
import AVFoundation
import UIKit

struct ContentView: View {

    static let sampleText = """
    Welcome to your text to speech app. Type or paste any text here, pick a \
    voice, and tap play to hear it read aloud. You can fine-tune the speed, \
    pitch and volume, and even export the narration as an audio file.
    """

    @StateObject private var speech = SpeechSynthesizer()

    @AppStorage("inputText") private var text = ContentView.sampleText
    @AppStorage("voiceIdentifier") private var voiceIdentifier = ""
    @AppStorage("speechRate") private var rate = Double(AVSpeechUtteranceDefaultSpeechRate)
    @AppStorage("speechPitch") private var pitch = 1.0
    @AppStorage("speechVolume") private var volume = 1.0

    @State private var showingVoicePicker = false
    @State private var isExporting = false
    @State private var shareURL: ShareURL?
    @State private var hapticTrigger = 0
    @FocusState private var editorFocused: Bool

    private var selectedVoice: AVSpeechSynthesisVoice? {
        if !voiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    private var voiceName: String { selectedVoice?.name ?? "Default" }

    private var trimmedIsEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background
                VStack(spacing: 16) {
                    textCard
                    if speech.isSpeaking {
                        ProgressView(value: speech.progress)
                            .tint(AppTheme.accent)
                            .transition(.opacity)
                    }
                    controlsCard
                }
                .padding(16)
            }
            .navigationTitle("Text to Speech")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if editorFocused {
                        Button("Done") { editorFocused = false }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: speech.isSpeaking)
            .sheet(isPresented: $showingVoicePicker) {
                VoicePickerView(selectedIdentifier: $voiceIdentifier)
            }
            .sheet(item: $shareURL) { item in
                ActivityView(items: [item.url])
            }
        }
    }

    // MARK: Text card

    private var textCard: some View {
        VStack(spacing: 12) {
            if speech.isSpeaking {
                HighlightedTextView(text: speech.spokenText, range: speech.spokenRange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Enter text to speak…")
                            .font(.system(size: 21, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 21, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .focused($editorFocused)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Divider()

            HStack(spacing: 18) {
                Text("^[\(wordCount) word](inflect: true) · ^[\(text.count) character](inflect: true)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { paste() } label: { Image(systemName: "doc.on.clipboard") }
                Button { text = ContentView.sampleText } label: { Image(systemName: "text.quote") }
                Button { text = "" } label: { Image(systemName: "trash") }
                    .disabled(text.isEmpty)
            }
            .font(.system(size: 18))
            .tint(AppTheme.accent)
            .opacity(speech.isSpeaking ? 0 : 1)
            .disabled(speech.isSpeaking)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    // MARK: Controls card

    private var controlsCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 28) {
                circleButton(system: "stop.fill", size: 56, prominent: false, action: stopPlayback)
                    .disabled(!speech.isSpeaking)
                    .opacity(speech.isSpeaking ? 1 : 0.4)

                playButton

                exportButton
                    .disabled(trimmedIsEmpty || speech.isSpeaking || isExporting)
                    .opacity((trimmedIsEmpty || speech.isSpeaking) ? 0.4 : 1)
            }

            VStack(spacing: 18) {
                voiceRow

                VStack(spacing: 14) {
                    SliderRow(icon: "gauge.with.dots.needle.67percent", title: "Speed",
                              value: $rate,
                              range: Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate),
                              display: String(format: "%.2f×", rate / Double(AVSpeechUtteranceDefaultSpeechRate)))
                    SliderRow(icon: "dial.medium", title: "Pitch",
                              value: $pitch, range: 0.5...2.0,
                              display: String(format: "%.1f", pitch))
                    SliderRow(icon: "speaker.wave.3.fill", title: "Volume",
                              value: $volume, range: 0.0...1.0,
                              display: "\(Int((volume * 100).rounded()))%")
                }
            }
            // Voice & prosody apply to the next utterance, so lock them while
            // one is playing rather than letting silent changes mislead.
            .disabled(speech.isSpeaking)
            .opacity(speech.isSpeaking ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.2), value: speech.isSpeaking)
        }
        .card()
    }

    private var playButton: some View {
        Button(action: togglePlay) {
            ZStack {
                Circle()
                    .fill(AppTheme.gradient)
                    .frame(width: 84, height: 84)
                    .shadow(color: AppTheme.accent.opacity(0.4), radius: 12, x: 0, y: 6)
                Image(systemName: (speech.isSpeaking && !speech.isPaused) ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(trimmedIsEmpty && !speech.isSpeaking)
        .opacity((trimmedIsEmpty && !speech.isSpeaking) ? 0.5 : 1)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }

    private var exportButton: some View {
        Button(action: exportAudio) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 56, height: 56)
                if isExporting {
                    ProgressView().tint(AppTheme.accent)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func circleButton(system: String, size: CGFloat, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: size, height: size)
                Image(systemName: system)
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .buttonStyle(.plain)
    }

    private var voiceRow: some View {
        Button {
            showingVoicePicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Voice")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(voiceName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func togglePlay() {
        editorFocused = false
        hapticTrigger += 1
        if speech.isSpeaking {
            if speech.isPaused { speech.resume() } else { speech.pause() }
        } else {
            speech.speak(text: text, voice: selectedVoice,
                         rate: Float(rate), pitch: Float(pitch), volume: Float(volume))
        }
    }

    private func stopPlayback() {
        hapticTrigger += 1
        speech.stop()
    }

    private func paste() {
        if let string = UIPasteboard.general.string {
            text = string
        }
    }

    private func exportAudio() {
        isExporting = true
        Task {
            let url = await speech.exportToFile(
                text: text, voice: selectedVoice,
                rate: Float(rate), pitch: Float(pitch), volume: Float(volume)
            )
            isExporting = false
            if let url {
                shareURL = ShareURL(url: url)
            }
        }
    }
}

// MARK: - Supporting views

private struct SliderRow: View {
    let icon: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: String

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(display)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .tint(AppTheme.accent)
        }
    }
}

/// Identifiable wrapper so a freshly generated file URL can drive `.sheet(item:)`.
private struct ShareURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// Bridges UIActivityViewController (share sheet) into SwiftUI.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
