import Foundation
import SwiftUI

@main
struct ReaderMacNativeApp: App {
    @StateObject private var store = ReaderStore()

    var body: some Scene {
        WindowGroup("ReaderMacNative") {
            ReaderRootView()
                .environmentObject(store)
                .frame(minWidth: 1100, minHeight: 760)
        }
        .commands {
            ReaderCommands(store: store)
        }
    }
}

struct ReaderCommands: Commands {
    @ObservedObject var store: ReaderStore

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("打开书籍...") {
                store.openDocumentPanel()
            }
            .keyboardShortcut("o")
        }

        CommandMenu("阅读") {
            Button("上一章 / 上一节") {
                store.goPrevious()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .disabled(!store.canGoPrevious)

            Button("下一章 / 下一节") {
                store.goNext()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .disabled(!store.canGoNext)
        }
    }
}

struct ReaderRootView: View {
    @EnvironmentObject private var store: ReaderStore

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            NavigationSplitView {
                ReaderSidebarView()
            } detail: {
                ReaderDetailView()
            }
        }
        .background(store.theme.backgroundColor)
        .preferredColorScheme(store.theme == .night ? .dark : .light)
        .alert(
            "打开失败",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { if !$0 { store.alertMessage = nil } }
            ),
            actions: {
                Button("好", role: .cancel) {}
            },
            message: {
                Text(store.alertMessage ?? "")
            }
        )
    }

    private var controlBar: some View {
        HStack(spacing: 16) {
            Button("打开文件") {
                store.openDocumentPanel()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(store.currentTitle)
                    .font(.headline)
                Text(store.documentSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("主题", selection: Binding(
                get: { store.theme },
                set: { store.theme = $0 }
            )) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            LabeledContent("字号") {
                Stepper(
                    value: Binding(
                        get: { store.fontSize },
                        set: { store.fontSize = $0 }
                    ),
                    in: 14...34,
                    step: 1
                ) {
                    Text("\(Int(store.fontSize))")
                        .monospacedDigit()
                }
                .frame(width: 120)
            }

            LabeledContent("行高") {
                Stepper(
                    value: Binding(
                        get: { store.lineSpacing },
                        set: { store.lineSpacing = $0 }
                    ),
                    in: 1.2...2.4,
                    step: 0.1
                ) {
                    Text(String(format: "%.1f", store.lineSpacing))
                        .monospacedDigit()
                }
                .frame(width: 120)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(store.theme.surfaceColor)
    }
}

struct ReaderSidebarView: View {
    @EnvironmentObject private var store: ReaderStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("目录")
                    .font(.title3.weight(.semibold))
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Divider()

            List(
                store.sidebarItems,
                selection: Binding(
                    get: { store.selectedSidebarID },
                    set: { store.selectSidebarItem(id: $0) }
                )
            ) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .lineLimit(2)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(item.id)
                .padding(.vertical, 2)
            }
            .listStyle(.sidebar)
        }
        .background(store.theme.surfaceColor)
    }
}

struct ReaderDetailView: View {
    @EnvironmentObject private var store: ReaderStore

    var body: some View {
        ZStack {
            store.theme.backgroundColor
                .ignoresSafeArea()

            if store.isBusy {
                ProgressView("正在打开书籍…")
                    .controlSize(.large)
            } else if store.textDocument != nil {
                TextReaderView()
            } else if store.epubDocument != nil {
                EPUBReaderView()
            } else {
                EmptyStateView()
            }
        }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var store: ReaderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("真正原生的 mac Reader")
                .font(.system(size: 34, weight: .bold))
            Text("这不是把 Win32 程序强行套壳，而是新的 SwiftUI macOS 应用。")
                .foregroundStyle(.secondary)
            Text("当前第一阶段已经支持本地 TXT / EPUB 阅读。")
                .foregroundStyle(.secondary)
            Button("打开本地书籍") {
                store.openDocumentPanel()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: 720, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct TextReaderView: View {
    @EnvironmentObject private var store: ReaderStore

    var body: some View {
        VStack(spacing: 0) {
            readerToolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let chapter = store.currentTextChapter {
                        let paragraphItems = paragraphs(for: chapter.content)
                        Text(chapter.title)
                            .font(.system(size: store.fontSize + 8, weight: .bold))
                            .foregroundStyle(store.theme.textColor)
                            .padding(.bottom, 6)

                        ForEach(paragraphItems.indices, id: \.self) { index in
                            let paragraph = paragraphItems[index]
                            if paragraph.isEmpty {
                                Color.clear.frame(height: 10)
                            } else if paragraph.isHeading {
                                Text(paragraph.text)
                                    .font(.system(size: store.fontSize + 2, weight: .semibold))
                                    .foregroundStyle(store.theme.textColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text("　　" + paragraph.text)
                                    .font(.system(size: store.fontSize))
                                    .lineSpacing((store.lineSpacing - 1.0) * 10.0)
                                    .foregroundStyle(store.theme.textColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(store.theme.surfaceColor)
    }

    private var readerToolbar: some View {
        HStack {
            Button("上一章") {
                store.goPrevious()
            }
            .disabled(!store.canGoPrevious)

            Button("下一章") {
                store.goNext()
            }
            .disabled(!store.canGoNext)

            Spacer()

            if let textDocument = store.textDocument {
                Text("TXT · \(textDocument.encodingLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func paragraphs(for content: String) -> [(text: String, isHeading: Bool)] {
        content
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmed
                return (trimmed, trimmed.hasPrefix("第") && trimmed.count < 80)
            }
    }
}

struct EPUBReaderView: View {
    @EnvironmentObject private var store: ReaderStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("上一节") {
                    store.goPrevious()
                }
                .disabled(!store.canGoPrevious)

                Button("下一节") {
                    store.goNext()
                }
                .disabled(!store.canGoNext)

                Spacer()

                if let epubDocument = store.epubDocument {
                    Text("EPUB · \(epubDocument.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            EPUBWebView(
                fileURL: store.currentEPUBFileURL,
                readAccessURL: store.epubDocument?.extractionRootURL,
                anchor: store.currentEPUBAnchor,
                theme: store.theme,
                fontSize: store.fontSize,
                lineSpacing: store.lineSpacing
            )
        }
        .background(store.theme.surfaceColor)
    }
}
