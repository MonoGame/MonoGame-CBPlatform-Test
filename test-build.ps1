# Test script to validate content build and packaging locally
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Android", "iOS", "DesktopGL")]
    [string]$Platform = "Android",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot
$ContentProject = Join-Path $RepoRoot "CBPlatformTest\Content\Content.csproj"

# Platform-specific settings
$platformSettings = @{
    Android = @{
        Project = "CBPlatformTest\CBPlatformTest.Android\CBPlatformTest.Android.csproj"
        OutputDir = "CBPlatformTest\CBPlatformTest.Android"
        Runtime = "android-arm64"
        TFM = "net9.0-android"
        RIDPath = "bin\$Configuration\net9.0-android\android-arm64"
    }
    iOS = @{
        Project = "CBPlatformTest\CBPlatformTest.iOS\CBPlatformTest.iOS.csproj"
        OutputDir = "CBPlatformTest\CBPlatformTest.iOS"
        Runtime = "ios-arm64"
        TFM = "net9.0-ios"
        RIDPath = "bin\$Configuration\net9.0-ios"
    }
    DesktopGL = @{
        Project = "CBPlatformTest\CBPlatformTest.DesktopGL\CBPlatformTest.DesktopGL.csproj"
        OutputDir = "CBPlatformTest\CBPlatformTest.DesktopGL"
        Runtime = "win-x64"
        TFM = "net9.0"
        RIDPath = "bin\$Configuration\net9.0\win-x64"
    }
}

$settings = $platformSettings[$Platform]
$projectPath = Join-Path $RepoRoot $settings.Project
$outputDir = Join-Path $RepoRoot $settings.OutputDir
$contentOutputBase = Join-Path $outputDir "bin\$Configuration"
$contentOutputRID = Join-Path $outputDir $settings.RIDPath

Write-Host "`n=== Testing $Platform Build ===" -ForegroundColor Cyan
Write-Host "Configuration: $Configuration"
Write-Host "Project: $projectPath"
Write-Host "Output Dir: $outputDir"
Write-Host ""

# Step 1: Build content
Write-Host "`n--- Step 1: Building Content ---" -ForegroundColor Yellow
$assetsPath = Join-Path $RepoRoot "CBPlatformTest\Content\Assets"
$contentOutput = Join-Path $outputDir "bin\$Configuration"

Push-Location (Join-Path $RepoRoot "CBPlatformTest\Content")
try {
    Write-Host "Restoring content project..."
    dotnet restore
    
    Write-Host "Building content project..."
    dotnet build -c Release
    
    Write-Host "Running content pipeline..."
    $contentArgs = "build -p $Platform -s `"$assetsPath`" -o `"$contentOutput`" -i `"$outputDir\obj\$Configuration`""
    Write-Host "Command: dotnet run -c Release -- $contentArgs"
    Invoke-Expression "dotnet run -c Release -- $contentArgs"
    
    if ($LASTEXITCODE -ne 0) {
        throw "Content build failed with exit code: $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

# Verify content was created
$contentFolder = Join-Path $contentOutput "Content"
Write-Host "`nChecking for content at: $contentFolder"
if (Test-Path $contentFolder) {
    $contentFiles = Get-ChildItem -Path $contentFolder -Recurse -File
    Write-Host "✓ Content folder found with $($contentFiles.Count) files" -ForegroundColor Green
    $contentFiles | Select-Object -First 10 | ForEach-Object { Write-Host "  - $($_.FullName.Replace($contentFolder, 'Content'))" }
    if ($contentFiles.Count -gt 10) {
        Write-Host "  ... and $($contentFiles.Count - 10) more files"
    }
} else {
    Write-Host "✗ Content folder NOT found!" -ForegroundColor Red
    exit 1
}

# Step 2: Copy content to RID folder (simulate CI/CD behavior)
Write-Host "`n--- Step 2: Copying Content to RID Folder ---" -ForegroundColor Yellow
$ridContentFolder = Join-Path $contentOutputRID "Content"
Write-Host "Source: $contentFolder"
Write-Host "Destination: $ridContentFolder"

if (Test-Path $contentFolder) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $ridContentFolder) -Force | Out-Null
    Copy-Item -Path $contentFolder -Destination $ridContentFolder -Recurse -Force
    Write-Host "✓ Content copied to RID folder" -ForegroundColor Green
    
    $ridFiles = Get-ChildItem -Path $ridContentFolder -Recurse -File
    Write-Host "  RID folder now has $($ridFiles.Count) files"
}

