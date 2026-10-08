# Switch 할인 트래커 KR v1.2.1

[ARM64 APK 다운로드](./switch-sale-tracker-kr-arm64-v1.2.1.apk) · 19,721,587 bytes (19.72 MB)

할인 탐색에서 현재 판매가 1,000원 이상 5,000원 미만의 게임을 제외합니다. 정가가 아닌 실제 판매가를 사용하며 1,000원·4,999원은 제외하고 5,000원은 표시합니다. 제외한 전체 결과를 정렬한 후 20개씩 페이지로 나누고 화면의 게임 수에 같은 조건을 적용합니다.

검색·관심 게임에서는 가격 제한 없이 조회하고 찜할 수 있습니다. 전체 카탈로그 캐시와 기존 찜을 보존합니다.

Android 7.0(API 24)+, arm64-v8a 전용. 앱 ID `kr.choisangjin.switch_sale_tracker`, versionName `1.2.1`, versionCode `2004`. 기존 v1.0.0·v1.1.0·v1.2.0과 같은 키로 서명해 업데이트 설치를 지원합니다.

소스: main merge commit `dad5f8526c73eb864df76919679a5b697d051921`, [PR #4](https://github.com/ChoiSangJin/Nintendo-eShop-Discount-Tracker-KR/pull/4).

SHA-256: `0483a1296d6ccd5d94f516a862d3538311bd26ffd1c2d0d661ab370e6868d824`

검증: 분석·회귀 테스트 28개 및 PR CI 통과. 경계 가격, 제외 후 정렬·페이지 개수, 검색·찜·전체 캐시 보존을 확인했습니다. APK 서명·ARM64 ABI·16KB ZIP/ELF 정렬 및 릴리스 바이너리의 가격 필터 문구 검증 통과. 실제 Android 기기 설치는 이 환경에서 실행하지 않았습니다. 선택형 실제 서버 테스트 1개는 생략했으며 목록·가격 API는 변경하지 않았습니다.
