import AppKit
import Foundation
import SwiftUI

@MainActor
final class ReaderStore: ObservableObject {
    @Published var settings: ReaderSettings
    @Published var sidebarItems: [ReaderSidebarItem] = []
    @Published var selectedSidebarID: String?
    @Published var currentTitle: String = "ReaderMacNative"
    @Published var statusMessage: String = "支持本地 TXT / EPUB。"
    @Published var isBusy = false
    @Published var alertMessage: String?

    @Published private(set) var textDocument: TextReaderDocument?
    @Published private(set) var epubDocument: EPUBReaderDocument?
    @Published private(set) var currentTextChapterIndex = 0
    @Published private(set) var currentEPUBFileURL: URL?
    @Published private(set) var currentEPUBAnchor: String?
    @Published private(set) var currentEPUBSpineIndex = 0

    private let settingsStore = ReaderSettingsStore()
    private let progressStore = ReadingProgressStore()

    init() {
        settings = settingsStore.load()
    }

    var theme: ReaderTheme {
        get { settings.theme }
        set {
            settings.theme = newValue
            persistSettings()
        }
    }

    var fontSize: Double {
        get { settings.fontSize }
        set {
            settings.fontSize = min(max(newValue, 14), 34)
            persistSettings()
        }
    }

    var lineSpacing: Double {
        get { settings.lineSpacing }
        set {
            settings.lineSpacing = min(max(newValue, 1.2), 2.4)
            persistSettings()
        }
    }

    var currentTextChapter: TextChapter? {
        textDocument?.chapters[safe: currentTextChapterIndex]
    }

    var canGoPrevious: Bool {
        if let textDocument {
            return currentTextChapterIndex > 0 && !textDocument.chapters.isEmpty
        }
        if let epubDocument {
            return currentEPUBSpineIndex > 0 && !epubDocument.spine.isEmpty
        }
        return false
    }

    var canGoNext: Bool {
        if let textDocument {
            return currentTextChapterIndex < textDocument.chapters.count - 1
        }
        if let epubDocument {
            return currentEPUBSpineIndex < epubDocument.spine.count - 1
        }
        return false
    }

    var documentSummary: String {
        if let textDocument {
            return "TXT · \(textDocument.encodingLabel) · \(textDocument.chapters.count) 章"
        }
        if let epubDocument {
            return "EPUB · \(epubDocument.spine.count) 个内容文件 · \(epubDocument.toc.count) 个目录项"
        }
        return "未打开书籍"
    }

