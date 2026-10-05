# Runs the same steps as the GitHub workflows on a local machine, for one platform.
#
#   1. Build the content with the Content Builder into the output folder of the game project.
#      This is what the MonoGame Build-Content action does in the workflows.
#   2. Restore and build the game project with WorkflowMode=true, so BuildContent.targets does not build the content again.
#   3. Publish the game project (not for iOS, which needs signing).
#
# Use -LocalMode to skip step 1 and let BuildContent.targets build the content during the game build instead,
# which is what happens when you build from an IDE.
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("DesktopGL", "DesktopVK", "WindowsDX12", "Android", "iOS")]
    [string]$Platform = "DesktopGL",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [Parameter(Mandatory = $false)]
    [string]$Runtime = "",

    [switch]$LocalMode,
    [switch]$SkipPublish
)

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot
$SolutionDir = Join-Path $RepoRoot "CBPlatformTest"
$ContentProject = Join-Path $SolutionDir "Content\Content.csproj"
$AssetsPath = Join-Path $SolutionDir "Content\Assets"

# Mirrors the matrix in .github/workflows/build.yml
$platformSettings = @{
    DesktopGL   = @{ Project = "CBPlatformTest.DesktopGL\CBPlatformTest.DesktopGL.csproj";     TFM = "net10.0";         DefaultRuntime = "win-x64";       Publish = $true }
    DesktopVK   = @{ Project = "CBPlatformTest.DesktopVK\CBPlatformTest.DesktopVK.csproj";     TFM = "net10.0";         DefaultRuntime = "win-x64";       Publish = $true }
    WindowsDX12 = @{ Project = "CBPlatformTest.WindowsDX12\CBPlatformTest.WindowsDX12.csproj"; TFM = "net10.0";         DefaultRuntime = "win-x64";       Publish = $true }
    Android     = @{ Project = "CBPlatformTest.Android\CBPlatformTest.Android.csproj";         TFM = "net10.0-android"; DefaultRuntime = "android-arm64"; Publish = $true }
    iOS         = @{ Project = "CBPlatformTest.iOS\CBPlatformTest.iOS.csproj";                 TFM = "net10.0-ios";     DefaultRuntime = "ios-arm64";     Publish = $false }
}

$settings = $platformSettings[$Platform]
if ($Runtime -eq "") { $Runtime = $settings.DefaultRuntime }
$projectPath = Join-Path $SolutionDir $settings.Project
$projectDir = Split-Path -Parent $projectPath

# iOS builds without a runtime identifier, so its output folder has no runtime folder.
if ($Platform -eq "iOS") {
    $outputDir = Join-Path $projectDir "bin\$Configuration\$($settings.TFM)"
} else {
    $outputDir = Join-Path $projectDir "bin\$Configuration\$($settings.TFM)\$Runtime"
}

function Invoke-Step([string]$Name, [scriptblock]$Action) {
    Write-Host "`n--- $Name ---" -ForegroundColor Yellow
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
    Write-Host "OK: $Name" -ForegroundColor Green
}

Write-Host "`n=== $Platform ($Runtime) $Configuration ===" -ForegroundColor Cyan
Write-Host "Project: $projectPath"
Write-Host "Output:  $outputDir"

if (-not $LocalMode) {
    # The builder writes a Content folder inside the folder given to -o, so pass the output folder of the game, not its Content folder.
    Invoke-Step "Build content" {
        dotnet run --project $ContentProject -c $Configuration -- build -p $Platform -s $AssetsPath -o $outputDir -i (Join-Path $projectDir "obj\$Configuration\content")
    }
    $contentFiles = Get-ChildItem -Path (Join-Path $outputDir "Content") -Recurse -File
    Write-Host "Content files: $($contentFiles.Count)"
}

Invoke-Step "Restore" { dotnet restore $projectPath -r $Runtime }

$workflowMode = if ($LocalMode) { "false" } else { "true" }
if ($Platform -eq "iOS") {
    Invoke-Step "Build" { dotnet build -c $Configuration $projectPath -p:WorkflowMode=$workflowMode }
} else {
    Invoke-Step "Build" { dotnet build -c $Configuration $projectPath -r $Runtime -p:WorkflowMode=$workflowMode }
}

if ($Platform -eq "Android") {
    $apk = Get-ChildItem -Path $outputDir -Filter "*.apk" -Recurse | Select-Object -First 1
    if ($apk) { Write-Host "Package: $($apk.FullName) ($([math]::Round($apk.Length / 1MB, 2)) MB)" }
}

if ($settings.Publish -and -not $SkipPublish) {
    Invoke-Step "Publish" { dotnet publish $projectPath -c $Configuration -r $Runtime -p:WorkflowMode=$workflowMode --self-contained }
    $publishDir = Join-Path $outputDir "publish"
    $publishContent = Join-Path $publishDir "Content"
    if (Test-Path $publishContent) {
        Write-Host "Content files in publish output: $((Get-ChildItem -Path $publishContent -Recurse -File).Count)"
    } elseif ($Platform -ne "Android") {
        Write-Host "WARNING: no Content folder in $publishDir" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
