# Nintendo Switch KR eShop 할인 트래커 앱 개발 명세서 (Flutter / Dart)

이 문서는 Codex, Cursor, Claude Code 등의 AI 코딩 에이전트가 단독으로 전체 프로젝트 코드베이스를 생성할 수 있도록 작성된 종합 프롬프트 겸 기능 명세서입니다.

---

## 1. 프로젝트 개요 및 기술 스택

* **목표:** 닌텐도 한국(KR) 공식 eShop의 할인 게임 목록을 조회하고, 카테고리 필터링/정렬/관심 게임(찜) 기능을 제공하는 1인용 크로스플랫폼 모바일 앱.
* **타깃 플랫폼:** Android (필요 시 iOS/Web 확장 가능)
* **언어 및 프레임워크:** Dart 3+, Flutter (최신 Stable)
* **상태 관리:** `flutter_riverpod` (권장) 또는 `provider`
* **네트워크 통신:** `dio` (배치 요청 및 타임아웃/헤더 처리)
* **로컬 저장소 (관심 목록 및 캐시):** `hive_flutter` 또는 `shared_preferences`
* **이미지 캐싱:** `cached_network_image`
* **디자인 시스템:** Material Design 3

---

## 2. API 엔드포인트 명세 및 데이터 수집 전략

닌텐도 eShop 내부 비공식 엔드포인트를 사용합니다.

### 2.1. 할인 게임 메타데이터 조회
* **URL:** `GET https://ec.nintendo.com/api/KR/ko/search/sales?count={count}&offset={offset}`
* **역할:** 할인 중인 게임의 기본 정보(이름, 배너 이미지, 장르, 출시일) 획득
* **주요 응답 필드:**
  * `total` (int): 전체 할인 게임 수
  * `contents[]`:
    * `id` (string): 14자리 타이틀 고유 번호 (NSUID, 예: `"70010000000001"`)
    * `formal_name` (string): 게임 타이틀 명
    * `hero_banner_url` (string): 배너 이미지 URL
    * `genres` (List<string>): 카테고리/장르 목록 (예: `["액션", "RPG"]`)
    * `release_date_on_eshop` (string): 출시일 (예: `"2023-05-12"`)

### 2.2. 실시간 가격 및 할인율 일괄 조회 (Batch Lookup)
* **URL:** `GET https://api.ec.nintendo.com/v1/price?country=KR&lang=ko&ids={comma_separated_ids}`
* **역할:** 특정 게임들의 정가, 현재 할인가, 할인 기간 획득
* **핵심 지침 (N+1 방지):**
  * 목록 API에서 받아온 게임들의 `id`를 콤마(`,`)로 묶어 최대 30개씩 단 1회의 요청으로 일괄 전송해야 합니다.
* **주요 응답 필드:**
  * `prices[]`:
    * `title_id` (string/num): 게임 NSUID
    * `regular_price`: `{ "amount": "74,800원", "currency": "KRW", "raw_value": "74800" }`
    * `discount_price`: `{ "amount": "52,360원", "currency": "KRW", "raw_value": "52360", "start_datetime": "...", "end_datetime": "..." }`

---

## 3. 데이터 모델 설계

### 3.1. 통합 게임 모델 (`GameItem`)
```dart
class GameItem {
  final String id;
  final String name;
  final String? bannerUrl;
  final List<String> genres;
  final DateTime? releaseDate;
  final int regularPrice;      // 원본 정가 (정수)
  final int discountPrice;     // 실제 판매가 (정수)
  final int discountRate;      // 계산된 할인율 (%)
  final DateTime? discountEnd;  // 할인 마감 일시
  final bool isFavorite;

  GameItem({
    required this.id,
    required this.name,
    this.bannerUrl,
    required this.genres,
    this.releaseDate,
    required this.regularPrice,
    required this.discountPrice,
    required this.discountRate,
    this.discountEnd,
    this.isFavorite = false,
  });

  // 할인율 계산 팩토리 헬퍼
  static int calculateDiscountRate(int regular, int discount) {
    if (regular <= 0 || discount >= regular) return 0;
    return (((regular - discount) / regular) * 100).round();
  }

  GameItem copyWith({bool? isFavorite}) {
    return GameItem(
      id: id,
      name: name,
      bannerUrl: bannerUrl,
      genres: genres,
      releaseDate: releaseDate,
      regularPrice: regularPrice,
      discountPrice: discountPrice,
      discountRate: discountRate,
      discountEnd: discountEnd,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
```

---

