# Reader for macOS

这是给原仓库补的一条 **最快可落地的 mac 使用路径**。

原项目是纯 Win32 桌面程序，主入口直接使用：

- `_tWinMain`
- `CreateWindowEx`
- `Shell_NotifyIcon`
- `SetWindowsHookEx`
- `TreeView_*`
- `GDI+`

这意味着它不是“换个平台导出一下”就能得到 `.app`，而是需要重做窗口层。

所以这里先提供一个 **可直接在 macOS 浏览器里使用的离线阅读版**。

## 现在支持

- 本地 `txt`
- 本地 `epub`
- 章节目录
- 阅读主题
- 字号 / 行高调节
- 阅读进度本地保存
- 拖拽打开

## 暂未迁移

- `mobi`
- 在线书源
- 托盘、热键、透明窗、全局置顶

## 在 macOS 上怎么打开

最快方式：

1. 打开 `mac-web` 文件夹
2. 优先双击 `Open Reader.command`
3. 如果不想用脚本，再直接双击 `index.html`
4. 在浏览器里打开本地书籍

如果你更喜欢终端启动，也可以执行：

```bash
chmod +x "Open Reader.command"
./Open\ Reader.command
```

## 为什么先这样做

因为这是当前仓库里 **最快能让 mac 真正用起来** 的方案。

如果下一阶段要做真正的原生 `.app`，建议路线是：

1. 先把 `Book / TextBook / EpubBook / MobiBook / HtmlParser / Cache` 这类核心逻辑从 Win32 依赖里拆出来
2. 再选一个跨平台 UI 壳：
   - SwiftUI（mac 原生）
   - Qt
   - Tauri / Electron

这会比当前工作量大很多，但才是完整原生迁移路线。
