# Codex 클라우드 개발 환경

기존 `/workspace/Nintendo-eShop-Discount-Tracker-KR` 체크아웃을 사용합니다. 사용자가 요청하지 않으면 Git worktree를 만들지 않습니다. 도구는 `/workspace/toolchains`에, 서명 키는 `/workspace/signing/switch-tracker`에 보관합니다.

```bash
export JAVA_HOME=/workspace/toolchains/jdk
export PATH=$JAVA_HOME/bin:/workspace/toolchains/flutter/bin:$PATH
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true
export PUB_CACHE=/workspace/toolchains/pub-cache
export XDG_CONFIG_HOME=/workspace/toolchains/config
export ANALYZER_STATE_LOCATION_OVERRIDE=/workspace/toolchains/analyzer
export ANDROID_HOME=/workspace/toolchains/android-sdk
export ANDROID_USER_HOME=/workspace/toolchains/android-user
export GRADLE_USER_HOME=/workspace/toolchains/gradle
cd /workspace/Nintendo-eShop-Discount-Tracker-KR
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

`CI=true`는 Dart 하위 프로세스가 읽기 전용 홈 디렉터리에 분석 설정을 만들지 않게 합니다. Java는 기본 프록시 환경 변수를 자동으로 쓰지 않으므로 Android SDK 설치와 Gradle에 플랫폼 HTTPS 프록시 및 플랫폼 인증서를 신뢰하도록 설정했습니다. `/workspace/toolchains/java-cacerts`와 Gradle 사용자 설정은 환경 안에만 있습니다. TLS 검증은 유지합니다.

별도 서버·데이터베이스는 필요하지 않습니다. 실제 API 검증은 `RUN_LIVE_SMOKE=1 flutter test test/live_smoke_test.dart --reporter expanded`, ARM64 릴리스는 `bash tool/build_release.sh`입니다. 서명 파일이 복원되지 않았다면 기존 릴리스 키를 안전하게 복원하세요. 새 키를 만들면 기존 APK에 업데이트 설치할 수 없습니다.

설치된 파일과 실행 중인 프로세스는 구분해야 합니다. 새 작업에서 필요한 것은 위 도구 활성화이며, 모바일 앱은 연결된 Android 기기에서 `flutter run`으로 실행합니다. ARM64 APK를 x86 에뮬레이터에 설치하지 마세요.
