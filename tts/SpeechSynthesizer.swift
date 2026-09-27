//
//  SpeechSynthesizer.swift
//  tts
//
//  Wraps AVSpeechSynthesizer in an ObservableObject that publishes playback
//  state and the character range currently being spoken (for live highlighting).
//

import Foundation
import Combine
import AVFoundation

@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject {

    // MARK: Published playback state

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    /// Character range (UTF-16, over `spokenText`) currently being spoken.
    @Published private(set) var spokenRange: NSRange?
    /// The full text of the utterance currently playing.
    @Published private(set) var spokenText = ""
    /// Overall progress through the current utterance, 0...1.
    @Published private(set) var progress: Double = 0

    // MARK: Private

    private let synthesizer = AVSpeechSynthesizer()
    /// The utterance currently owned by this manager. Delegate callbacks are
    /// filtered by identity against this so that late events from a cancelled
    /// utterance can never mutate state belonging to a newer one.
    private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Controls

    func speak(text: String, voice: AVSpeechSynthesisVoice?, rate: Float, pitch: Float, volume: Float) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Starting fresh: cancel anything already playing.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        Self.activateAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate.clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = pitch.clamped(to: 0.5...2.0)
        utterance.volume = volume.clamped(to: 0.0...1.0)

        currentUtterance = utterance
        spokenText = text
        spokenRange = nil
        progress = 0
        synthesizer.speak(utterance)
    }

    func pause() {
        guard synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
    }

    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: Audio session

    static func activateAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true, options: [])
        #endif
    }

    static func deactivateAudioSession() {
        #if os(iOS)
        // Releasing the session un-ducks any other audio we interrupted.
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    // MARK: Export

    /// Renders the given text to a CoreAudio (.caf) file and returns its URL, or
    /// nil on failure. Bounded by a timeout so a stalled render can never leave
    /// the caller waiting forever.
    func exportToFile(text: String, voice: AVSpeechSynthesisVoice?, rate: Float, pitch: Float, volume: Float) async -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Generous ceiling: real renders finish in a fraction of playback time.
        let timeout = max(20.0, Double(text.count) / 6.0)

        return await withTaskGroup(of: URL?.self) { group in
            group.addTask {
                await self.renderToFile(text: text, voice: voice, rate: rate, pitch: pitch, volume: volume)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func renderToFile(text: String, voice: AVSpeechSynthesisVoice?, rate: Float, pitch: Float, volume: Float) async -> URL? {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate.clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = pitch.clamped(to: 0.5...2.0)
        utterance.volume = volume.clamped(to: 0.0...1.0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Speech-\(UUID().uuidString).caf")
        let writer = AVSpeechSynthesizer()

        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            var audioFile: AVAudioFile?
            var didFinish = false

            func finish(_ result: URL?) {
                guard !didFinish else { return }
                didFinish = true
                _ = writer // keep the synthesizer alive until writing completes
                continuation.resume(returning: result)
            }

            writer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else {
                    finish(nil)
                    return
                }
                // A zero-length buffer signals the end of the stream.
                guard pcm.frameLength > 0 else {
                    finish(audioFile == nil ? nil : url)
                    return
                }
                do {
                    if audioFile == nil {
                        audioFile = try AVAudioFile(forWriting: url, settings: pcm.format.settings)
                    }
                    try audioFile?.write(from: pcm)
                } catch {
                    finish(nil)
                }
            }
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.isSpeaking = true
            self.isPaused = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let length = (utterance.speechString as NSString).length
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.spokenRange = characterRange
            if length > 0 {
                let spoken = characterRange.location + characterRange.length
                self.progress = min(1, Double(spoken) / Double(length))
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.isPaused = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.currentUtterance else { return }
            self.isPaused = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(utterance) }
    }

    @MainActor
    private func finish(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        reset()
    }

    @MainActor
    private func reset() {
        isSpeaking = false
        isPaused = false
        spokenRange = nil
        progress = 0
        currentUtterance = nil
        Self.deactivateAudioSession()
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
