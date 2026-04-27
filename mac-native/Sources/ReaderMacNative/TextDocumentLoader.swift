import Foundation

enum TextDocumentLoader {
    private static let chapterMarkers = Set(["卷", "章", "部", "节", "回", "集"])
    private static let validChapterNumberCharacters = Set(
        Array("  \t0123456789零一二三四五六七八九十百千万亿壹贰叁肆伍陆柒捌玖拾佰仟萬億两　")
    )

    static func load(from sourceURL: URL) throws -> TextReaderDocument {
        let data = try Data(contentsOf: sourceURL)
        guard let decoded = decodeText(data) else {
            throw ReaderOpenError.invalidText
        }

        let normalized = normalize(decoded.text)
        let chapters = parseChapters(normalized)

        return TextReaderDocument(
            sourceURL: sourceURL,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            encodingLabel: decoded.label,
            chapters: chapters
        )
    }

    private static func decodeText(_ data: Data) -> (text: String, label: String)? {
        let candidates: [(String.Encoding, String)] = [
            (.utf8, "UTF-8"),
            (.gb18030, "GB18030"),
            (.utf16LittleEndian, "UTF-16 LE"),
            (.utf16BigEndian, "UTF-16 BE"),
            (.utf16, "UTF-16"),
        ]

        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data, encoding: .utf8) {
            return (text, "UTF-8 BOM")
        }
        if data.starts(with: [0xFF, 0xFE]), let text = String(data: data, encoding: .utf16LittleEndian) {
            return (text, "UTF-16 LE BOM")
        }
        if data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16BigEndian) {
            return (text, "UTF-16 BE BOM")
        }

        for (encoding, label) in candidates {
            if let text = String(data: data, encoding: encoding), looksReasonable(text) {
                return (text, label)
            }
        }

        return nil
    }

    private static func looksReasonable(_ text: String) -> Bool {
        guard !text.isEmpty else {
            return false
        }

        let replacementCount = text.reduce(into: 0) { count, character in
            if character == "\u{FFFD}" {
                count += 1
            }
        }

        return replacementCount < max(3, text.count / 160)
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{3000}", with: "  ")
    }

    private static func parseChapters(_ text: String) -> [TextChapter] {
        let lines = text.components(separatedBy: "\n")
        var chapters: [TextChapter] = []
        var currentTitle = "开始阅读"
        var currentLines: [String] = []

        func flushCurrentChapter() {
            let body = currentLines.joined(separator: "\n").trimmed
            guard !body.isEmpty else {
                currentLines.removeAll(keepingCapacity: true)
                return
            }

            let chapter = TextChapter(
                id: "txt-\(chapters.count)",
                title: currentTitle,
                content: body
            )
            chapters.append(chapter)
            currentLines.removeAll(keepingCapacity: true)
        }

        for rawLine in lines {
            let line = rawLine.trimmed
            if let title = detectChapterTitle(line) {
                if !currentLines.isEmpty {
                    flushCurrentChapter()
                }
                currentTitle = title
                currentLines.append(title)
                continue
            }

            if currentLines.isEmpty, !line.isEmpty, currentTitle == "开始阅读" {
                currentTitle = line.count > 32 ? String(line.prefix(32)) : line
            }
            currentLines.append(rawLine)
        }

        flushCurrentChapter()

        if chapters.isEmpty {
            return [
                TextChapter(
                    id: "txt-0",
                    title: "全文",
                    content: text.trimmed
                ),
            ]
        }

        return chapters
    }

    private static func detectChapterTitle(_ line: String) -> String? {
        guard !line.isEmpty, line.count <= 80 else {
            return nil
        }

        if line == "楔子" || line.hasPrefix("楔子 ") || line.hasPrefix("楔子　") {
            return line
        }
        if line == "序章" || line.hasPrefix("序章 ") || line.hasPrefix("序章　") {
            return line
        }

        guard line.hasPrefix("第") else {
            return nil
        }

        let characters = Array(line)
        for index in 1..<characters.count {
            let character = characters[index]
            guard chapterMarkers.contains(String(character)) else {
                continue
            }

            let middle = String(characters[1..<index])
            guard isValidChapterNumberText(middle) else {
                continue
            }

            return line
        }

        return nil
    }

    private static func isValidChapterNumberText(_ text: String) -> Bool {
        guard !text.trimmed.isEmpty else {
            return false
        }

        for character in text {
            if !validChapterNumberCharacters.contains(character) {
                return false
            }
        }
        return true
    }
}
