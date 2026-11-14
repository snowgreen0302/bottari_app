# 🎒 보따리 (Bottari)
> **날씨와 여행 맥락을 읽고, 짐 싸기부터 숙소 거점 최적 동선까지 알아서 챙겨주는 AI 스마트 여행 플래너**

---

## 📌 1. 프로젝트 소개 (Overview)
여행을 준비할 때 가장 번거로운 두 가지는 **"날씨와 여행 테마에 맞춰 무슨 짐을 챙겨야 할까?"**와 **"숙소를 중심으로 동선을 어떻게 짜야 이동 시간을 아끼고 휴무일을 피할 수 있을까?"**입니다.

**보따리(Bottari)**는 생성형 AI(Google Gemini)와 실시간 기상·지오코딩 API를 결합하여, 사용자가 **목적지·숙소·일정·여행 테마**만 입력하면 **맞춤형 준비물 체크리스트**와 **실존 여부·정기 휴무일·숙소 체크인 시간이 검증된 최적의 여행 동선**을 원스톱으로 자동 생성해 주는 크로스플랫폼 애플리케이션입니다.

---

## ✨ 2. 핵심 기능 (Key Features)

### ① 날씨·숙소·테마 융합형 AI 보따리 생성
- **실시간 기상 예보 연동 (`Open-Meteo API`)**: 여행 출발일의 실제 예상 기온과 강수확률을 조회하여 우산, 방한용품, 선크림 등 날씨 맞춤형 준비물을 도출합니다.
- **숙소 형태 및 테마 맞춤 추천**: 호텔·펜션·게스트하우스 등 숙소 특성과 여행 맥락(예: 부모님 효도 온천 여행, 뚜벅이 식도락 여행)을 분석해 군더더기 없는 깔끔한 준비물 리스트를 생성합니다.
- **프롬프트 가드레일(Guardrail)**: 비현실적이거나 장난스러운 테마(예: 좀비 사태, 우주여행, 무의미한 문자열) 입력 시 AI가 즉시 감지하여 안내 팝업을 띄우고 예외 처리합니다.

### ② 실존 매장 및 방문 요일 휴무일 실시간 검증 (Search Grounding)
- **AI 환각(Hallucination) 원천 차단**: Gemini REST API에 `google_search` 그라운딩 도구를 결합하고 `OpenStreetMap Nominatim` 지오코딩으로 교차 검증하여, 폐업했거나 존재하지 않는 가상의 상호명 추천을 방지합니다.
- **요일별 정기 휴무일 자동 체크**: 여행 일차별 실제 요일(월~일)을 계산하여 방문 예정일에 정기 휴무이거나 브레이크타임인 매장을 동선에서 자동 배제합니다.

### ③ 숙소 거점(체크인·복귀·익일 출발) 동선 최적화
- **숙소 체크인 시간 자동 확인**: 사용자가 선택한 체크인 시간 또는 AI가 실시간 검색한 숙소 공식 체크인 시간(예: 15:00)에 맞춰 1일차 체크인 일정을 자동 배치합니다.
- **숙소 복귀 및 익일 숙소 출발 연결**: 1일차 일정이 끝나면 숙소(🏨)로 복귀하고, 2일차 아침 첫 일정은 자동으로 숙소에서 출발하도록 동선과 지도 라인을 설계했습니다.

### ④ 커스텀 인터랙티브 타일 지도 & 드래그 앤 드롭 동선 재정렬
- **외부 패키지 의존성 없는 자체 지도 엔진**: Web/Mobile 환경에서 패키지 충돌 없이 부드럽게 동작하도록 메르카토르 투영법(Web Mercator Projection) 수식을 직접 구현하여 `OpenStreetMap` 타일 렌더링, 마우스 드래그 이동(Pan), 휠/버튼 확대·축소(Zoom)를 지원합니다.
- **스마트 타임슬롯 스왑(Time-Slot Swap)**: 일정을 길게 눌러 위아래로 순서를 바꾸면 장소만 이동하는 것이 아니라 날짜(Day), 시간, 지도 핀 번호와 연결선이 즉시 재계산됩니다.

### ⑤ AI 자동 분류 & 랜덤 장소 추천 & 공유용 한 장 포스터
- **나만의 준비물 AI 자동 분류**: 물건 이름(예: `고데기`, `인공눈물`)만 입력하면 AI가 백그라운드에서 `[의류, 세면도구, 전자기기, 상비약, 필수품, 기타]` 6대 카테고리로 자동 분류합니다.
- **🎲 AI 랜덤 장소 추천**: 동선 추가 시 현재 일정과 겹치지 않으면서 해당 요일에 정상 영업 중인 현지 맛집·카페·명소를 즉시 추천합니다.
- **📷 동선 한 장 요약 포스터 (이미지 변환 & 카톡 텍스트 복사)**: 확정된 1·2일차 전체 코스와 미니 동선 지도를 한 장의 고화질 PNG 포스터 이미지(`RepaintBoundary`) 또는 카카오톡 공유용 텍스트로 즉시 추출합니다.

---

## 🛠️ 3. 기술 스택 및 아키텍처 (Tech Stack)

| 구분 | 사용 기술 및 상세 내용 |
| :--- | :--- |
| **Framework & Language** | Flutter (Dart) — Web & Mobile Cross-Platform |
| **AI Engine** | Google Gemini REST API (`gemini-2.5-flash` / `gemini-2.0-flash`) + **Google Search Grounding** |
| **Weather & Geocoding** | Open-Meteo Forecast API, OpenStreetMap Nominatim Geocoding API |
| **Map Rendering** | Custom Web Mercator Tile Engine + `CustomPainter` Vector Route Overlay |
| **Local Persistence** | `SharedPreferences` 기반 JSON 직렬화 로컬 스토리지 |
| **UI / UX** | Forest Green (`#006B3E`) & Dark Grey (`#1C1C1E`) 디자인 시스템, `TableCalendar` |

---

## 📂 4. 폴더 구조 (Directory Structure)

```text
lib/
├── main.dart                      # 앱 진입점 및 글로벌 테마(#006B3E) 설정
├── config/
│   ├── api_keys.dart              # 실제 API 키 보관 (.gitignore 처리됨)
│   └── api_keys.example.dart      # 협업 및 배포용 API 키 템플릿
├── models/
│   └── trip_model.dart            # TripPlan, PackingItem, ScheduleItem 데이터 모델 및 직렬화
├── services/
│   ├── ai_service.dart            # Gemini REST 통신, 검색 그라운딩, 휴무일 검증, JSON 자동 보정
│   ├── weather_service.dart       # 실시간 기상 예보 및 국내외 정밀 좌표(Geocoding) 검색
│   └── storage_service.dart       # SharedPreferences 기반 로컬 데이터 영구 저장 관리
├── screens/
│   ├── main_screen.dart           # 여행 보따리 목록, 진행률 대시보드, 일정 제목 수정
│   ├── create_trip_screen.dart    # 목적지·숙소·체크인 시간·캘린더·테마 입력 화면
│   └── trip_detail_screen.dart    # 체크리스트 뷰, 동선 일정 뷰, 공유용 한 장 포스터 생성기
└── widgets/
    └── route_map_widget.dart      # 자체 구현 드래그/줌 오픈스트리트맵 타일 및 숙소 경유 동선 위젯