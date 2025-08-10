# TuneOut

This is a free [Skip](https://skip.tools) dual-platform app project.
It builds a native app for both iOS and Android.

## iOS Screenshots

<img src="https://github.com/Tune-Out/Tune-Out/blob/main/Darwin/fastlane/screenshots/en-US/1_en-US.png" width="190" /> <img src="https://github.com/Tune-Out/Tune-Out/blob/main/Darwin/fastlane/screenshots/en-US/2_en-US.png" width="190" /> <img src="https://github.com/Tune-Out/Tune-Out/blob/main/Darwin/fastlane/screenshots/en-US/3_en-US.png" width="190" /> <img src="https://github.com/Tune-Out/Tune-Out/blob/main/Darwin/fastlane/screenshots/en-US/4_en-US.png" width="190" /> <img src="https://github.com/Tune-Out/Tune-Out/blob/main/Darwin/fastlane/screenshots/en-US/5_en-US.png" width="190" />


## Android Screenshots

<img src="https://github.com/Tune-Out/Tune-Out/blob/main/Android/fastlane/metadata/android/en-US/images/phoneScreenshots/1_en-US.png" width="190" /> <img src="https://github.com/Tune-Out/Tune-Out/blob/main/Android/fastlane/metadata/android/en-US/images/phoneScreenshots/2_en-US.png" width="190" /> <img src="https://github.com/Tune-Out/Tune-Out/blob/main/Android/fastlane/metadata/android/en-US/images/phoneScreenshots/3_en-US.png" width="190" /> <img src="https://github.com/Tune-Out/Tune-Out/blob/main/Android/fastlane/metadata/android/en-US/images/phoneScreenshots/4_en-US.png" width="190" /> <img src="https://github.com/Tune-Out/Tune-Out/blob/main/Android/fastlane/metadata/android/en-US/images/phoneScreenshots/5_en-US.png" width="190" />



## Building

This project is both a stand-alone Swift Package Manager module,
as well as an Xcode project that builds and transpiles the project
into a Kotlin Gradle project for Android using the Skip plugin.

Building the module requires that Skip be installed using
[Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.

This will also install the necessary transpiler prerequisites:
Kotlin, Gradle, and the Android build tools.

Installation prerequisites can be confirmed by running `skip checkup`.

## Testing

The module can be tested using the standard `swift test` command
or by running the test target for the macOS destination in Xcode,
which will run the Swift tests as well as the transpiled
Kotlin JUnit tests in the Robolectric Android simulation environment.

Parity testing can be performed with `skip test`,
which will output a table of the test results for both platforms.

## Running

Xcode and Android Studio must be downloaded and installed in order to
run the app in the iOS simulator / Android emulator.
An Android emulator must already be running, which can be launched from
Android Studio's Device Manager.

To run both the Swift and Kotlin apps simultaneously,
launch the TuneOut target from Xcode.
A build phases runs the "Launch Android APK" script that
will deploy the transpiled app a running Android emulator or connected device.
Logging output for the iOS app can be viewed in the Xcode console, and in
Android Studio's logcat tab for the transpiled Kotlin app.

## License

This software is licensed under the [GNU General Public License v2.0 or later](https://spdx.org/licenses/GPL-2.0-or-later.html).
