# 🎒 보따리 (Bottari)
> **날씨와 여행 맥락을 읽고, 짐 싸기부터 숙소 거점 최적 동선까지 알아서 챙겨주는 AI 스마트 여행 플래너**

---

## 📌 1. 프로젝트 소개 (Overview)
여행을 준비할 때 가장 번거로운 두 가지는 **"날씨와 여행 테마에 맞춰 무슨 짐을 챙겨야 할까?"**와 **"숙소를 중심으로 동선을 어떻게 짜야 이동 시간을 아끼고 휴무일을 피할 수 있을까?"**입니다.

**보따리(Bottari)**는 생성형 AI(`Google Gemini 3.5 Flash`)와 실시간 기상·정밀 지오코딩 API(`Kakao Local API` & `Open-Meteo`)를 결합하여, 사용자가 **목적지·숙소·일정·여행 테마**만 입력하면 **맞춤형 준비물 체크리스트**와 **실존 여부·정기 휴무일·숙소 체크인 시간이 검증된 최적의 여행 동선**을 원스톱으로 자동 생성해 주는 크로스플랫폼 애플리케이션입니다.

---

## ✨ 2. 핵심 기능 (Key Features)

### ① 날씨·숙소·테마 융합형 AI 보따리 생성
- **실시간 기상 예보 연동 (`Open-Meteo API`)**: 여행 출발일의 실제 예상 기온과 강수확률을 조회하여 우산, 방한용품, 선크림 등 날씨 맞춤형 준비물을 도출합니다.
- **숙소 형태 및 테마 맞춤 추천**: 호텔·펜션·게스트하우스 등 숙소 특성과 여행 맥락(예: 부모님 효도 온천 여행, 뚜벅이 식도락 여행)을 분석해 군더더기 없는 깔끔한 준비물 리스트를 생성합니다.
- **프롬프트 가드레일(Guardrail)**: 비현실적이거나 장난스러운 테마(예: 좀비 사태, 우주여행, 무의미한 문자열) 입력 시 AI가 즉시 감지하여 안내 팝업을 띄우고 예외 처리합니다.

### ② 실존 매장 및 방문 요일 휴무일 검증 & 정밀 지오코딩
- **국내외 이중 정밀 지오코딩 (`Kakao Local API` + `OSM Nominatim`)**: 한국 내 호텔·식당·카페는 **카카오 로컬 키워드 검색 API**를 통해 오차 없는 실제 건물 위·경도 좌표(`lat`, `lng`)를 추출하고, 해외 지역은 `OpenStreetMap Nominatim`으로 교차 검증하여 핀 위치 오차와 행정구역 이탈을 원천 차단합니다.
- **요일별 정기 휴무일 자동 체크**: 여행 일차별 실제 요일(월~일)을 계산하여 방문 예정일에 정기 휴무이거나 폐업한 매장을 동선에서 배제합니다.

### ③ 숙소 거점(체크인·복귀·익일 출발) 동선 최적화
- **숙소 체크인 시간 자동 확인**: 사용자가 선택한 체크인 시간 또는 AI가 확인한 숙소 공식 체크인 시간(예: `15:00`)에 맞춰 1일차 체크인 일정을 자동 배치합니다.
- **숙소 복귀 및 익일 숙소 출발 연결**: 1일차 일정이 끝나면 숙소(🏨)로 복귀하고, 2일차 이후 매일 아침 첫 일정은 자동으로 숙소에서 출발하도록 동선과 지도 라인을 설계했습니다.

### ④ 커스텀 인터랙티브 타일 지도 & 반응형 장기 여행 UI
- **외부 패키지 의존성 없는 자체 지도 엔진**: Web/iOS 환경에서 패키지 충돌 없이 동작하도록 메르카토르 투영법(Web Mercator Projection) 수식을 직접 구현하여 `OpenStreetMap` 타일 렌더링, 드래그 이동(Pan), 휠/버튼 확대·축소(Zoom)를 지원합니다.
- **장기 여행(1~14일+) 대응 2줄 반응형 헤더 & 컬러 시스템**: 다일차 일정에서도 레이아웃 깨짐 없이 탐색할 수 있도록 가로 스크롤 일차 필터 바를 적용했으며, **홀수 일차(Forest Green `#006B3E`)**와 **짝수 일차(Sky Blue `#0288D1`)** 이원화 컬러로 전날·다음날 동선을 직관적으로 구분합니다.
- **스마트 타임슬롯 스왑(Time-Slot Swap)**: 일정을 길게 눌러 위아래로 순서를 바꾸면 장소만 이동하는 것이 아니라 날짜(Day), 시간, 지도 핀 번호와 연결선이 즉시 재계산됩니다.

