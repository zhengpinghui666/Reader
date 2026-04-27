import AppKit
import CoreFoundation
import Foundation
import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable, Codable {
    case paper
    case night
    case forest
    case sepia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paper:
            return "纸张"
        case .night:
            return "夜间"
        case .forest:
            return "松针"
        case .sepia:
            return "暖黄"
        }
    }

    var backgroundColor: Color {
        Color(nsColor: backgroundNSColor)
    }

    var backgroundNSColor: NSColor {
        switch self {
        case .paper:
            return NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.88, alpha: 1.0)
        case .night:
            return NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.10, alpha: 1.0)
        case .forest:
            return NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.94, alpha: 1.0)
        case .sepia:
            return NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.87, alpha: 1.0)
        }
    }

    var surfaceColor: Color {
        Color(nsColor: surfaceNSColor)
    }

    var surfaceNSColor: NSColor {
        switch self {
        case .paper:
            return NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.93, alpha: 1.0)
        case .night:
            return NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.16, alpha: 1.0)
        case .forest:
            return NSColor(calibratedRed: 0.97, green: 0.99, blue: 0.97, alpha: 1.0)
        case .sepia:
            return NSColor(calibratedRed: 1.00, green: 0.97, blue: 0.92, alpha: 1.0)
        }
    }

    var textColor: Color {
        Color(nsColor: textNSColor)
    }

    var textNSColor: NSColor {
        switch self {
        case .paper:
            return NSColor(calibratedRed: 0.20, green: 0.16, blue: 0.12, alpha: 1.0)
        case .night:
            return NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.96, alpha: 1.0)
        case .forest:
            return NSColor(calibratedRed: 0.13, green: 0.19, blue: 0.15, alpha: 1.0)
        case .sepia:
            return NSColor(calibratedRed: 0.27, green: 0.18, blue: 0.13, alpha: 1.0)
        }
    }

    var accentColor: Color {
        Color(nsColor: accentNSColor)
    }

    var accentNSColor: NSColor {
        switch self {
        case .paper:
            return NSColor(calibratedRed: 0.55, green: 0.37, blue: 0.20, alpha: 1.0)
        case .night:
            return NSColor(calibratedRed: 0.50, green: 0.75, blue: 1.0, alpha: 1.0)
        case .forest:
            return NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.32, alpha: 1.0)
        case .sepia:
            return NSColor(calibratedRed: 0.68, green: 0.37, blue: 0.16, alpha: 1.0)
        }
    }

    var cssBackground: String { backgroundNSColor.cssRGBA }
    var cssSurface: String { surfaceNSColor.cssRGBA }
    var cssText: String { textNSColor.cssRGBA }
    var cssAccent: String { accentNSColor.cssRGBA }
}

struct ReaderSettings: Codable {
    var theme: ReaderTheme = .paper
    var fontSize: Double = 20
    var lineSpacing: Double = 1.85
}

final class ReaderSettingsStore {
    private let key = "reader.mac.native.settings"

    func load() -> ReaderSettings {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return ReaderSettings()
        }

        do {
            return try JSONDecoder().decode(ReaderSettings.self, from: data)
        } catch {
            return ReaderSettings()
        }
    }

    func save(_ settings: ReaderSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct ReaderSidebarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
}

struct TextChapter: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let content: String
}

struct TextReaderDocument {
    let sourceURL: URL
    let title: String
    let encodingLabel: String
    let chapters: [TextChapter]

    var progressKey: String {
        sourceURL.standardizedFileURL.path
    }
}

struct EPUBSpineItem: Identifiable, Hashable {
    let id: String
    let title: String
    let relativePath: String
    let fileURL: URL
}

struct EPUBTOCItem: Identifiable, Hashable {
    let id: String
    let title: String
    let href: String
    let spineIndex: Int?
}

struct EPUBLocation {
    let fileURL: URL
    let spineIndex: Int
    let anchor: String?
}

struct EPUBReaderDocument {
    let sourceURL: URL
    let title: String
    let extractionRootURL: URL
    let opfDirectoryURL: URL
    let spine: [EPUBSpineItem]
    let toc: [EPUBTOCItem]

    var progressKey: String {
        sourceURL.standardizedFileURL.path
    }

    func resolveLocation(for href: String) -> EPUBLocation? {
        let decoded = href.removingPercentEncoding ?? href
        let parts = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = parts.first.map(String.init) ?? decoded
        let anchor = parts.count > 1 ? String(parts[1]) : nil

        let baseURL: URL
        if pathPart.isEmpty {
            baseURL = spine.first?.fileURL ?? opfDirectoryURL
        } else {
            baseURL = URL(fileURLWithPath: pathPart, relativeTo: opfDirectoryURL).standardizedFileURL
        }

        guard let index = spine.firstIndex(where: { $0.fileURL.standardizedFileURL.path == baseURL.standardizedFileURL.path }) else {
            return nil
        }

        return EPUBLocation(fileURL: baseURL, spineIndex: index, anchor: anchor)
    }

    func sidebarID(forSpineIndex index: Int) -> String? {
        toc.first(where: { $0.spineIndex == index })?.id
    }
}

struct ReaderProgress: Codable {
    var textChapterIndex: Int?
    var epubHref: String?
}

final class ReadingProgressStore {
    private let key = "reader.mac.native.progress"

    func load(for bookKey: String) -> ReaderProgress {
        loadAll()[bookKey] ?? ReaderProgress()
    }

    func save(_ progress: ReaderProgress, for bookKey: String) {
        var all = loadAll()
        all[bookKey] = progress
        guard let data = try? JSONEncoder().encode(all) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func loadAll() -> [String: ReaderProgress] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: ReaderProgress].self, from: data)
        } catch {
            return [:]
        }
    }
}

enum ReaderOpenError: LocalizedError {
    case unsupportedFormat(String)
    case invalidText
    case invalidEPUB(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "暂不支持 \(ext) 格式。当前原生 mac 版先覆盖 TXT 与 EPUB。"
        case .invalidText:
            return "TXT 文件无法识别编码，或者内容为空。"
        case .invalidEPUB(let reason):
            return "EPUB 解析失败：\(reason)"
        }
    }
}

extension NSColor {
    var cssRGBA: String {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return "rgba(255,255,255,1)"
        }

        let red = Int(round(rgb.redComponent * 255))
        let green = Int(round(rgb.greenComponent * 255))
        let blue = Int(round(rgb.blueComponent * 255))
        let alpha = String(format: "%.3f", rgb.alphaComponent)
        return "rgba(\(red), \(green), \(blue), \(alpha))"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension String.Encoding {
    static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )
}