    func openDocumentPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["txt", "text", "md", "epub"]
        panel.message = "选择 TXT 或 EPUB 文件"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        openDocument(at: url)
    }

    func openDocument(at url: URL) {
        isBusy = true
        statusMessage = "正在打开 \(url.lastPathComponent)..."
        alertMessage = nil

        do {
            switch url.pathExtension.lowercased() {
            case "txt", "text", "md":
                let document = try TextDocumentLoader.load(from: url)
                present(textDocument: document)
            case "epub":
                let document = try EPUBDocumentLoader.load(from: url)
                present(epubDocument: document)
            default:
                throw ReaderOpenError.unsupportedFormat(url.pathExtension.lowercased())
            }
        } catch {
            alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = "打开失败"
        }

        isBusy = false
    }

    func goPrevious() {
        if textDocument != nil {
            selectTextChapter(at: currentTextChapterIndex - 1)
            return
        }

        guard let epubDocument else {
            return
        }

        let nextIndex = currentEPUBSpineIndex - 1
        guard epubDocument.spine.indices.contains(nextIndex) else {
            return
        }

        setCurrentEPUBLocation(
            fileURL: epubDocument.spine[nextIndex].fileURL,
            spineIndex: nextIndex,
            anchor: nil
        )
    }

    func goNext() {
        if textDocument != nil {
            selectTextChapter(at: currentTextChapterIndex + 1)
            return
        }

        guard let epubDocument else {
            return
        }

        let nextIndex = currentEPUBSpineIndex + 1
        guard epubDocument.spine.indices.contains(nextIndex) else {
            return
        }

        setCurrentEPUBLocation(
            fileURL: epubDocument.spine[nextIndex].fileURL,
            spineIndex: nextIndex,
            anchor: nil
        )
    }

    func selectSidebarItem(id: String?) {
        guard let id else {
            return
        }

        if let textDocument {
            guard let index = textDocument.chapters.firstIndex(where: { $0.id == id }) else {
                return
            }
            selectTextChapter(at: index)
            return
        }

        if let epubDocument, let item = epubDocument.toc.first(where: { $0.id == id }),
           let location = epubDocument.resolveLocation(for: item.href) {
            setCurrentEPUBLocation(
                fileURL: location.fileURL,
                spineIndex: location.spineIndex,
                anchor: location.anchor,
                preferredSidebarID: item.id
            )
        }
    }

    private func present(textDocument document: TextReaderDocument) {
        self.textDocument = document
        epubDocument = nil
        currentEPUBFileURL = nil
        currentEPUBAnchor = nil
        currentEPUBSpineIndex = 0
        currentTitle = document.title
        sidebarItems = document.chapters.enumerated().map { index, chapter in
            ReaderSidebarItem(
                id: chapter.id.isEmpty ? "txt-\(index)" : chapter.id,
                title: chapter.title,
                subtitle: "第 \(index + 1) 章"
            )
        }

        let progress = progressStore.load(for: document.progressKey)
        let index = min(max(progress.textChapterIndex ?? 0, 0), max(0, document.chapters.count - 1))
        selectTextChapter(at: index)
        statusMessage = "已打开 TXT：\(document.encodingLabel)"
    }

    private func present(epubDocument document: EPUBReaderDocument) {
        self.epubDocument = document
        textDocument = nil
        currentTextChapterIndex = 0
        currentEPUBFileURL = nil
        currentEPUBAnchor = nil
        currentEPUBSpineIndex = 0
        currentTitle = document.title
        sidebarItems = document.toc.enumerated().map { index, item in
            ReaderSidebarItem(
                id: item.id,
                title: item.title,
                subtitle: item.spineIndex.map { "目录 \($0 + 1)" } ?? "目录 \(index + 1)"
            )
        }

        let progress = progressStore.load(for: document.progressKey)
        if let href = progress.epubHref, let location = document.resolveLocation(for: href) {
            setCurrentEPUBLocation(
                fileURL: location.fileURL,
                spineIndex: location.spineIndex,
                anchor: location.anchor,
                preferredSidebarID: document.toc.first(where: { $0.href == href })?.id
            )
        } else if let firstItem = document.toc.first, let location = document.resolveLocation(for: firstItem.href) {
            setCurrentEPUBLocation(
                fileURL: location.fileURL,
                spineIndex: location.spineIndex,
                anchor: location.anchor,
                preferredSidebarID: firstItem.id
            )
        } else if let firstSpine = document.spine.first {
            setCurrentEPUBLocation(fileURL: firstSpine.fileURL, spineIndex: 0, anchor: nil)
        }

        statusMessage = "已打开 EPUB"
    }

    private func selectTextChapter(at index: Int) {
        guard let textDocument, textDocument.chapters.indices.contains(index) else {
            return
        }

        currentTextChapterIndex = index
        selectedSidebarID = sidebarItems[safe: index]?.id
        statusMessage = "第 \(index + 1) / \(textDocument.chapters.count) 章"
        progressStore.save(
            ReaderProgress(textChapterIndex: index, epubHref: nil),
            for: textDocument.progressKey
        )
    }

    private func setCurrentEPUBLocation(
        fileURL: URL,
        spineIndex: Int,
        anchor: String?,
        preferredSidebarID: String? = nil
    ) {
        guard let epubDocument, epubDocument.spine.indices.contains(spineIndex) else {
            return
        }

        currentEPUBFileURL = fileURL
        currentEPUBAnchor = anchor
        currentEPUBSpineIndex = spineIndex
        selectedSidebarID = preferredSidebarID ?? epubDocument.sidebarID(forSpineIndex: spineIndex)

        let savedHref = epubDocument.toc.first(where: { $0.id == selectedSidebarID })?.href
        let hrefToSave = savedHref ?? epubDocument.spine[spineIndex].relativePath
        progressStore.save(
            ReaderProgress(textChapterIndex: nil, epubHref: hrefToSave),
            for: epubDocument.progressKey
        )
        statusMessage = "EPUB 位置：\(spineIndex + 1) / \(epubDocument.spine.count)"
    }

    private func persistSettings() {
        settingsStore.save(settings)
        objectWillChange.send()
    }
}
