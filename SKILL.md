---
name: gkprep-build-apk
description: Build or package the active GKPrep or WrapperApp Android app in this repository, optionally uploading the generated APK to a Feishu/Lark group. Use when asked to generate an APK, run a Gradle build, locate the latest APK output, send the APK to Feishu, or check packaging prerequisites such as local.properties, mfph.properties, signing configs, or variant selection.
---

# Android App Build APK

## Overview

Use this skill to produce the `GKPrep` or `WrapperApp` APK with the Gradle flow the project already uses. Run Gradle only when the user explicitly asks to build or package; otherwise use `-SkipBuild` for a local output lookup.

## Workflow

1. Confirm the repo is configured for the active app:
   - `local.properties` must contain `app=GKPrep` or `app=WrapperApp`
   - `app/<active-app>/mfph.properties` must exist
2. Clean old build outputs before packaging:
   - Default: `.\gradlew.bat clean`
   - Skip only when explicitly requested: `scripts/package_apk.ps1 -SkipClean`
3. Build from the repo root with a selected variant:
   - GKPrep default: `.\gradlew.bat :GKPrep:assembleGKPrepNormalY41airRelease`
   - WrapperApp default: `.\gradlew.bat :WrapperApp:assembleWrapperAppNormalY41airRelease`
   - All variants: `.\gradlew.bat :<active-app>:assemble`
4. Use the existing project output naming rule:
   - `${variant.name}_${variant.versionName}_${build_time}.apk`
5. Look for the APK in:
   - `app/<active-app>/build/outputs/apk/**`
   - `build/apk/**` after the project's copy task runs
6. If you need a repeatable one-command flow, run `scripts/package_apk.ps1`.
   - Default app: read `local.properties`; select explicitly with `-App GKPrep` or `-App WrapperApp`
   - Default channel/platform: `y41air`
   - Select Y41: `scripts/package_apk.ps1 -Platform y41`
   - Select debug: `scripts/package_apk.ps1 -BuildType debug`
   - Send to Feishu: `scripts/package_apk.ps1 -SendToFeishu`
   - The script prints a preflight summary before building
   - Feishu messages include the Flutter upgrade appVersion parsed from `FlutterUpgrader.checkUpdate()`

## Usage Examples

- "Build the APK"
- "Build the WrapperApp APK"
- "Package the y41 release APK"
- "Generate a y41air debug APK"
- "Build with platform y41 and buildType debug"
- "Build y41air release and send it to Feishu"

## Script Parameters

```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\gkprep-build-apk\scripts\package_apk.ps1 -App WrapperApp -Platform y41 -BuildType release
```

- `-App`: `auto` (default), `GKPrep`, or `WrapperApp`. `auto` reads the active app from `local.properties`; an explicit app must match it.
- `-Platform`: `y41air` or `y41`
- `-BuildType`: `release` or `debug`
- `-SkipClean`: do not run `.\gradlew.bat clean` before building
- `-SkipBuild`: only locate the latest matching APK without rebuilding
- `-SendToFeishu`: upload the APK to Feishu Drive and send a group message
- `-ChatId`: override the configured Feishu group id
- `-FolderToken`: override the configured Feishu Drive folder token

## Preflight Checklist

- `local.properties` contains `app=GKPrep` or `app=WrapperApp`
- The requested app matches `local.properties`
- `app/<active-app>/mfph.properties` exists
- Selected platform matches the intended flavor
- Selected build type matches the intended output
- Clean is enabled unless `-SkipClean` or `-SkipBuild` is used
- Target APK name should include the selected variant and version

## Feishu Delivery

Copy `config/feishu.example.json` to `config/feishu.local.json` and fill the app credentials and default group. Do not commit `feishu.local.json`.

```powershell
powershell -ExecutionPolicy Bypass -File .\.agents\skills\gkprep-build-apk\scripts\package_apk.ps1 -App WrapperApp -Platform y41air -BuildType release -SendToFeishu
```

The APK build remains successful even if the Feishu upload or message send fails. Report both the local APK path and any Feishu error.

Without `-SendToFeishu`, packaging only produces a local APK and deliberately skips the Feishu upload.

APK files are usually too large for Feishu IM file messages. Use `drive-link` mode and set `default_folder_token` in `config/feishu.local.json`, or pass `-FolderToken`.

## Common Checks

- Missing or unsupported `app` in `local.properties`
- `-App` differs from the active app in `local.properties`
- Missing `mfph.properties`
- Internal Maven or VPN access problems
- Signing config mismatch when the active platform flavor changes

## References

See [build-matrix.md](references/build-matrix.md) for the repo-specific packaging rules.
