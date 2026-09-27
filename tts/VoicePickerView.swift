//
//  VoicePickerView.swift
//  tts
//
//  Searchable list of installed voices grouped by language, with quality and
//  gender badges and per-voice previews.
//

import SwiftUI
import AVFoundation

struct VoicePickerView: View {
    @Binding var selectedIdentifier: String
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var previewSynthesizer = AVSpeechSynthesizer()
    @State private var previewingIdentifier: String?

    private struct LanguageGroup: Identifiable {
        let id: String          // language code
        let display: String     // localized language name
        let voices: [AVSpeechSynthesisVoice]
    }

    private var groups: [LanguageGroup] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            guard !query.isEmpty else { return true }
            return voice.name.lowercased().contains(query)
                || voice.language.lowercased().contains(query)
                || Self.languageName(voice.language).lowercased().contains(query)
        }

        let current = AVSpeechSynthesisVoice.currentLanguageCode()
        return Dictionary(grouping: voices, by: \.language)
            .map { code, voices in
                LanguageGroup(
                    id: code,
                    display: Self.languageName(code),
                    voices: voices.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                )
            }
            .sorted { lhs, rhs in
                if lhs.id == current { return true }
                if rhs.id == current { return false }
                return lhs.display.localizedCompare(rhs.display) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section(group.display) {
                        ForEach(group.voices, id: \.identifier) { voice in
                            row(for: voice)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search voices or languages")
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear {
                previewSynthesizer.stopSpeaking(at: .immediate)
                SpeechSynthesizer.deactivateAudioSession()
            }
        }
    }

    private func row(for voice: AVSpeechSynthesisVoice) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(voice.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    badge(Self.qualityLabel(voice.quality), filled: voice.quality != .default)
                    if let gender = Self.genderLabel(voice.gender) {
                        badge(gender, filled: false)
                    }
                    Text(voice.language)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            if voice.identifier == selectedIdentifier {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.title3)
            }

            Button {
                preview(voice)
            } label: {
                Image(systemName: previewingIdentifier == voice.identifier ? "stop.circle.fill" : "play.circle")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedIdentifier = voice.identifier
            dismiss()
        }
    }

    private func badge(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(filled ? AppTheme.accent.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
            )
            .foregroundStyle(filled ? AppTheme.accent : Color.secondary)
    }

    private func preview(_ voice: AVSpeechSynthesisVoice) {
        previewSynthesizer.stopSpeaking(at: .immediate)
        if previewingIdentifier == voice.identifier {
            previewingIdentifier = nil
            return
        }
        SpeechSynthesizer.activateAudioSession()
        let utterance = AVSpeechUtterance(string: "Hello, this is the \(voice.name) voice.")
        utterance.voice = voice
        previewingIdentifier = voice.identifier
        previewSynthesizer.speak(utterance)
    }

    // MARK: Labels

    private static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Standard"
        }
    }

    private static func genderLabel(_ gender: AVSpeechSynthesisVoiceGender) -> String? {
        switch gender {
        case .male: return "Male"
        case .female: return "Female"
        default: return nil
        }
    }
}
