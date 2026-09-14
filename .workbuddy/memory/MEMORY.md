# 项目长期记忆 — MyComputerManager-awa

## 项目概况

- 仓库：https://github.com/longteng-H/MyComputerManager-awa （`1357310795/MyComputerManager` v1.03 的二次开发分支）
- 技术栈：WPF / .NET Framework **4.7.2** / Wpf.Ui **2.0.1** / Microsoft.Extensions.Hosting + DI / MVVM
- 依赖管理：**packages.config**（非 PackageReference），包目录为 `packages\Id.Version\`
- 版本号集中在 `Directory.Build.props`（当前 Version=0.1.0、LangVersion=10.0）
- `app.manifest` 的 `requestedExecutionLevel` 处于**注释状态**（默认 asInvoker，不自动提权）
- Release|AnyCPU 产物：`MyComputerManager\bin\Release\MyComputerManager.exe`

## 打包约定（重要）

**单文件发布必须用 Costura.Fody「嵌入」，禁止用 ILMerge「合并」。**

原因：WPF 在编译期把 pack URI 硬编码进生成代码（`obj\Release\App.g.cs`）：
`new Uri("/MyComputerManager;component/app.xaml", UriKind.Relative)`。
ILMerge 会把输出程序集重命名为 `/out` 指定的文件名（如 `MyComputerManager-merged`），导致该 URI 无法解析，程序在 `App.InitializeComponent()` 抛 `System.Exception` 后静默退出（双击无反应）。
同理 `Wpf.Ui.dll` 内部也用 `/Wpf.Ui;component/...` 引用自身资源，因此改 `/out` 名称也救不了 —— ILMerge 对本项目整体不可行。

正确做法：`FodyWeavers.xml` 配 `<Costura />`，并把 `Fody` + `Costura.Fody` 记入 `packages.config`；
csproj 需同时导入 `Costura.Fody.props`（注册 `WeaverFiles`，**漏了它 Fody 找不到 weaver**）与 `Fody.targets`。

**防坑**：`<Import ... Condition="Exists(...)">` 在路径写错时是**静默跳过**，构建照常成功但编织不生效。
本项目曾在 `EnsureNuGetPackageBuildImports` 中对 Fody/Costura 加了 `<Error>` 守卫，修改导入路径时不要移除。

### 一键打包脚本

根目录 `build.ps1`（+ 双击用 `build.bat`）是打包入口：

```powershell
.\build.ps1              # 打包 + 校验，输出到 dist\
.\build.ps1 -SmokeTest   # 追加隔离启动测试
```

脚本会拦截三类静默失败：程序集名不是 `MyComputerManager`、无 `costura.*` 内嵌资源、输出目录残留依赖 DLL。
改动构建配置后，请同步检查脚本里 `$ExpectedEmbedded` 那份 38 个依赖程序集的清单。

**分发是「exe + exe.config」两个文件**：`MyComputerManager.exe.config` 含 4 条 NuGet 自动生成的
`bindingRedirect`（System.Drawing.Common、System.Runtime.CompilerServices.Unsafe、
Microsoft.Extensions.Configuration.EnvironmentVariables / .UserSecrets），不能省略。

### 源码备份

`F:\ai开发\MyComputerManager\_backups\MyComputerManager-1.03_<时间戳>`（与项目同级，避免被自身递归打包）。
命令：`robocopy <项目> <备份> /E /XD bin obj .vs`。

## 本机环境与工具注意事项

- VS 为 **Build Tools 18**：`C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\MSBuild.exe`
- **PowerShell 工具会拦截 MSBuild / dotnet 等 LOLBin**，无法在本机代跑编译；即使用户授权也仍拦截。
  拦截是对命令文本里的**文件名做子串匹配**，连只做 `Test-Path` 的探测命令都会被拦。
  按规则不得绕过（不可借 node / 脚本转手调用），应停下来交付脚本交由用户执行
- **Bash 通道不可用**：`PortableGit\...\bash.exe` 下 `ls`/`dirname` 均 `command not found`（PATH 缺失）
- shell 命令的输出捕获不稳定：稳妥做法是把结果写入 `%TEMP%` 文件，再用 Read 读取
- 用 `powershell -File` 执行含中文路径的脚本会因编码错乱失败：脚本内容保持纯 ASCII，中文路径通过命令行参数传入
- 但**脚本本身给用户跑时**需要中文可读 → 用 UTF-8 **带 BOM** 写 `build.ps1`（PS 5.1 读中文必须有 BOM）；
  `.bat` 保持纯 ASCII（cmd.exe 代码页会乱码），路径一律用 `%~dp0` 推导，不写死盘符
- 检查 .NET 程序集元数据（程序集名 / 引用表 / 资源清单）可用 `AssemblyName::GetAssemblyName` 与
  `Assembly::ReflectionOnlyLoadFrom`，只读且不执行代码
- 校验 .ps1 语法而不执行：`[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$null,[ref]$errs)`

