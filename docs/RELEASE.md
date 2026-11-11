# Release pipeline

Pushing a `v*` tag builds the app on GitHub Actions, uploads it to **TestFlight** (iOS) and the **Play internal testing track** (Android), and sends the debug symbols to Sentry. A push to `main` that touches `backend/` builds the backend image, pushes it to GHCR and deploys it to the VM.

> **Status:** the pipeline is written and lint-checked, but **no build has shipped yet**. The resume line "Fastlane + GitHub Actions releases to TestFlight and Play" becomes true only after at least one build has reached TestFlight **and** one has reached Play internal testing through these workflows. When that happens, add the screenshots `docs/testflight.png` and `docs/play-internal.png` and update this line.

| Workflow | Trigger | Runner | What it does |
|---|---|---|---|
| `app-ci.yml` | push to `main`, PRs (`app/**`) | ubuntu | `pub get` → `build_runner` (drift) → `analyze` → `test`; `e2e` job runs `integration_test/` on an Android emulator |
| `backend-ci.yml` | push to `main`, PRs (`backend/**`) | ubuntu | `npm ci` → lint → test → build → `docker build`; on `main` also pushes `ghcr.io/elysian12/pawsense-backend` and deploys over SSH |
| `release-android.yml` | tag `v*`, manual | ubuntu | signed, obfuscated AAB → Sentry symbols → `fastlane internal` |
| `release-ios.yml` | tag `v*`, manual | macOS | Flutter config → `fastlane beta` (archive, sign, TestFlight) → Sentry symbols |

## Fastlane in one paragraph