### ⑤ AI 자동 분류 & 랜덤 장소 추천 & 공유용 한 장 포스터
- **나만의 준비물 AI 자동 분류**: 물건 이름(예: `고데기`, `인공눈물`)만 입력하면 AI가 백그라운드에서 `[의류, 세면도구, 전자기기, 상비약, 필수품, 기타]` 6대 카테고리로 자동 분류합니다.
- **🎲 AI 랜덤 장소 추천**: 동선 추가 시 현재 일정과 겹치지 않으면서 해당 요일에 정상 영업 중인 현지 맛집·카페·명소를 즉시 추천합니다.
- **📷 동선 한 장 요약 포스터 (이미지 변환 & 카톡 텍스트 복사)**: 확정된 전체 코스와 미니 동선 지도를 한 장의 고화질 PNG 포스터 이미지(`RepaintBoundary`) 또는 카카오톡 공유용 텍스트로 즉시 추출합니다.

---

## 🛠️ 3. 기술 스택 및 아키텍처 (Tech Stack)

| 구분 | 사용 기술 및 상세 내용 |
| :--- | :--- |
| **Framework & Language** | Flutter (Dart) — Web & iOS Cross-Platform |
| **AI Engine** | Google Gemini REST API (`gemini-3.5-flash` 우선 적용 및 가용 모델 자동 탐색) |
| **Geocoding & Weather** | **Kakao Local REST API**, OpenStreetMap Nominatim, Open-Meteo Forecast API |
| **Map Rendering** | Custom Web Mercator Tile Engine + `CustomPainter` Vector Route Overlay |
| **Local Persistence** | `SharedPreferences` 기반 JSON 직렬화 로컬 스토리지 |
| **CI/CD & iOS Build** | GitHub Actions (`macos-latest` 클라우드 무서명 `.ipa` 빌드) & Sideloadly 실기기 포팅 |
| **UI / UX** | Forest Green (`#006B3E`), Sky Blue (`#0288D1`), Cream White (`#F9F8F7`) 테마, `TableCalendar` |

---

## 📂 4. 폴더 구조 (Directory Structure)

```text
├── .github/
│   └── workflows/
│       └── ios_build.yml          # GitHub Secrets 주입 및 macOS 클라우드 iOS(.ipa) 자동 빌드
└── lib/
    ├── main.dart                  # 앱 진입점 및 글로벌 테마(#006B3E) 설정
    ├── config/
    │   ├── api_keys.dart          # Gemini 및 Kakao API 키 보관 (.gitignore 처리됨)
    │   └── api_keys.example.dart  # 협업 및 배포용 API 키 템플릿
    ├── models/
    │   └── trip_model.dart        # TripPlan, PackingItem, ScheduleItem 데이터 모델 및 직렬화
    ├── services/
    │   ├── ai_service.dart        # Gemini 3.5 Flash 통신, 휴무일 검증, 장기일정 보장, JSON 보정
    │   ├── weather_service.dart   # 실시간 기상 예보 및 Kakao Local / OSM 정밀 좌표 검색
    │   ├── storage_service.dart   # SharedPreferences 기반 로컬 데이터 영구 저장 관리
    │   └── poster_saver.dart      # Web/iOS 플랫폼별 고화질 동선 포스터 이미지 저장 처리
    ├── screens/
    │   ├── main_screen.dart       # 여행 보따리 목록, 진행률 대시보드, 일정 제목 수정
    │   ├── create_trip_screen.dart# 목적지·숙소·체크인 시간·캘린더·테마 입력 화면
    │   └── trip_detail_screen.dart# 체크리스트 뷰, 동선 일정 뷰, 공유용 한 장 포스터 생성기
    └── widgets/
        └── route_map_widget.dart  # 2줄 반응형 헤더, 가로 스크롤 필터, 숙소 경유 동선 타일 맵 위젯
