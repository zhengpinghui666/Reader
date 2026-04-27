# ReaderMacNative

这是给原始 Win32 Reader 补的 **真正原生 macOS 版本**。

它不是把原来的 `.exe` 换壳，而是新建了一套 `SwiftUI + WebKit` 的 mac 应用外壳：

- `TXT`：原生文本阅读视图
- `EPUB`：原生应用壳，使用 `WKWebView` 渲染 EPUB 内容
- 原生目录侧边栏
- 原生设置和阅读进度保存

## 当前支持

- 本地 `txt`
- 本地 `epub`
- 章节 / 目录导航
- 主题切换
- 字号和行高调整
- 阅读进度保存

## 暂未迁移

- `mobi`
- 在线书源
- 托盘 / 全局热键 / 透明窗 / 置顶
- Win32 专有窗口行为

## 在 mac 上构建

方式一：直接命令行导出 `.app`

```bash
cd mac-native
chmod +x build-mac.sh
./build-mac.sh
```

导出的应用会在：

```bash
mac-native/dist/ReaderMacNative.app
```

同时会额外生成一个方便分发的压缩包：

```bash
mac-native/dist/ReaderMacNative-macOS.zip
```

方式二：用 Xcode 打开

1. 在 mac 上打开 `mac-native/Package.swift`
2. 选择 scheme `ReaderMacNative`
3. 直接 Run，或者 Archive

## 没有 Mac 时怎么导出

如果你现在手上是 Windows 机器，可以把仓库推到 GitHub，然后直接运行仓库内置的 Actions 工作流：

1. 打开 `Actions`
2. 运行 `Build Native macOS App`
3. 在 Artifact 里下载 `ReaderMacNative-macOS`

参考：

- [Swift Package Manager package manifest](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html)
- [Swift packages in Xcode](https://developer.apple.com/documentation/xcode/swift-packages)

## 说明

原仓库深度绑定 Win32 API，包括 `_tWinMain`、`CreateWindowEx`、`TreeView_*`、`Shell_NotifyIcon`、`SetWindowsHookEx`、GDI+ 等，所以不能直接导出原生 mac 包。

这套 `mac-native` 工程是当前仓库里真正可走通的原生 mac 路线第一阶段：先把本地阅读核心迁过来，再逐步补更复杂的能力。
