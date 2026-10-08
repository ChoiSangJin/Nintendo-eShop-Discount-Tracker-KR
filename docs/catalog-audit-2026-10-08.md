# 공식 카탈로그 검색 누락 점검 — 2026-10-08

한국닌텐도 `https://www.nintendo.com/kr/api/software?sftab=all&spage=N`의 고유 공식 항목 **4,494개**를 최신/오래된 순과 겹치는 구간으로 수집했다. 이 중 14자리 상품 ID가 아닌 항목은 **47개(약 1.05%)**다. 7개는 예정작이며 나머지에도 실물 전용·판매 종료 항목이 섞여 있다. 47개 전부가 판매 중인 eShop 게임이라는 의미는 아니다.

기존 앱은 이러한 항목을 모두 버렸다. `포켓몬스터스칼렛・바이올렛`은 ID가 `0001`이라 검색되지 않았다. 또한 소드/실드, 브릴리언트 다이아몬드/샤이닝 펄, 레츠고 피카츄/이브이처럼 하나의 공식 항목에 여러 상품이 묶이면 한쪽 상품만 연결됐다.

## 수정

- `catalog_products.dart`의 공식 한국 상품 링크로 검증한 제품별 ID/제목을 사용한다. NSUID가 아닌 공식 항목 ID로 연결하므로 `0001` 같은 임시 ID가 서로 다른 게임에 쓰여도 섞이지 않는다. 한국 가격 API에서 검증된 상품의 원화 가격을 확인했다.
- 임시 ID 대신 직접 한국 스토어 링크의 14자리 ID를 사용할 수 있다(진・여신전생5 Vengeance 등).
- 스토어 정보를 확정할 수 없는 항목도 `catalog:<공식 항목 ID>`로 검색/저장한다. 가격 확인 불가를 표시하고 공식 소개 링크가 있으면 제공한다. 임시 ID를 가격 API에 보내거나 스토어 URL에 사용하지 않는다.
- 소개 페이지의 추천 게임, DLC, 업그레이드 패스는 본편 ID로 추정하지 않는다. 예를 들어 메트로이드/원더 Switch 2 소개 페이지에서 찾은 업그레이드 패스 ID를 본편 가격에 연결하지 않는다.
- v2 캐시는 업데이트 후 다시 수집하고 v3으로 저장한다. 기존 관심 목록은 보존한다.
- 포켓몬스터/포켓몬/Pokémon/Pokemon 및 Scarlet/Violet 검색을 정규화한다.

다음 목록은 ID 형식 점검 결과이며 판매 가능 여부에 대한 판정이 아니다. 상품 링크가 확정되지 않은 항목의 가격 연결에는 추가 공식 정보가 필요하지만 검색 결과에서는 더 이상 버리지 않는다.

## 비정상 상품 ID 항목

| 공식 제목 | 상품 ID |
| --- | --- |
| 페르소나4 리바이벌 (Persona 4 Revival) | `0000` |
| FINAL FANTASY VII REVELATION | `0000` |
| 이터널 아니마 | `0000` |
| 로맨싱 사가 3 데스티니스 유나이티드 | `0000` |
| 로맨싱 사가 3 데스티니스 유나이티드 | `0000` |
| 레이튼 교수와 증기의 신세계 | `0000` |
| 레이튼 교수와 증기의 신세계 | `0000` |
| Fitness Boxing 3: Your Personal Trainer – Nintendo Switch 2 Edition | `000` |
| 리듬 천국 미라클 스타즈 | `000` |
| 슈퍼 마리오브라더스 원더 Nintendo Switch 2 Edition + 다 함께 방울 파크 | `00011` |
| Pokémon Pokopia | `POTPAAB5AKOR` |
| 메트로이드 프라임 4 비욘드 Nintendo Switch 2 Edition | `000` |
| 메트로이드 프라임 4 비욘드 | `000` |
| 젤다무쌍 봉인 전기 | `000` |
| Pokémon LEGENDS Z-A | `000` |
| 팩맨 월드 2 리팩 （PAC-MAN WORLD 2 Re-PAC） | `000` |
| 8번 승강장 | `000` |
| Eggy Party | `000` |
| 진・여신전생5 Vengeance | `0000000008` |
| 브레드와 프레드 | `0000` |
| Lorelei and the Laser Eyes | `0000` |
| 포켓몬스터스칼렛・바이올렛 | `0001` |
| Spingram | `no-route` |
| Heaven Dust 2 | `no-route` |
| Football Manager 2022 Touch | `no-route` |
| Marvel's Guardians of the Galaxy: Cloud Version TRIAL | `no-route` |
| MINECRAFT DUNGEONS: ULTIMATE EDITION | `0011` |
| 헤노시스™ | `no-route` |
| SUPER BOMBERMAN R ONLINE | `no-route` |
| Just Dance® 2021 | `no-route` |
| FIFA 21 Nintendo Switch™ 레거시 에디션 | `no-route` |
| JUMP FORCE Deluxe Edition | `no-route` |
| Just Dance® 2020 | `no-route` |
| MISTOVER | `no-route` |
| MARVEL ULTIMATE ALLIANCE 3: The Black Order | `0010` |
| Nintendo Labo Toy-Con 02: 로봇 키트 | `0002` |
| Nintendo Labo Toy-Con 03: 드라이브 키트 | `0003` |
| 사이쿄 컬렉션 Vol.3 | `0006` |
| Nintendo Labo Toy-Con 04: VR 키트 | `0004` |
| Nintendo Labo Toy-Con 01: 버라이어티 키트 | `0001` |
| 리디&수르의 아틀리에 ~신비한 그림의 연금술사~ | `0005` |
| BIOHAZARD® REVELATIONS UNVEILED EDITION | `0009` |
| SUPER BOMBERMAN R | `0008` |
| Fate/EXTELLA | `0007` |
| Mindcell | `no-route` |
| Fitness Boxing 3: Your Personal Trainer | `000` |
| KINGDOM HEARTS Collection [I~III] | `0` |
