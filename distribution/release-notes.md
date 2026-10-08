# Switch 할인 트래커 KR v1.2.0

[ARM64 APK 다운로드](./switch-sale-tracker-kr-arm64-v1.2.0.apk) · 19,721,587 bytes (19.72 MB)

- 전체 공식 게임 목록과 한국 가격 확인 후 전체 할인율·가격·출시일·인기 정렬 → 20개씩 페이지 분할. 페이지 이동 시 추가 수집 없음.
- 페르소나/Persona 등 시리즈 검색, 띄어쓰기 정규화. 정가 게임도 검색에 표시.
- 로딩 중 전체 화면 표시와 앱 내 조작·뒤로 가기 차단. 실패 시 해제하고 재시도 지원.
- 빨강·흰색 콘솔과 가격 화살표로 아이콘 단순화.

Android 7.0(API 24)+, arm64-v8a 전용. 앱 ID `kr.choisangjin.switch_sale_tracker`, versionName `1.2.0`, versionCode `2003`.
기존 v1.0.0·v1.1.0과 같은 키로 서명해 업데이트 설치와 찜 보존을 지원합니다.

소스: main merge commit `4741d0f5e46e23c3d4925abc69c9688c6995e945`, [PR #3](https://github.com/ChoiSangJin/Nintendo-eShop-Discount-Tracker-KR/pull/3).

SHA-256: `f0c43619ae03ec74a603ea10bee1fdb0a1f1d358c4cc70b74e64ae77d7d52901`

검증: 분석, 회귀 테스트 27개, 실제 공식 서버 전체 항목 4,494개 및 유효 고유 NSUID 4,445개 가격 확인. 할인 719개, 페르소나 검색 7개, 포켓몬 검색 14개 및 전체 페이지 간 정렬 검증. APK 서명·ARM64 ABI·16KB ZIP/ELF 정렬 검증 통과. 실제 Android 기기 설치는 이 환경에서 실행하지 않았습니다.

첫 전체 조회 및 수동 전체 새로고침에는 몇 분 걸릴 수 있습니다. 시작/복귀에는 전체 결과를 15분 재사용하고, 가격 갱신 시 전체 메타데이터를 최대 24시간 재사용합니다. 수동 새로고침은 전체 목록부터 다시 수집합니다.