[Fastlane](https://docs.fastlane.tools) is a Ruby CLI that scripts the store chores: code signing, archiving and uploading. A **lane** is a named Ruby block in `fastlane/Fastfile` that calls **actions** (`build_app`, `upload_to_testflight`, `upload_to_play_store`, …). The `Appfile` holds the app identifiers. Both platforms share one pinned Gemfile at `app/Gemfile` (+ `Gemfile.lock`), so CI and your laptop run the same fastlane version:

```sh
cd app && bundle install
cd ios && BUNDLE_GEMFILE=../Gemfile bundle exec fastlane lanes
```

| Lane | File | Does |
|---|---|---|
| `ios beta` | `app/ios/fastlane/Fastfile` | temporary keychain → import the distribution cert → install the App Store profile → switch Release to manual signing → `build_app` (archive + export IPA) → `upload_to_testflight` with the App Store Connect API key |
| `android internal` | `app/android/fastlane/Fastfile` | `upload_to_play_store(track: "internal")` for the AAB that `flutter build appbundle` produced |

**Why Flutter builds outside the lanes:** the Sentry upload needs the `--split-debug-info` output and the obfuscation map, so the workflows run the `flutter build` themselves. On Android the lane only uploads. On iOS, `flutter build ios --config-only` writes `ios/Flutter/Generated.xcconfig` (entrypoint, version, dart-defines, obfuscation flags), and Xcode's Flutter build phase compiles the Dart code with those settings during the lane's `build_app` archive.

## Versioning

- `--build-name` comes from the tag: `v0.2.0` → `0.2.0`. A manual run (`workflow_dispatch`) uses the `version:` in `pubspec.yaml`.
- `--build-number` is `github.run_number`, so every upload has a new, increasing build number (App Store Connect and Play both reject duplicates).

## Obfuscation and Sentry symbols

Release builds use `--obfuscate --split-debug-info=build/debug-info --extra-gen-snapshot-options=--save-obfuscation-map=build/app/obfuscation.map.json`:

- `--obfuscate` renames Dart symbols in the binary. `--split-debug-info` strips the debug info into `build/debug-info/app.<platform>-<arch>.symbols`, which makes the app smaller.
- Without those files, Sentry stack traces from release builds are unreadable. The workflows upload them with `sentry-cli debug-files upload`. On iOS they also upload the `Runner.app.dSYM.zip` from the archive, for native frames.
- The obfuscation map translates obfuscated Dart type names back, e.g. in issue titles. `sentry-cli dart-symbol-map upload` links it to each `.symbols` file's debug ID.

These steps are skipped when `SENTRY_AUTH_TOKEN` is not set, so a release still works without Sentry.

## One-time manual prerequisites

These cost money or need a human identity check, so they can't be automated.

### Apple (TestFlight)

1. Join the **Apple Developer Program** ($99/yr).
2. **Certificates, Identifiers & Profiles → Identifiers:** register the App ID `com.elysian12.pawsense`.
3. **App Store Connect → Apps → +:** create the app with that bundle ID. The first upload fails if the app record doesn't exist.
4. **Distribution certificate:** create an *Apple Distribution* certificate, import it into Keychain Access, and export it with its private key as a `.p12` with a password.
5. **Provisioning profile:** create an *App Store Connect* distribution profile for `com.elysian12.pawsense` using that certificate, then download the `.mobileprovision`. The lane reads the profile's name and team ID from the file itself.
6. **API key:** App Store Connect → Users and Access → Integrations → App Store Connect API → generate a key with the **App Manager** role. Download `AuthKey_<KEYID>.p8` (you can only download it once) and note the **Key ID** and **Issuer ID**.

### Google Play (internal testing)

1. Create a **Google Play Console** developer account ($25 one-time) and complete identity verification.
2. **Create app** `PawSense`, then fill in the required App content declarations so testing tracks are allowed.
3. **Upload key:** generate it once and keep a backup outside the repo. Play App Signing (the default) holds the real app signing key; this one only signs uploads.
   ```sh
   keytool -genkeypair -v -keystore upload-keystore.jks -alias upload \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
4. **First upload by hand:** the Play API can't create the first release of a new app. Run `release-android.yml` once (the fastlane step will fail), download the `app-release-*.aab` artifact from the run, then upload it manually under **Testing → Internal testing → Create release** and add yourself as a tester. Later runs upload automatically. If fastlane reports *"Only releases with status draft may be created on draft app"*, this manual first release hasn't been done yet.
5. **Service account:** in Google Cloud, enable the *Google Play Android Developer API*, create a service account and download a JSON key. In Play Console → **Users and permissions**, invite the service account email and grant it *Release to testing tracks* for PawSense.

### Sentry

Create a Flutter project, then an **Organization auth token** (Settings → Developer Settings → Organization Tokens). The org slug and project slug go in repository *variables*, not secrets.

### Backend VM (e.g. AWS Lightsail, Ubuntu)

1. Install Docker and add the deploy user to the `docker` group.
2. Create `~/pawsense/.env` **on the VM only**: `PORT=8080`, `API_TOKEN=<long random>`, `ANTHROPIC_API_KEY=<key>`. The container publishes port 8080.
3. Create an SSH key pair for CI (`ssh-keygen -t ed25519 -f pawsense_deploy`). Append the `.pub` file to the deploy user's `~/.ssh/authorized_keys` on the VM.
4. GHCR: after the first push, set the `pawsense-backend` package to **public** (GitHub → Packages → Package settings), or run `docker login ghcr.io` on the VM with a token that has `read:packages`.
5. Put HTTPS in front (e.g. Caddy as a reverse proxy to `:8080`) so the app talks to `https://` / `wss://`. `API_BASE_URL` is that public URL.

## GitHub secrets and variables

Add them under **Settings → Secrets and variables → Actions**, or with `gh secret set NAME`. None of them are ever committed (`.gitignore` covers `*.p8`, `*.p12`, `*.mobileprovision`, `*.jks`, `key.properties`, `dart_defines.json`, service-account JSON).

| Secret | Value | Used by |
|---|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID | release-ios |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID | release-ios |
| `APP_STORE_CONNECT_API_KEY_P8` | contents of `AuthKey_<KEYID>.p8` (raw, multi-line): `gh secret set APP_STORE_CONNECT_API_KEY_P8 < AuthKey_XXXX.p8` | release-ios |
| `IOS_CERT_P12_BASE64` | `base64 -i distribution.p12 \| gh secret set IOS_CERT_P12_BASE64` | release-ios |
| `IOS_CERT_PASSWORD` | the `.p12` export password | release-ios |
| `IOS_PROFILE_BASE64` | `base64 -i PawSense_AppStore.mobileprovision \| gh secret set IOS_PROFILE_BASE64` | release-ios |
| `ANDROID_KEYSTORE_BASE64` | `base64 -i upload-keystore.jks \| gh secret set ANDROID_KEYSTORE_BASE64` | release-android |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password (no backslashes) | release-android |
| `ANDROID_KEY_ALIAS` | `upload` | release-android |
| `ANDROID_KEY_PASSWORD` | key password (no backslashes) | release-android |
| `PLAY_SERVICE_ACCOUNT_JSON` | `gh secret set PLAY_SERVICE_ACCOUNT_JSON < service-account.json` | release-android |
| `API_BASE_URL` | public backend URL, e.g. `https://api.example.com` | both releases (→ `dart_defines.json`) |
| `API_TOKEN` | same value as `API_TOKEN` in the VM `.env` | both releases |
| `SENTRY_DSN` | Flutter project DSN (empty disables Sentry in the app) | both releases |
| `SENTRY_AUTH_TOKEN` | Sentry org auth token | both releases (symbol upload) |
| `DEPLOY_HOST` / `DEPLOY_USER` | VM address / SSH user | backend-ci deploy |
| `DEPLOY_SSH_KEY` | private key `pawsense_deploy` | backend-ci deploy |
| `DEPLOY_KNOWN_HOSTS` *(optional)* | `ssh-keyscan -H <host>` output, checked once by hand; pins the host key instead of trusting on first use | backend-ci deploy |

| Variable | Value |
|---|---|
| `SENTRY_ORG` | Sentry organization slug |
| `SENTRY_PROJECT` | Sentry project slug |

`ANTHROPIC_API_KEY` is **not** a GitHub secret. It lives only in the VM's `~/pawsense/.env`. The release workflows fail fast if `API_BASE_URL`, `API_TOKEN` or `ANDROID_KEYSTORE_BASE64` is missing. The deploy job is skipped, with a notice, until the three `DEPLOY_*` secrets exist.

## Cutting a release

```sh
# optional: bump `version:` in app/pubspec.yaml first
git tag v0.1.0
git push origin v0.1.0
```

Both release workflows start. When they finish:

- **TestFlight:** the build shows up after Apple finishes processing (the lane doesn't wait for this). If it shows *Missing Compliance*, answer the encryption question once, or add `ITSAppUsesNonExemptEncryption = NO` to `Info.plist`.
- **Play:** Internal testing shows the new release, and testers get it from the opt-in link.

You can also run either workflow from the **Actions** tab (*Run workflow*).

## Local signing

- **Android:** copy `app/android/key.properties.example` to `app/android/key.properties` and fill it in. Release builds sign with it when the file is present and fall back to the debug key otherwise, so `flutter run --release` always works.
- **iOS:** the Xcode project keeps *automatic* signing for development. Only the CI checkout is switched to manual signing, by `update_code_signing_settings` inside the lane. `fastlane beta` is CI-only, because `setup_ci` creates its temporary keychain only when `CI=true`.

## Option: `match` instead of manual signing

[`match`](https://docs.fastlane.tools/actions/match/) keeps the certificate and profiles encrypted in a private git repo (or S3/GCS) and installs them on any machine. That's better once more than one person or machine signs builds. To switch:

1. `cd app/ios && BUNDLE_GEMFILE=../Gemfile bundle exec fastlane match init`, choose a **private** repo, then run `fastlane match appstore` once to create the cert and profile.
2. In the `beta` lane, replace everything from `tmp = Dir.mktmpdir` to `install_provisioning_profile(...)` with:
   ```ruby
   match(type: "appstore", readonly: true, api_key: api_key)
   profile_name = ENV.fetch("sigh_com.elysian12.pawsense_appstore_profile-name")
   team_id = ENV.fetch("sigh_com.elysian12.pawsense_appstore_team-id")
   ```
3. Secrets: add `MATCH_PASSWORD`, plus `MATCH_GIT_BASIC_AUTHORIZATION` (base64 of `user:token`) so CI can clone the repo. Drop the three `IOS_CERT_*` / `IOS_PROFILE_*` secrets.
