# Switch 할인 트래커 KR

한국 Nintendo eShop 할인 게임을 탐색하고 관심 게임을 기기에 저장하는 Flutter Android 앱입니다.

![앱 아이콘](assets/branding/app_icon.png)

- 한국 정식 제목 우선 표시, Switch / Switch 2 플랫폼 구분
- 장르 필터, 전체 게임 검색, 인기·할인율·가격·출시일 정렬
- 화면당 20개와 상·하단 이전/다음 페이지 버튼, 스크롤 자동 로딩 없음
- 평소에는 할인 게임만, 검색 시에는 할인하지 않는 게임도 표시
- 원화 정가·할인가·할인 종료 시간, 최대 30개씩 가격 일괄 조회
- 찜과 마지막 조회 결과 영속 저장, 오류·재시도 지원
- 빨강·흰색만 사용한 단순한 Switch 2·할인 아이콘
- Android 7.0(API 24) 이상 **ARM64(arm64-v8a) 전용** APK

## 개발

Flutter **3.47.6**(Dart 3.13.5), JDK 21, Android SDK 36, Build Tools 36.0.0, NDK 28.2.13676358을 사용합니다. Flutter 버전은 `.flutter-version`에 고정했습니다.

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run
```

실제 데이터 점검은 선택해서 실행합니다. 일반 테스트는 네트워크 없이 실행됩니다.

```bash
RUN_LIVE_SMOKE=1 flutter test test/live_smoke_test.dart --reporter expanded
```

Codex 클라우드 활성화는 [환경 안내](docs/cloud-setup.md)를 사용합니다. 기존 체크아웃에서 작업하며, 별도 Git worktree는 필요하지 않습니다.

## 현재 공식 데이터 경로

[원본 명세](docs/user-spec.md)의 `ec.nintendo.com/api/KR/ko/search/sales`는 2026-10-08 검증에서 404를 반환했습니다. 앱은 404/410일 때 현재 공식 카탈로그로 전환합니다.

1. `www.nintendo.com/kr/api/software?sftab=all&spage=N`: 한국 정식 제목, NSUID, 배너, 출시일, 플랫폼. 현재 24개 단위입니다.
2. `api.ec.nintendo.com/v1/price?country=KR&lang=ko&ids=...`: 중복 제거한 ID를 최대 30개씩 묶어 실제 원화 가격·할인 기간을 확인합니다.
3. 실제 할인 중인 항목만 표시하고 다음 페이지를 누를 때 원래 카탈로그 위치부터 이어갑니다. 한 번의 요청은 최대 네 카탈로그 페이지를 확인하며, 화면당 20개를 채울 때까지 필요한 요청을 이어갑니다. 전체 카탈로그 수를 할인 게임 수로 표시하지 않습니다.
4. 검색어를 입력하면 `www.nintendo.com/kr/api/search?k=...&directory=software&size=24&p=N`으로 전체 공식 카탈로그를 검색합니다. 가격 조회 후 정가 게임도 그대로 표시하고 찜할 수 있습니다. 한국어 별칭으로 검색된 영어 제목도 유지합니다. 검색 결과는 할인 목록의 오프라인 캐시를 덮어쓰지 않습니다. 검색어를 지우면 할인 탐색으로 돌아갑니다.
5. 인기순은 [닌텐도 미국 공식 Best Sellers](https://www.nintendo.com/us/store/games/best-sellers/)의 공개 목록 순서입니다. 한국 판매 순위가 아닙니다. 같은 NSUID, 정확한 영어 제품명(한국 제목의 괄호/슬래시 영어 병기 포함)과 플랫폼, 또는 공식 지역 제목 별칭으로 연결합니다. 에디션·플랫폼을 임의로 합치거나 유사한 시리즈명만으로 순위를 붙이지 않습니다. 연결되지 않은 게임은 순위 미확인으로 뒤에 두고 할인율·제목으로 정렬합니다. 조회에 실패하면 저장된 순위를 유지하고 재시도를 제공합니다.

장르·정렬은 불러온 게임에 적용됩니다. 페이지를 더 불러와도 이미 방문한 페이지의 순서를 유지해 중복·누락을 방지합니다. 검색어·장르·정렬을 변경하거나 새로고침하면 첫 페이지부터 다시 정렬합니다. 마지막 페이지는 20개 미만일 수 있습니다. 한국 공식 제목을 사용하며, 추가 제목은 같은 NSUID의 한국 스토어 canonical URL이 일치할 때만 채택하고 캐시합니다. 공식 카탈로그에도 영어 이름만 있는 경우 임의 번역하지 않습니다. 카탈로그에서 유효한 eShop NSUID가 없는 예정작·패키지 묶음은 가격을 확인할 수 없어 제외합니다.

카탈로그가 장르를 생략하면 알려진 시리즈의 보수적 장르 분류를 보완합니다(`genre_catalog.dart`). 확인할 수 없는 게임은 **미분류**로 표시합니다. API가 제공하는 장르는 우선 사용합니다.

## 서명 및 ARM64 APK

최초 한 번만 앱 전용 키를 생성합니다. 키는 체크아웃 밖에, `android/key.properties`는 Git에서 제외하여 저장합니다. 기존 키를 새 키로 바꾸지 마세요. 동일 키가 있어야 이후 APK를 업데이트 설치할 수 있습니다.

```bash
python3 tool/create_signing_key.py
bash tool/build_release.sh
```

빌드 스크립트는 분석·테스트 후 `flutter build apk --release --target-platform android-arm64 --split-per-abi`를 실행합니다. 디버그 키로 릴리스를 서명하지 않으며, 네이티브 ABI·APK 서명을 검사하고 SHA-256 파일을 생성합니다. 결과는 `dist/switch-sale-tracker-kr-arm64-v1.1.0.apk`와 `.apk.sha256`입니다. 기존 1.0.0과 같은 키로 서명하고 버전 코드를 올려 찜·캐시를 유지한 업데이트 설치를 지원합니다. 다른 CPU용 라이브러리가 없어 범용 APK보다 작습니다. 32비트 전용 기기·x86 에뮬레이터에서는 설치할 수 없습니다.

CI는 PR·main에서 분석·테스트합니다. 수동 실행하는 `release.yml`을 사용하려면 저장소 **Settings → Secrets and variables → Actions**에 동일 릴리스 키의 다음 값을 안전하게 등록해야 합니다.

- `ANDROID_KEYSTORE_BASE64`: 키스토어 파일의 base64
- `ANDROID_KEYSTORE_PASSWORD`: 키스토어 비밀번호
- `ANDROID_KEY_PASSWORD`: 키 비밀번호(생성 스크립트의 PKCS12 키에서는 같은 비밀번호)

키스토어와 비밀번호는 별도로 안전하게 백업하세요. 코드·PR·릴리스에 포함하지 마세요. 자동 배포는 이미 존재하는 버전을 덮어쓰지 않습니다.

## 데이터 및 개인정보

로그인, 자체 서버, 광고, 분석 SDK를 사용하지 않습니다. 관심 목록과 캐시는 기기에 저장됩니다. Android 권한은 인터넷뿐입니다. Nintendo 공식 서버에서 목록·가격을, 공식 카탈로그가 지정한 CDN에서 이미지를 조회합니다. 가격은 변동될 수 있으므로 구매 전 공식 스토어에서 확인해 주세요.

Nintendo와 제휴하지 않은 팬 앱입니다. Nintendo Switch 및 관련 상표는 Nintendo의 자산입니다.
