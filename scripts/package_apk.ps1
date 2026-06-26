param(
    [ValidateSet("y41air", "y41")]
    [string]$Platform = "y41air",
    [ValidateSet("release", "debug")]
    [string]$BuildType = "release",
    [string]$GradleTask = "",
    [switch]$SendToFeishu,
    [string]$ChatId = "",
    [string]$FolderToken = "",
    [ValidateSet("auto", "drive-link", "im-file")]
    [string]$FeishuMode = "auto",
    [switch]$SkipClean,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$localProps = Join-Path $root "local.properties"
$mfph = Join-Path $root "app\GKPrep\mfph.properties"
$gradlew = Join-Path $root "gradlew.bat"
$copyRoot = Join-Path $root "build\apk"
$moduleOut = Join-Path $root "app\GKPrep\build\outputs\apk"
$sendFeishuScript = Join-Path $PSScriptRoot "send_apk_to_feishu.ps1"
$flutterUpgrader = Join-Path $root "library\LibAiCommon\AiCommon\src\main\java\com\coocaa\aicommon\flutter\FlutterUpgrader.kt"

function Convert-ToPascalCase([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $value
    }
    return $value.Substring(0, 1).ToUpperInvariant() + $value.Substring(1)
}

function Get-FlutterAppVersion([string]$path) {
    if (-not (Test-Path $path)) {
        return ""
    }

    $content = Get-Content -Raw -LiteralPath $path
    $match = [regex]::Match(
        $content,
        'private\s+fun\s+checkUpdate\s*\(\)\s*\{(?s:.*?)val\s+appVersion\s*:\s*Int\s*=\s*(\d+)'
    )
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return ""
}

if (-not (Test-Path $localProps)) {
    throw "Missing local.properties at $localProps"
}

$appLine = Get-Content $localProps | Where-Object { $_ -match '^\s*app\s*=' } | Select-Object -First 1
if (-not $appLine -or ($appLine -notmatch '^\s*app\s*=\s*GKPrep\s*$')) {
    throw "local.properties must contain app=GKPrep"
}

if (-not (Test-Path $mfph)) {
    throw "Missing mfph.properties at $mfph"
}

if ([string]::IsNullOrWhiteSpace($GradleTask)) {
    $variant = "GKPrepNormal$(Convert-ToPascalCase $Platform)$(Convert-ToPascalCase $BuildType)"
    $GradleTask = ":GKPrep:assemble$variant"
}
else {
    if ($GradleTask -match 'assemble(.+)$') {
        $variant = $Matches[1]
    }
}

if (-not $variant) {
    $variant = "GKPrepNormal$(Convert-ToPascalCase $Platform)$(Convert-ToPascalCase $BuildType)"
}

$flutterAppVersion = Get-FlutterAppVersion $flutterUpgrader

Write-Host "Preflight:"
Write-Host ("  local.properties: app=GKPrep")
Write-Host ("  mfph.properties: present")
Write-Host ("  platform: " + $Platform)
Write-Host ("  buildType: " + $BuildType)
Write-Host ("  variant: " + $variant)
Write-Host ("  flutter appVersion: " + $(if ([string]::IsNullOrWhiteSpace($flutterAppVersion)) { "not found" } else { $flutterAppVersion }))
Write-Host ("  clean before build: " + (-not $SkipClean -and -not $SkipBuild))
Write-Host ("  output roots: " + $copyRoot + " ; " + $moduleOut)

if (-not $SkipBuild) {
    if (-not (Test-Path $gradlew)) {
        throw "Missing gradlew.bat at $gradlew"
    }

    Push-Location $root
    try {
        if (-not $SkipClean) {
            Write-Host "Gradle clean: clean"
            & $gradlew clean
            if ($LASTEXITCODE -ne 0) {
                throw "Gradle clean failed with exit code $LASTEXITCODE"
            }
        }

        Write-Host ("Gradle task: " + $GradleTask)
        & $gradlew $GradleTask
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

$searchRoots = @()
if (Test-Path $copyRoot) { $searchRoots += $copyRoot }
if (Test-Path $moduleOut) { $searchRoots += $moduleOut }

if ($searchRoots.Count -eq 0) {
    if ($SkipBuild) {
        Write-Host "No existing APK output folders found under build/apk or app/GKPrep/build/outputs/apk"
        exit 0
    }
    throw "No APK output folders found under build/apk or app/GKPrep/build/outputs/apk"
}

$apk = Get-ChildItem -Path $searchRoots -Recurse -Filter "*$variant*.apk" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $apk) {
    if ($SkipBuild) {
        Write-Host "No existing APK file found for variant $variant"
        exit 0
    }
    throw "No APK file found after build"
}

Write-Host ("Variant: " + $variant)
Write-Host ("APK: " + $apk.FullName)

if ($SendToFeishu) {
    if (-not (Test-Path $sendFeishuScript)) {
        throw "Missing Feishu sender script at $sendFeishuScript"
    }

    $sendArgs = @(
        "-ApkPath", $apk.FullName,
        "-Variant", $variant,
        "-Mode", $FeishuMode,
        "-FlutterAppVersion", $flutterAppVersion
    )
    if (-not [string]::IsNullOrWhiteSpace($ChatId)) {
        $sendArgs += @("-ChatId", $ChatId)
    }
    if (-not [string]::IsNullOrWhiteSpace($FolderToken)) {
        $sendArgs += @("-FolderToken", $FolderToken)
    }

    try {
        & powershell -ExecutionPolicy Bypass -File $sendFeishuScript @sendArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Feishu send failed with exit code $LASTEXITCODE. APK has been built successfully."
        }
    } catch {
        Write-Warning ("Feishu send failed. APK has been built successfully. " + $_.Exception.Message)
    }
}
