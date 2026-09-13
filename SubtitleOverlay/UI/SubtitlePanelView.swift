import SwiftUI

@MainActor
private final class SubtitleDisplayModel: ObservableObject {
    @Published private(set) var entries: [String] = []
    @Published private(set) var currentSource = ""
    @Published private(set) var translationText = ""

    private var committedPrefix = ""
    private var latestText = ""
    private var translationTask: Task<Void, Never>?

    var sourceText: String {
        (entries + [currentSource])
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func update(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != latestText else { return }

        // ponytail: reset on cross-boundary recognition revisions; use stable segment IDs if this becomes visible.
        if !text.hasPrefix(committedPrefix) {
            resetDisplay()
            committedPrefix = ""
        }

        latestText = text
        currentSource = String(text.dropFirst(committedPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if currentSource.last.map({ ".!?。！？".contains($0) }) == true {
            commitCurrent()
        }
        translateVisibleText()
    }

    func stop() {
        translationTask?.cancel()
    }

    private func commitCurrent() {
        guard !currentSource.isEmpty else { return }
        entries.append(currentSource)
        if entries.count > 12 {
            entries.removeFirst(entries.count - 12)
        }
        committedPrefix = latestText
        currentSource = ""
    }

    private func translateVisibleText() {
        guard AppSettings.shared.showChineseTranslation else { return }
        let text = sourceText
        translationTask?.cancel()
        translationTask = Task { [weak self] in
            guard let self else { return }
            let translation = await TranslationService.shared.translate(text)
            guard !Task.isCancelled, let translation else { return }
            self.translationText = translation
        }
    }

    private func resetDisplay() {
        translationTask?.cancel()
        translationTask = nil
        entries.removeAll()
        currentSource = ""
        translationText = ""
        TranslationService.shared.translatedText = ""
    }
}

struct SubtitlePanelView: View {
    @ObservedObject private var speech = SpeechRecognizer.shared
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var display = SubtitleDisplayModel()

    var body: some View {
        VStack(spacing: 6) {
            if settings.showChineseTranslation {
                Text(display.translationText.isEmpty ? " " : display.translationText)
                    .font(.system(size: settings.subtitleFontSize, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(3, reservesSpace: true)
                    .truncationMode(.head)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Text(display.sourceText.isEmpty ? " " : display.sourceText)
                .font(.system(size: settings.subtitleFontSize * 0.7))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.head)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minWidth: 300, idealWidth: settings.windowWidth, maxWidth: 900,
               minHeight: 60, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(settings.backgroundOpacity))
        )
        .onReceive(speech.$recognizedText) { display.update($0) }
        .onDisappear { display.stop() }
    }
}
