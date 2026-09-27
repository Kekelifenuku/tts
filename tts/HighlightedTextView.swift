//
//  HighlightedTextView.swift
//  tts
//
//  Read-only text view that highlights the word currently being spoken and
//  auto-scrolls to keep it visible. Text is split into paragraphs (computed
//  once per text change, not per spoken word) so that only the paragraph
//  containing the active word rebuilds its styled string on each event —
//  everything else reuses a cached plain AttributedString. Highlighting stays
//  UTF-16 accurate against the NSRange reported by AVSpeechSynthesizer.
//

import SwiftUI

struct HighlightedTextView: View {
    let text: String
    let range: NSRange?
    var fontSize: CGFloat = 21

    @State private var paragraphs: [Paragraph]

    init(text: String, range: NSRange?, fontSize: CGFloat = 21) {
        self.text = text
        self.range = range
        self.fontSize = fontSize
        _paragraphs = State(initialValue: Self.buildParagraphs(from: text, fontSize: fontSize))
    }

    private struct Paragraph: Identifiable {
        let id: Int
        let start: Int              // UTF-16 offset of this paragraph within the full text
        let length: Int             // UTF-16 length, excluding the trailing newline separator
        let string: String
        let plain: AttributedString // pre-styled, un-highlighted — reused every render
    }

    private var activeParagraphID: Int? {
        guard let range, range.location != NSNotFound else { return nil }
        let location = range.location
        return paragraphs.first { location >= $0.start && location <= $0.start + $0.length }?.id
            ?? paragraphs.last?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(paragraphs) { paragraph in
                        Text(displayString(for: paragraph))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(paragraph.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: range?.location ?? -1) { _, _ in
                guard let id = activeParagraphID else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .onChange(of: text) { _, newText in
            paragraphs = Self.buildParagraphs(from: newText, fontSize: fontSize)
        }
    }

    /// Highlighted string for the paragraph containing the spoken range;
    /// the cached plain string for every other paragraph (no allocation).
    private func displayString(for paragraph: Paragraph) -> AttributedString {
        guard let range, range.location != NSNotFound else { return paragraph.plain }

        let localLocation = range.location - paragraph.start
        let nsString = paragraph.string as NSString
        guard localLocation >= 0, localLocation < nsString.length else { return paragraph.plain }
        let localLength = min(range.length, nsString.length - localLocation)
        guard localLength > 0 else { return paragraph.plain }

        let before = nsString.substring(to: localLocation)
        let current = nsString.substring(with: NSRange(location: localLocation, length: localLength))
        let after = nsString.substring(from: localLocation + localLength)

        var result = Self.styled(before, weight: .regular, highlighted: false, fontSize: fontSize)
        result.append(Self.styled(current, weight: .semibold, highlighted: true, fontSize: fontSize))
        result.append(Self.styled(after, weight: .regular, highlighted: false, fontSize: fontSize))
        return result
    }

    // MARK: Building

    private static func buildParagraphs(from text: String, fontSize: CGFloat) -> [Paragraph] {
        var result: [Paragraph] = []
        var offset = 0
        for (index, part) in text.components(separatedBy: "\n").enumerated() {
            let length = (part as NSString).length
            result.append(Paragraph(
                id: index,
                start: offset,
                length: length,
                string: part,
                plain: styled(part, weight: .regular, highlighted: false, fontSize: fontSize)
            ))
            offset += length + 1 // account for the "\n" removed by the split
        }
        return result
    }

    private static func styled(_ string: String, weight: Font.Weight, highlighted: Bool, fontSize: CGFloat) -> AttributedString {
        var attributed = AttributedString(string)
        attributed.font = .system(size: fontSize, weight: weight, design: .rounded)
        attributed.foregroundColor = highlighted ? .black : .primary
        if highlighted {
            attributed.backgroundColor = AppTheme.highlight
        }
        return attributed
    }
}
