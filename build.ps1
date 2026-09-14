#Requires -Version 5.1
<#
.SYNOPSIS
    MyComputerManager 单文件（Costura.Fody）打包脚本。

.DESCRIPTION
    按顺序完成打包，并在打包后做产物校验：

      1. 预检：Fody 6.9.3 / Costura.Fody 6.2.0 的 NuGet 包是否就位。
         这一步专门用来拦截"导入被 Condition=Exists 静默跳过"的旧故障。
      2. 定位 MSBuild：vswhere -> 常见安装路径 -> PATH。
      3. 以 Release 重新生成解决方案（Rebuild，确保 Costura 重新织入）。
      4. 校验产物确实是单文件：
           - 程序集名必须是 MyComputerManager（ILMerge 会改名成 -merged，
             导致 WPF 的 pack URI 解析失败，这里直接拦下）
           - 必须存在 costura.* 内嵌资源，且覆盖全部预期的依赖程序集
           - 输出目录不得残留任何依赖 DLL
      5. 把自包含产物复制到 dist\。

.PARAMETER Configuration
    生成配置，默认 Release。

.PARAMETER SmokeTest
    额外做一次隔离启动测试：把 exe 单独复制到一个临时空目录并启动它，
    确认它能独立运行（不依赖同级 DLL），随后自动关闭进程。

.EXAMPLE
    .\build.ps1
    仅打包 + 校验，输出到 dist\。

.EXAMPLE
    .\build.ps1 -SmokeTest
    打包 + 校验 + 隔离启动测试。

.NOTES
    若 PowerShell 提示"无法加载文件，因为在此系统上禁止运行脚本"，
    请改用同目录下的 build.bat，它会带上 -ExecutionPolicy Bypass。
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [switch]$SmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FailureCount = 0

function Write-Step { param([string]$Text) Write-Host ''; Write-Host ("=== " + $Text) -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host ("  [OK]   " + $Text) -ForegroundColor Green }
function Write-Bad  { param([string]$Text) Write-Host ("  [FAIL] " + $Text) -ForegroundColor Red; $script:FailureCount++ }
function Write-Info { param([string]$Text) Write-Host ("  " + $Text) -ForegroundColor Gray }
function Write-Warn2{ param([string]$Text) Write-Host ("  [WARN] " + $Text) -ForegroundColor Yellow }

# --------------------------------------------------------------------------
# 路径
# --------------------------------------------------------------------------
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Root) { $Root = (Get-Location).Path }
$Root    = (Resolve-Path -LiteralPath $Root).Path

