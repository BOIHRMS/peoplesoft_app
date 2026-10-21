# PeopleSoft Flutter App

## Setup (one time, ~2 minutes)
1. Install Flutter SDK + Android Studio (with Flutter & Dart plugins).
2. Unzip this folder. In a terminal inside it, run:
       flutter create --org com.example --project-name peoplesoft_app .
   (This generates the Gradle wrapper, icons etc. It will NOT overwrite the provided files.)
3. Open `android/app/build.gradle` (or `build.gradle.kts`) and set minSdk to 24:
       minSdk = 24        // (or minSdkVersion 24)
4. Edit `lib/main.dart` -> set `kPeopleSoftUrl` to your PeopleSoft URL.
5. Run `flutter pub get`, then in Android Studio: File > Open > this folder, pick a device, press Run.

## Notes
- Screenshots/screen recording are blocked via FLAG_SECURE in MainActivity.kt (Android).
- Biometric uses fingerprint/face, falling back to device PIN/pattern.
- Registration stores email locally (encrypted). Add your backend/OTP call at the TODO in RegisterPage.
- PeopleSoft must be reachable over HTTPS from the phone (VPN if intranet-only).
