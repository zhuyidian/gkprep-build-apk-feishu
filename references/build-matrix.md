# Build Matrix

## Required inputs

- `local.properties`: `app=GKPrep`
- `app/GKPrep/mfph.properties`: manifest placeholders for the selected flavor
- Default clean entrypoint: `.\gradlew.bat clean`
- Default Gradle entrypoint: `.\gradlew.bat :GKPrep:assembleGKPrepNormalY41airRelease`

## Variant selection

The app uses three flavor dimensions plus build type:

- APP: `GKPrep`
- DEVICE: `normal`
- PLATFORM: `y41air` or `y41`
- Build type: `release` or `debug`

Common tasks:

- `:GKPrep:assembleGKPrepNormalY41airRelease`
- `:GKPrep:assembleGKPrepNormalY41Release`
- `:GKPrep:assembleGKPrepNormalY41airDebug`
- `:GKPrep:assembleGKPrepNormalY41Debug`

## Output rules

- APK filename format: `${variant.name}_${variant.versionName}_${build_time}.apk`
- Primary outputs: `app/GKPrep/build/outputs/apk/**`
- Copied outputs: `build/apk/**`

## Project notes

- `app/GKPrep/build.gradle` applies the output rename and `copyApk` task.
- Signing varies by platform flavor (`platformCoocaa` / `platformNormal`).
- Feishu delivery uses `config/feishu.local.json`, uploads the APK to Drive, and sends a text message to the configured chat.