## 4. 핵심 기능 및 화면 구성

앱은 하단 네비게이션 바(`NavigationBar`)를 통해 2개 탭으로 분리합니다.

### 4.1. 탐색 탭 (`ExplorerScreen`)
1. **장르/카테고리 필터링:**
   * 상단에 수평 스크롤되는 `FilterChip` 목록 제공.
   * `전체`, `액션`, `RPG`, `어드벤처`, `퍼즐`, `시뮬레이션`, `스포츠` 등.
   * 선택된 장르에 부합하는 게임만 즉시 인메모리 필터링.
2. **정렬 메뉴:**
   * 우측 상단 드롭다운 또는 액션 시트 지원:
     * 최신 출시순 (`releaseDate` 내림차순)
     * 높은 할인율순 (`discountRate` 내림차순)
     * 최저 가격순 (`discountPrice` 오름차순)
3. **게임 카드 UI (`GameCard`):**
   * 배너 이미지 (`AspectRatio 16:9`, `CachedNetworkImage` + 로딩/에러 플레이스홀더).
   * 게임명 (최대 2줄, 말줄임 처리).
   * 장르 태그 칩 (작은 크기).
   * 가격 정보:
     * 취소선이 그어진 정가 (예: `₩54,800`)
     * 강조된 할인가 (예: `₩38,360`)
     * 할인율 뱃지 (예: `-30%`, 테마 강조색).
   * 찜(하트) 아이콘: 탭 시 즐겨찾기 등록/해제 토글.
4. **새로고침 & 페이지네이션:**
   * `RefreshIndicator`를 통한 당겨서 새로고침(Pull-to-Refresh).
   * 스크롤 끝 도달 시 다음 30개 추가 로딩 (`ScrollController` 리스너).

### 4.2. 관심 게임 탭 (`WishlistScreen`)
* 사용자가 하트를 눌러 로컬 저장소(`Hive`)에 등록한 게임 ID 목록만 필터링하여 노출.
* 목록 카드에서 즉시 찜 취소 가능.
* 비어 있을 경우 안내 UI 노출 ("관심 있는 할인 게임을 추가해 보세요").

---

## 5. 로컬 저장소 요구사항 (Hive)

* **저장 대상:** 관심 게임의 ID 목록 (`Set<String>` 또는 `List<String>`).
* **동작:**
  * 앱 시작 시 로컬 DB(`favoritesBox`)에서 ID 목록 로드.
  * API 응답 목록과 비교하여 `isFavorite` 플래그 매핑.
  * 하트 클릭 시 로컬 DB에 ID 추가/삭제 즉시 반영.

---

## 6. 프로젝트 디렉터리 구조 가이드

```text
lib/
├── core/
│   ├── constants/
│   │   └── api_constants.dart
│   └── network/
│       └── dio_client.dart
├── data/
│   ├── datasources/
│   │   ├── eshop_remote_data_source.dart
│   │   └── favorites_local_data_source.dart
│   ├── models/
│   │   ├── eshop_sales_response.dart
│   │   └── eshop_price_response.dart
│   └── repositories/
│       └── game_repository_impl.dart
├── domain/
│   ├── models/
│   │   └── game_item.dart
│   └── repositories/
│       └── game_repository.dart
├── presentation/
│   ├── controllers/
│   │   └── game_list_controller.dart
│   ├── screens/
│   │   ├── main_screen.dart
│   │   ├── explorer_screen.dart
│   │   └── wishlist_screen.dart
│   └── widgets/
│       ├── game_card.dart
│       ├── genre_filter_bar.dart
│       └── sort_bottom_sheet.dart
└── main.dart
```

---

## 7. AI 코딩 에이전트(Codex) 실행 지침

1. **의존성 설치 (`pubspec.yaml`):**
   * `flutter_riverpod`, `dio`, `hive_flutter`, `cached_network_image`, `intl` 라이브러리를 추가하고 구성할 것.
2. **API 결합 로직 작성:**
   * `sales` 엔드포인트 호출 후 반환된 NSUID 목록을 `ids` 쿼리스트링으로 결합하여 `price` 엔드포인트를 일괄 호출하는 리포지토리 로직을 작성할 것.
3. **상태 관리 및 UI 바인딩:**
   * 로딩, 에러(재시도 버튼 포함), 정상 데이터 표시 상태를 깔끔하게 처리할 것.
   * 모든 텍스트 및 통화 표시는 한국 원화(`₩`, 콤마 포맷팅) 규격에 맞출 것.
