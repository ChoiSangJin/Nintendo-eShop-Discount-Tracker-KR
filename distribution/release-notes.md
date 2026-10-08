# Switch 할인 트래커 KR v1.3.0

[ARM64 APK 다운로드](./switch-sale-tracker-kr-arm64-v1.3.0.apk) · 19,787,307 bytes (19.79 MB)

- 할인율 구간: 0~90%대를 10% 단위로 선택하고 전체·100%도 선택할 수 있습니다. 50%대는 화면의 표시 할인율 50~59%인 실제 할인 게임입니다.
- 기종: 전체 / Switch 1 / Switch 2 선택. Switch 2 Edition은 Switch 2에 포함하며 공식 출시 기종 기준으로 분류합니다.
- 화면에는 작은 필터 버튼 두 개를 두고 누르면 선택창을 엽니다. 장르·검색과 조합 후 전체 정렬 → 20개씩 페이지 분할. 변경 시 첫 페이지로 이동하며 취소·초기화를 지원합니다.
- Switch 2·Switch 2 Edition은 카드와 상세 화면에서 빨간 배경·흰 글자 라벨, Switch 1은 중립색과 숫자 1 라벨로 구분합니다.

기존 가격 제외 정책, 전체 카탈로그 캐시와 관심 게임 저장을 유지합니다. Android 7.0(API 24)+, arm64-v8a 전용. 앱 ID `kr.choisangjin.switch_sale_tracker`, versionName `1.3.0`, versionCode `2005`. 기존 APK와 같은 키로 서명해 업데이트 설치를 지원합니다.

소스: main merge commit `0699c833293ff2332bb29b305e0dfdb9a5e803c7`, [PR #5](https://github.com/ChoiSangJin/Nintendo-eShop-Discount-Tracker-KR/pull/5).

SHA-256: `d663d8fce3ff5a188e83365663ce933a026856b1b66653de0b8b415258c62a57`

검증: 분석·회귀 테스트 33개 및 PR CI 통과. 할인율 경계·반올림·정가/종료 할인 제외·100%, 기종/Edition 분류, 필터 조합과 정렬·페이지 초기화·취소·찜 보존, 카드/상세 라벨, 320px·글자 1.8배의 선택창과 초기화를 확인했습니다. APK 서명·ARM64 ABI·16KB ZIP/ELF 정렬 및 릴리스 바이너리의 새 UI 문구 검증 통과. 실제 Android 기기 설치는 이 환경에서 실행하지 않았습니다. 선택형 실제 서버 테스트 1개는 생략했으며 목록·가격 API는 변경하지 않았습니다.