$Sln     = Join-Path $Root 'MyComputerManager.sln'
$Proj    = Join-Path $Root 'MyComputerManager\MyComputerManager.csproj'
$OutDir  = Join-Path $Root ("MyComputerManager\bin\" + $Configuration)
$Dist    = Join-Path $Root 'dist'
$ExeName = 'MyComputerManager.exe'
$CfgName = $ExeName + '.config'
$ExePath = Join-Path $OutDir $ExeName

$PackagesDir   = Join-Path $Root 'packages'
$FodyTargets   = Join-Path $PackagesDir 'Fody.6.9.3\build\Fody.targets'
$CosturaProps  = Join-Path $PackagesDir 'Costura.Fody.6.2.0\build\Costura.Fody.props'
$CosturaTargets= Join-Path $PackagesDir 'Costura.Fody.6.2.0\build\Costura.Fody.targets'

# 期望被 Costura 内嵌进主程序集的依赖（取自上一次正常构建的输出目录）
$ExpectedEmbedded = @(
    'Microsoft.Bcl.AsyncInterfaces'
    'Microsoft.Extensions.Configuration'
    'Microsoft.Extensions.Configuration.Abstractions'
    'Microsoft.Extensions.Configuration.Binder'
    'Microsoft.Extensions.Configuration.CommandLine'
    'Microsoft.Extensions.Configuration.EnvironmentVariables'
    'Microsoft.Extensions.Configuration.FileExtensions'
    'Microsoft.Extensions.Configuration.Json'
    'Microsoft.Extensions.Configuration.UserSecrets'
    'Microsoft.Extensions.DependencyInjection'
    'Microsoft.Extensions.DependencyInjection.Abstractions'
    'Microsoft.Extensions.FileProviders.Abstractions'
    'Microsoft.Extensions.FileProviders.Physical'
    'Microsoft.Extensions.FileSystemGlobbing'
    'Microsoft.Extensions.Hosting'
    'Microsoft.Extensions.Hosting.Abstractions'
    'Microsoft.Extensions.Logging'
    'Microsoft.Extensions.Logging.Abstractions'
    'Microsoft.Extensions.Logging.Configuration'
    'Microsoft.Extensions.Logging.Console'
    'Microsoft.Extensions.Logging.Debug'
    'Microsoft.Extensions.Logging.EventLog'
    'Microsoft.Extensions.Logging.EventSource'
    'Microsoft.Extensions.Options'
    'Microsoft.Extensions.Options.ConfigurationExtensions'
    'Microsoft.Extensions.Primitives'
    'Microsoft.Xaml.Behaviors'
    'System.Buffers'
    'System.Diagnostics.DiagnosticSource'
    'System.Drawing.Common'
    'System.Memory'
    'System.Numerics.Vectors'
    'System.Runtime.CompilerServices.Unsafe'
    'System.Text.Encodings.Web'
    'System.Text.Json'
    'System.Threading.Tasks.Extensions'
    'System.ValueTuple'
    'Wpf.Ui'
)

Write-Host ''
Write-Host 'MyComputerManager 单文件打包' -ForegroundColor White
Write-Info ("项目根目录 : " + $Root)
Write-Info ("生成配置   : " + $Configuration)
Write-Info ("输出目录   : " + $OutDir)

# --------------------------------------------------------------------------
# 1. 预检
# --------------------------------------------------------------------------
Write-Step '1/5 预检 NuGet 包与工程文件'

if (-not (Test-Path -LiteralPath $Sln))  { Write-Bad ("找不到解决方案: " + $Sln) }
else { Write-Ok 'MyComputerManager.sln 存在' }

if (-not (Test-Path -LiteralPath $Proj)) { Write-Bad ("找不到工程文件: " + $Proj) }
else { Write-Ok 'MyComputerManager.csproj 存在' }

$packOk = $true
foreach ($pair in @(
    @{ Path = $FodyTargets;    Label = 'packages\Fody.6.9.3\build\Fody.targets' }
    @{ Path = $CosturaProps;   Label = 'packages\Costura.Fody.6.2.0\build\Costura.Fody.props' }
    @{ Path = $CosturaTargets; Label = 'packages\Costura.Fody.6.2.0\build\Costura.Fody.targets' }
)) {
    if (Test-Path -LiteralPath $pair.Path) {
        Write-Ok ('包文件就位: ' + $pair.Label)
    }
    else {
        Write-Bad ('包文件缺失: ' + $pair.Label)
        $packOk = $false
    }
}

if (-not $packOk) {
    Write-Host ''
    Write-Host '包目录不完整，Costura 不会生效。请在 Visual Studio 里对解决方案执行一次' -ForegroundColor Yellow
    Write-Host '"还原 NuGet 包"，或运行:  nuget restore MyComputerManager.sln' -ForegroundColor Yellow
    Write-Host '注意 packages 目录必须是带版本号的命名（例如 Fody.6.9.3），' -ForegroundColor Yellow
    Write-Host '否则 csproj 里的 Condition=Exists 会静默跳过导入。' -ForegroundColor Yellow
    exit 1
}

# --------------------------------------------------------------------------
# 2. 定位 MSBuild
# --------------------------------------------------------------------------
Write-Step '2/5 定位 MSBuild'

$MSBuild = $null

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if ($vswhere -and (Test-Path -LiteralPath $vswhere)) {
    Write-Info ('vswhere: ' + $vswhere)
    $install = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null
    if ($install) {
        $install = ($install | Select-Object -First 1).Trim()
        $cand = Join-Path $install 'MSBuild\Current\Bin\MSBuild.exe'
        if (Test-Path -LiteralPath $cand) { $MSBuild = $cand }
    }
}
else {
    Write-Info 'vswhere 不存在，改用路径扫描'
}

if (-not $MSBuild) {
    $roots = @(${env:ProgramFiles}, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($r in $roots) {
        $hit = Get-ChildItem -Path (Join-Path $r 'Microsoft Visual Studio\*\*\MSBuild\Current\Bin\MSBuild.exe') -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { $MSBuild = $hit.FullName; break }
    }
}

if (-not $MSBuild) {
    $cmdB = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($cmdB) { $MSBuild = $cmdB.Source }
}

if (-not $MSBuild) {
    Write-Bad '找不到 MSBuild.exe'
    Write-Host '请安装 Visual Studio 或 "Visual Studio 生成工具"（含 .NET 桌面开发工作负载），' -ForegroundColor Yellow
    Write-Host '或直接在 Visual Studio 中打开 MyComputerManager.sln 手动生成 Release。' -ForegroundColor Yellow
    exit 1
}

Write-Ok ('MSBuild: ' + $MSBuild)

# --------------------------------------------------------------------------
# 3. 重新生成
# --------------------------------------------------------------------------
Write-Step '3/5 重新生成解决方案（Release / Rebuild）'

Write-Info '命令: MSBuild MyComputerManager.sln /t:Rebuild /p:Configuration=' + $Configuration
Write-Host ''

& $MSBuild $Sln /t:Rebuild /p:Configuration=$Configuration /verbosity:minimal /nologo
$buildExit = $LASTEXITCODE

Write-Host ''
if ($buildExit -ne 0) {
    Write-Bad ('MSBuild 返回非零退出码: ' + $buildExit)
    Write-Host '编译失败，请检查上面的错误信息。常见原因：' -ForegroundColor Yellow
    Write-Host '  - 缺少 .NET Framework 4.7.2 开发工具包（Targeting Pack）' -ForegroundColor Yellow
    Write-Host '  - 缺少 NuGet 包，先执行还原' -ForegroundColor Yellow
    exit 1
}
Write-Ok 'MSBuild 编译成功'

# --------------------------------------------------------------------------
# 4. 校验产物
# --------------------------------------------------------------------------
Write-Step '4/5 校验单文件产物'

if (-not (Test-Path -LiteralPath $ExePath)) {
    Write-Bad ('产物不存在: ' + $ExePath)
    exit 1
}

$exeItem = Get-Item -LiteralPath $ExePath
Write-Info ('产物: {0}  ({1:N2} MB)  {2}' -f $exeItem.Name, ($exeItem.Length / 1MB), $exeItem.LastWriteTime)

# 4.1 程序集名
try {
    $an = [System.Reflection.AssemblyName]::GetAssemblyName($ExePath)
    if ($an.Name -eq 'MyComputerManager') {
        Write-Ok ('程序集名 = ' + $an.Name + '  (v' + $an.Version + ')')
    }
    else {
        Write-Bad ('程序集名 = ' + $an.Name + '，期望 MyComputerManager')
        Write-Host '  这正是之前单文件无法启动的根因：程序集被改名后，' -ForegroundColor Yellow
        Write-Host '  WPF 编译期写死的 pack URI "/MyComputerManager;component/app.xaml" 会解析失败。' -ForegroundColor Yellow
        Write-Host '  请确认没有对产物再执行 ILMerge / ILRepack 之类的合并改名操作。' -ForegroundColor Yellow
    }
}
catch {
    Write-Bad ('读取程序集标识失败: ' + $_.Exception.Message)
}

# 4.2 内嵌资源
try {
    $asm  = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($ExePath)
    $res  = @($asm.GetManifestResourceNames())
    $cst  = @($res | Where-Object { $_ -like 'costura.*' })
    Write-Info ('资源总数: ' + $res.Count + '，其中 costura.* : ' + $cst.Count)

    if ($cst.Count -eq 0) {
        Write-Bad '产物里没有任何 costura.* 资源 —— Costura 没有织入'
        Write-Host '  说明 Fody 目标未生效。请确认 csproj 顶部已导入 Costura.Fody.props、' -ForegroundColor Yellow
        Write-Host '  底部已导入 Fody.targets 与 Costura.Fody.targets，且 packages 目录带版本号。' -ForegroundColor Yellow
    }
    else {
        Write-Ok ('Costura 已织入，内嵌 ' + $cst.Count + ' 个资源')

        $missing = @()
        foreach ($name in $ExpectedEmbedded) {
            $pat = '^(?i)costura\.' + [regex]::Escape($name) + '\.dll(\.compressed)?$'
            if (-not ($cst | Where-Object { $_ -match $pat })) { $missing += $name }
        }
        if ($missing.Count -eq 0) {
            Write-Ok ('预期的 ' + $ExpectedEmbedded.Count + ' 个依赖程序集全部已内嵌')
        }
        else {
            Write-Bad ('有 ' + $missing.Count + ' 个依赖未内嵌: ' + ($missing -join ', '))
        }
    }
}
catch {
    Write-Warn2 ('反射读取资源清单失败（可能缺少依赖解析上下文）: ' + $_.Exception.Message)
}

# 4.3 输出目录不得残留依赖 DLL
$loose = @(Get-ChildItem -LiteralPath $OutDir -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Extension -ieq '.dll' })
if ($loose.Count -eq 0) {
    Write-Ok '输出目录没有残留依赖 DLL，exe 自包含'
}
else {
    Write-Bad ('输出目录仍有 ' + $loose.Count + ' 个 DLL，exe 不构成单文件')
    $loose | Select-Object -First 10 | ForEach-Object { Write-Info ('   ' + $_.Name) }
    if ($loose.Count -gt 10) { Write-Info ('   ... 其余 ' + ($loose.Count - 10) + ' 个') }
}

# --------------------------------------------------------------------------
# 5. 输出到 dist
# --------------------------------------------------------------------------
Write-Step '5/5 输出到 dist'

if (-not (Test-Path -LiteralPath $Dist)) {
    New-Item -ItemType Directory -Path $Dist -Force | Out-Null
    Write-Ok ('已创建: ' + $Dist)
}

Copy-Item -LiteralPath $ExePath -Destination (Join-Path $Dist $ExeName) -Force
Write-Ok ('dist\' + $ExeName)

$cfgSrc = Join-Path $OutDir $CfgName
if (Test-Path -LiteralPath $cfgSrc) {
    Copy-Item -LiteralPath $cfgSrc -Destination (Join-Path $Dist $CfgName) -Force
    Write-Ok ('dist\' + $CfgName + '   (含 bindingRedirect，必须与 exe 同行)')
}
else {
    Write-Warn2 ($CfgName + ' 不存在，未复制')
}

# --------------------------------------------------------------------------
# 可选：隔离启动测试
# --------------------------------------------------------------------------
if ($SmokeTest) {
    Write-Step '附加 隔离启动测试'

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('mcm_singlefile_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    Write-Info ('临时空目录: ' + $tmp)

    Copy-Item -LiteralPath $ExePath -Destination (Join-Path $tmp $ExeName) -Force
    if (Test-Path -LiteralPath $cfgSrc) { Copy-Item -LiteralPath $cfgSrc -Destination (Join-Path $tmp $CfgName) -Force }

    $target = Join-Path $tmp $ExeName
    $proc = Start-Process -FilePath $target -PassThru
    Start-Sleep -Seconds 6

    if ($proc.HasExited) {
        Write-Bad ('进程在 6 秒内退出，退出码 = ' + $proc.ExitCode + ' —— 单文件启动失败')
        Write-Info '可查看 Windows 事件日志 "应用程序" 里的 .NET Runtime 崩溃记录定位原因。'
    }
    else {
        Write-Ok '进程存活，单文件可脱离同级 DLL 独立启动'
        try { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 1 } catch { }
        if (-not $proc.HasExited) { try { $proc.Kill() } catch { } }
        Write-Info '已关闭测试进程'
    }

    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------------
# 汇总
# --------------------------------------------------------------------------
Write-Host ''
if ($script:FailureCount -eq 0) {
    Write-Host '打包完成，全部校验通过。' -ForegroundColor Green
    Write-Host ('产物目录: ' + $Dist) -ForegroundColor Green
    Write-Host ''
    Write-Host '手工验收方式：把 dist 里的 exe 与 exe.config 一起复制到一个空文件夹，双击运行。' -ForegroundColor Gray
    exit 0
}
else {
    Write-Host ('打包结束，但有 ' + $script:FailureCount + ' 项校验未通过，请看上面的 [FAIL]。') -ForegroundColor Red
    exit 1
}