# Step 3: Restore project
Write-Host "`n--- Step 3: Restoring Project ---" -ForegroundColor Yellow
dotnet restore $projectPath -r $settings.Runtime
if ($LASTEXITCODE -ne 0) {
    throw "Restore failed"
}
Write-Host "✓ Restore completed" -ForegroundColor Green

# Step 4: Build project
Write-Host "`n--- Step 4: Building Project ---" -ForegroundColor Yellow
Write-Host "Building with WorkflowMode=true (simulating CI/CD)"
if ($Platform -eq "iOS") {
    dotnet build -c $Configuration $projectPath -p:WorkflowMode=true -v:n
} else {
    dotnet build -c $Configuration $projectPath -r $settings.Runtime -p:WorkflowMode=true -v:n
}

if ($LASTEXITCODE -ne 0) {
    throw "Build failed"
}
Write-Host "✓ Build completed" -ForegroundColor Green

# Step 5: Check build output
Write-Host "`n--- Step 5: Checking Build Output ---" -ForegroundColor Yellow
$buildOutput = Join-Path $outputDir $settings.RIDPath

if (Test-Path $buildOutput) {
    Write-Host "Build output directory: $buildOutput"
    $outputFiles = Get-ChildItem -Path $buildOutput -File
    Write-Host "Files in build output: $($outputFiles.Count)"
    $outputFiles | ForEach-Object { Write-Host "  - $($_.Name)" }
    
    # Check for APK/AAB/APP
    $packageFiles = Get-ChildItem -Path $buildOutput -Filter "*.*pk*" -Recurse
    if ($packageFiles.Count -gt 0) {
        Write-Host "`nPackage files found:" -ForegroundColor Green
        $packageFiles | ForEach-Object { 
            Write-Host "  - $($_.FullName)" -ForegroundColor Green
            Write-Host "    Size: $([math]::Round($_.Length / 1MB, 2)) MB"
        }
    }
    
    # Check if Content folder exists in output (it shouldn't be loose for Android/iOS)
    $outputContent = Join-Path $buildOutput "Content"
    if (Test-Path $outputContent) {
        Write-Host "`n⚠ Warning: Loose Content folder found in build output" -ForegroundColor Yellow
        Write-Host "  For Android/iOS, content should be packed inside APK/IPA"
        $looseFiles = Get-ChildItem -Path $outputContent -Recurse -File
        Write-Host "  Contains $($looseFiles.Count) files"
    } else {
        Write-Host "`n✓ No loose Content folder (expected for Android/iOS)" -ForegroundColor Green
    }
} else {
    Write-Host "✗ Build output directory not found: $buildOutput" -ForegroundColor Red
}

# Step 6: Publish
Write-Host "`n--- Step 6: Publishing ---" -ForegroundColor Yellow
dotnet publish $projectPath -c $Configuration -r $settings.Runtime -p:WorkflowMode=true --self-contained

if ($LASTEXITCODE -ne 0) {
    throw "Publish failed"
}
Write-Host "✓ Publish completed" -ForegroundColor Green

# Step 7: Check publish output
Write-Host "`n--- Step 7: Checking Publish Output ---" -ForegroundColor Yellow
$publishOutput = Join-Path $outputDir "$($settings.RIDPath)\publish"

if (Test-Path $publishOutput) {
    Write-Host "Publish output directory: $publishOutput"
    $publishFiles = Get-ChildItem -Path $publishOutput -Recurse -File
    Write-Host "Total files in publish output: $($publishFiles.Count)"
    
    # Check for packages
    $publishPackages = $publishFiles | Where-Object { $_.Extension -match '\.(apk|aab|app|ipa)$' }
    if ($publishPackages.Count -gt 0) {
        Write-Host "`nPackage files:" -ForegroundColor Green
        $publishPackages | ForEach-Object {
            Write-Host "  - $($_.Name)" -ForegroundColor Green
            Write-Host "    Size: $([math]::Round($_.Length / 1MB, 2)) MB"
            Write-Host "    Path: $($_.FullName)"
        }
    }
    
    # Check for content
    $publishContent = Join-Path $publishOutput "Content"
    if (Test-Path $publishContent) {
        $contentFiles = Get-ChildItem -Path $publishContent -Recurse -File
        Write-Host "`nContent in publish output: $($contentFiles.Count) files" -ForegroundColor Green
    } else {
        Write-Host "`n⚠ Warning: No Content folder in publish output" -ForegroundColor Yellow
        if ($Platform -eq "Android" -or $Platform -eq "iOS") {
            Write-Host "  (Content should be packed inside APK/IPA for mobile platforms)"
        }
    }
} else {
    Write-Host "✗ Publish output directory not found: $publishOutput" -ForegroundColor Red
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
Write-Host "Check the output above for any issues."
