# ReaderMacNative

这是给原始 Win32 Reader 补的 **真正原生 macOS 版本**。

它不是把原来的 `.exe` 换壳，而是新建了一套 `SwiftUI + WebKit` 的 mac 应用外壳：

- `TXT`：原生文本阅读视图
- `EPUB`：原生应用壳，使用 `WKWebView` 渲染 EPUB 内容
- 原生目录侧边栏
- 原生设置和阅读进度保存

## 当前支持

- macOS 13 或更新版本
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

需要先安装 Xcode 或 Xcode Command Line Tools。若终端里没有 `swift` 命令，先执行：

```bash
xcode-select --install
```

方式一：一键构建并安装到 `/Applications`

在 macOS 上双击：

```bash
mac-native/Build and Install.command
```

它会自动构建 `ReaderMacNative.app`，安装到 `/Applications`，清理隔离属性，补齐可执行权限，然后打开应用。

方式二：直接命令行导出 `.app`

```bash
cd mac-native
chmod +x build-mac.sh
./build-mac.sh
```

导出的应用会在：

```bash
mac-native/dist/ReaderMacNative.app
```

同时会额外生成方便分发的压缩包和 macOS 安装镜像：

```bash
mac-native/dist/ReaderMacNative-macOS.zip
mac-native/dist/ReaderMacNative-macOS.dmg
```

推荐普通用户优先下载 `.dmg`，打开后把 `ReaderMacNative.app` 拖到 `Applications`。

方式三：用 Xcode 打开

1. 在 mac 上打开 `mac-native/Package.swift`
2. 选择 scheme `ReaderMacNative`
3. 直接 Run，或者 Archive

## 没有 Mac 时怎么导出

如果你现在手上是 Windows 机器，可以把仓库推到 GitHub，然后直接运行仓库内置的 Actions 工作流：

1. 打开 `Actions`
2. 运行 `Build Native macOS App`
3. 在 Artifact 里下载 `ReaderMacNative-macOS`
4. 优先使用里面的 `ReaderMacNative-macOS.dmg`

## 打不开时

如果 macOS 只提示 `The application "ReaderMacNative" can't be opened.`：

1. 在 Mac 上重新运行 `mac-native/Build and Install.command`
2. 或者优先使用 `.dmg` 安装，不要经过聊天软件解压 `.app`
3. 右键点击 `ReaderMacNative.app`，选择 `Open`
4. 如果仍然打不开，终端执行：

```bash
xattr -cr /Applications/ReaderMacNative.app
chmod +x /Applications/ReaderMacNative.app/Contents/MacOS/ReaderMacNative
open /Applications/ReaderMacNative.app
```

当前构建是未公证的开源自用包，所以第一次打开时 macOS 可能会拦截；这是签名/公证问题，不代表程序一定坏了。

参考：

- [Swift Package Manager package manifest](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html)
- [Swift packages in Xcode](https://developer.apple.com/documentation/xcode/swift-packages)

## 说明

原仓库深度绑定 Win32 API，包括 `_tWinMain`、`CreateWindowEx`、`TreeView_*`、`Shell_NotifyIcon`、`SetWindowsHookEx`、GDI+ 等，所以不能直接导出原生 mac 包。

这套 `mac-native` 工程是当前仓库里真正可走通的原生 mac 路线第一阶段：先把本地阅读核心迁过来，再逐步补更复杂的能力。
