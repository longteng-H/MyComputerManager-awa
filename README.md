# MyComputerManager-awa

**基于 [1357310795/MyComputerManager](https://github.com/1357310795/MyComputerManager) v1.03 的二次开发**

---

A enhanced fork of [MyComputerManager](https://github.com/1357310795/MyComputerManager) with batch management features and bug fixes.

---

## 修改内容 / Changes

### 新增功能 / New Features

- **批量管理**：支持全选/取消全选、批量禁用、批量启用、批量删除操作
- **列表多选**：每个项目新增 CheckBox 选择框，支持多选操作
- **操作确认**：批量删除前弹出确认对话框，显示待删除项目名称，防止误操作

### Bug 修复 / Bug Fixes

- **Registry64 兼容性**：修复源码构建版本在 64 位系统上仅显示 1 个项目（应显示 4 个）的问题，通过 `RegistryView.Registry64` 回退机制解决

### 技术变更 / Technical Changes

| 文件 / File | 变更说明 / Description |
|---|---|
| `Models/NamespaceItem.cs` | 新增 `IsSelected` 属性，修复 `RegKey_CLSID` 的 Registry64 兼容性 |
| `ViewModels/MainPageViewModel.cs` | 新增批量操作命令（`BatchDelete`/`BatchDisable`/`BatchEnable`/`ToggleSelectAll`），注入 `IDialogService` |
| `MainWindow.xaml` | 顶栏新增批量操作工具栏按钮（始终可见） |
| `MainWindow.xaml.cs` | 新增 `GetMainPageVM()` 辅助方法及批量操作事件处理 |
| `Styles/ItemListStyle.xaml` | DataTemplate 中新增 CheckBox 绑定 `IsSelected` |
| `Converters/BoolToVisibilityConverter.cs` | 新增布尔值转可见性转换器 |
| `Helpers/NamespaceHelper.cs` | 添加 `RegistryView.Registry64` 回退，修复 64 位系统兼容性 |

## 构建 / Build

**环境要求 / Requirements**：
- Visual Studio 2019+ 或 MSBuild
- .NET Framework 4.7.2 SDK

**步骤 / Steps**：
```bash
# 恢复 NuGet 包
nuget restore MyComputerManager.sln

# 编译
msbuild MyComputerManager.sln /p:Configuration=Release
```

**输出路径 / Output**：
```
MyComputerManager\bin\Release\MyComputerManager.exe
```

## 原项目说明 / Original Project

### 背景 / Background

国内流氓软件经常通过 Shell Extension 在"此电脑"里塞快捷方式，用户无法轻易删除。本工具通过可视化界面管理注册表中的 Shell Namespace 扩展项，安全高效。

Bloatware often injects unwanted shortcuts into "This PC" via Shell Extensions. This tool provides a safe, visual interface to manage Shell Namespace registry entries.

### 功能 / Features

- 查看"此电脑"中所有 Shell Namespace 扩展项（系统 + 第三方）
- 启用/禁用/删除指定项目
- 添加自定义文件夹到"此电脑"
- Win11 风格 UI（基于 wpfui）

## 开源许可 / License

本项目基于 **GNU General Public License v3.0** 开源。

This project is licensed under the **GNU General Public License v3.0**.

## 致谢 / Credits

- 原项目作者 [@1357310795](https://github.com/1357310795) — [MyComputerManager](https://github.com/1357310795/MyComputerManager)
- [@lepoco](https://github.com/lepoco) — [wpfui](https://github.com/lepoco/wpfui)（Win11 风格控件）
- @walterlv 和 @XIU2 — [TileTool UI 讨论](https://github.com/XIU2/TileTool/pull/4)
