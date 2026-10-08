# Switch 할인 트래커 KR v1.3.1

할인율·기종 선택창을 중앙 모달로 변경했습니다. Android 하단 시스템 내비게이션 영역을 피하고, 작은 화면과 큰 글씨에서는 선택 항목을 스크롤합니다. 닫기·뒤로 가기로 취소하면 기존 선택을 유지합니다.

- [ARM64 APK 다운로드](switch-sale-tracker-kr-arm64-v1.3.1.apk)
- [SHA-256 확인 파일](switch-sale-tracker-kr-arm64-v1.3.1.apk.sha256)
- 크기: 19,787,307 bytes (약 19.8 MB)
- Android 7.0 이상 / ARM64 전용 / 버전 1.3.1, versionCode 2006
- 기존 릴리스와 같은 서명 키: 기존 앱 위에 업데이트 설치 가능
- 병합 PR: https://github.com/ChoiSangJin/Nintendo-eShop-Discount-Tracker-KR/pull/6
- 소스: `e5f3ff9149f9186dc58519378ac24eb3f013ce16`
- APK SHA-256: `5732648b90831f58e6a906513a5b131197a13deb8870b65356e7991b6714fb68`
- 서명 인증서 SHA-256: `74b994a84b3df7aefe056c657b182877398889f9bf513bcf0980e90b6373dd48`

검증: 정적 분석, 자동 테스트 35개(선택적 실 API 테스트 1개 제외), PR CI, APK 무결성·서명·ARM64 ABI·16KB 페이지 정렬 통과. 테스트에서 세로·가로 작은 화면, 글자 배율 1.8, 시스템 버튼 여백 48px 및 선택·취소 동작을 확인했습니다. 실제 Android 기기 설치는 이 환경에서 실행하지 않았습니다.

현재 환경의 GitHub Release 첨부 업로드 인증 제한으로 APK는 공개 배포 브랜치에 제공하며, Release에서 검증된 직접 다운로드 링크를 안내합니다.
