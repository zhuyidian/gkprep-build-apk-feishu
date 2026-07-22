# Build Matrix

## Required inputs

- `local.properties`: `app=GKPrep` or `app=WrapperApp`
- `app/<active-app>/mfph.properties`: manifest placeholders for the selected flavor
- Default clean entrypoint: `.\gradlew.bat clean`
- GKPrep default Gradle entrypoint: `.\gradlew.bat :GKPrep:assembleGKPrepNormalY41airRelease`
- WrapperApp default Gradle entrypoint: `.\gradlew.bat :WrapperApp:assembleWrapperAppNormalY41airRelease`

## Variant selection

The app uses three flavor dimensions plus build type:

- APP: `GKPrep` or `WrapperApp`
- DEVICE: `normal`
- PLATFORM: `y41air` or `y41`
- Build type: `release` or `debug`

Common GKPrep tasks:

- `:GKPrep:assembleGKPrepNormalY41airRelease`
- `:GKPrep:assembleGKPrepNormalY41Release`
- `:GKPrep:assembleGKPrepNormalY41airDebug`
- `:GKPrep:assembleGKPrepNormalY41Debug`

Common WrapperApp tasks:

- `:WrapperApp:assembleWrapperAppNormalY41airRelease`
- `:WrapperApp:assembleWrapperAppNormalY41Release`
- `:WrapperApp:assembleWrapperAppNormalY41airDebug`
- `:WrapperApp:assembleWrapperAppNormalY41Debug`

## Output rules

- APK filename format: `${variant.name}_${variant.versionName}_${build_time}.apk`
- Primary outputs: `app/<active-app>/build/outputs/apk/**`
- Copied outputs: `build/apk/**`

## Project notes

- Both `app/GKPrep/build.gradle` and `app/WrapperApp/build.gradle` apply the output rename and `copyApk` task.
- Signing varies by platform flavor (`platformCoocaa` / `platformNormal`).
- Feishu delivery uses `config/feishu.local.json`, uploads the APK to Drive, and sends a text message to the configured chat.
