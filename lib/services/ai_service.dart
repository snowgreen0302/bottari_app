import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_keys.dart';
import '../models/trip_model.dart';
import 'storage_service.dart';
import 'weather_service.dart';

class AiService {
  static const List categories = ['의류', '세면도구', '전자기기', '상비약', '필수품', '기타'];

  static const String geminiApiKey = ApiKeys.geminiApiKey;
  static const String _apiHost = 'generativelanguage.googleapis.com';
  static String _lastErrorDetail = '';

  static Future _resolveApiKey() async {
    final String hardcoded = geminiApiKey.replaceAll(RegExp(r'\s+'), '');
    if (hardcoded.isNotEmpty && !hardcoded.contains('여기에')) {
      return hardcoded;
    }
    final String saved = await StorageService.getApiKey();
    return saved.replaceAll(RegExp(r'\s+'), '');
  }

  static String _getKoreanWeekday(DateTime date) {
    const List days = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    return days[date.weekday - 1].toString();
  }

  static String _sanitizeJsonText(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }

    final int startIdx = cleaned.indexOf('{');
    final int endIdx = cleaned.lastIndexOf('}');
    if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
      cleaned = cleaned.substring(startIdx, endIdx + 1);
    }

    cleaned = cleaned.replaceAll(RegExp(r'\}\s*\{'), '},{');
    cleaned = cleaned.replaceAll(RegExp(r',\s*\]'), ']');
    cleaned = cleaned.replaceAll(RegExp(r',\s*\}'), '}');

    return cleaned.trim();
  }

  static String _stripParentheses(String rawTitle) {
    var cleaned = rawTitle
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
        .trim();
    if (cleaned.contains(' - ')) {
      final List parts = cleaned.split(' - ');
      if (categories.contains(parts.first.toString().trim()) &&
          parts.length > 1) {
        cleaned = parts.sublist(1).join(' - ').trim();
      }
    }
    return cleaned.isEmpty ? rawTitle.trim() : cleaned;
  }

  static Future _getAvailableModels(String apiKey) async {
    final List priorityModels = [
      'gemini-2.5-flash',
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-1.5-pro',
    ];

    try {
      final listUri = Uri.https(_apiHost, '/v1beta/models', {'key': apiKey});
      final resp = await http.get(listUri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final dynamic data = json.decode(utf8.decode(resp.bodyBytes));
        final List rawModels = (data['models'] as List?) ?? [];
        final List fetched = [];

        for (final dynamic m in rawModels) {
          final String name = (m['name']?.toString() ?? '').replaceFirst(
            'models/',
            '',
          );
          final List methods = (m['supportedGenerationMethods'] as List?) ?? [];
          final bool canGenerate = methods
              .map((e) => e.toString())
              .contains('generateContent');

          if (canGenerate &&
              name.contains('gemini') &&
              !name.contains('vision') &&
              !name.contains('embedding') &&
              !name.contains('imagen') &&
              !name.contains('tts') &&
              !name.contains('audio') &&
              !name.contains('thinking')) {
            fetched.add(name);
          }
        }

        if (fetched.isNotEmpty) {
          final List ordered = [];
          for (final dynamic p in priorityModels) {
            if (fetched.contains(p)) ordered.add(p.toString());
          }
          for (final dynamic f in fetched) {
            final String fs = f.toString();
            if (!ordered.contains(fs) && fs.contains('flash')) ordered.add(fs);
          }
          for (final dynamic f in fetched) {
            final String fs = f.toString();
            if (!ordered.contains(fs)) ordered.add(fs);
          }
          return ordered;
        }
      } else {
        _lastErrorDetail = '모델 조회 실패 (HTTP ${resp.statusCode})';
      }
    } catch (e) {
      _lastErrorDetail = '모델 조회 오류: $e';
    }

    return priorityModels;
  }

  static Future _callGeminiJsonApi({
    required String apiKey,
    required String prompt,
    bool enableSearchGrounding = true,
    double temperature = 0.2,
  }) async {
    _lastErrorDetail = '';
    final List models = await _getAvailableModels(apiKey);

    for (final dynamic modelObj in models) {
      final String modelName = modelObj.toString();
      final List modes = enableSearchGrounding
          ? ['search_grounding', 'json_mime', 'plain']
          : ['json_mime', 'plain'];

      for (final dynamic modeObj in modes) {
        final String mode = modeObj.toString();
        try {
          final uri = Uri.https(
            _apiHost,
            '/v1beta/models/$modelName:generateContent',
            {'key': apiKey},
          );

          final Map genConfig = {
            'temperature': temperature,
            'maxOutputTokens': 4096,
          };
          if (mode == 'json_mime') {
            genConfig['responseMimeType'] = 'application/json';
          }

          final Map bodyMap = {
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': genConfig,
          };

          if (mode == 'search_grounding') {
            bodyMap['tools'] = [
              {'google_search': {}},
            ];
          }

          final response = await http
              .post(
                uri,
                headers: {'Content-Type': 'application/json'},
                body: json.encode(bodyMap),
              )
              .timeout(const Duration(seconds: 30));

          if (response.statusCode == 200) {
            final dynamic decoded = json.decode(
              utf8.decode(response.bodyBytes),
            );
            final List candidates = (decoded['candidates'] as List?) ?? [];
            if (candidates.isNotEmpty) {
              final dynamic content = candidates.first['content'];
              final List parts = (content?['parts'] as List?) ?? [];
              if (parts.isNotEmpty) {
                final StringBuffer buffer = StringBuffer();
                for (final dynamic p in parts) {
                  if (p['text'] != null) {
                    buffer.write(p['text'].toString());
                  }
                }
                final String text = buffer.toString();
                if (text.trim().isNotEmpty) {
                  final String sanitized = _sanitizeJsonText(text);
                  final dynamic parsedJson = json.decode(sanitized);
                  return parsedJson;
                }
              }
            }
          } else {
            final String errBody = utf8.decode(response.bodyBytes);
            _lastErrorDetail =
                '[$modelName/$mode] HTTP ${response.statusCode}: $errBody';
          }
        } catch (e) {
          _lastErrorDetail = '[$modelName/$mode] 오류: $e';
        }
      }
    }
    return null;
  }

  static Future _callGeminiTextApi({
    required String apiKey,
    required String prompt,
  }) async {
    final List models = await _getAvailableModels(apiKey);

    for (final dynamic modelObj in models) {
      final String modelName = modelObj.toString();
      try {
        final uri = Uri.https(
          _apiHost,
          '/v1beta/models/$modelName:generateContent',
          {'key': apiKey},
        );

        final Map bodyMap = {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {'temperature': 0.2},
        };

        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: json.encode(bodyMap),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final dynamic decoded = json.decode(utf8.decode(response.bodyBytes));
          final List candidates = (decoded['candidates'] as List?) ?? [];
          if (candidates.isNotEmpty) {
            final dynamic content = candidates.first['content'];
            final List parts = (content?['parts'] as List?) ?? [];
            if (parts.isNotEmpty) {
              final String? text = parts.first['text']?.toString();
              if (text != null && text.trim().isNotEmpty) {
                return text.trim();
              }
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future recommendRandomPlace({
    required String destination,
    required String accommodation,
    required String theme,
    required DateTime visitDate,
    required List existingPlaces,
  }) async {
    final String weekday = _getKoreanWeekday(visitDate);
    final String excluded = existingPlaces.isEmpty
        ? '없음'
        : existingPlaces.join(', ');
    final String stayInfo = accommodation.trim().isEmpty
        ? destination
        : accommodation.trim();

    final String apiKey = await _resolveApiKey();
    if (apiKey.isNotEmpty) {
      final int randomSeed = DateTime.now().millisecondsSinceEpoch % 1000;
      final String prompt =
          """
사용자가 "$destination" 여행 중 추가할 만한 새로운 장소를 랜덤으로 추천받고 싶어 합니다. (랜덤 시드: $randomSeed)
실시간 검색을 통해 아래 조건에 맞는 실제 영업 장소를 딱 1곳 골라 순수 JSON으로만 응답하세요. 문자열 내에 큰따옴표를 넣지 마세요.

[조건]
- 목적지: $destination (거점 숙소: $stayInfo)
- 여행 테마: $theme
- 방문 요일: $weekday (반드시 이 요일에 휴무가 아니고 정상 영업하는 곳이어야 함)
- 이미 일정에 있어서 제외할 장소: [$excluded] (절대 여기에 있는 장소와 겹치지 않게 새로운 곳을 추천하세요)
- 맛집, 분위기 좋은 카페, 소품샵, 전망 명소, 산책 코스 등 테마에 어울리는 실제 상호명을 추천하세요.

[출력 JSON 형식]
{
  "placeName": "실제 존재하는 공식 상호명",
  "recommendedTime": "15:30",
  "description": "추천 이유 및 특징 한 줄 요약 · ✅ $weekday 정상영업"
}
""";

      final dynamic parsed = await _callGeminiJsonApi(
        apiKey: apiKey,
        prompt: prompt,
        enableSearchGrounding: true,
        temperature: 0.85,
      );

      if (parsed != null) {
        final String name = parsed['placeName']?.toString().trim() ?? '';
        final String time =
            parsed['recommendedTime']?.toString().trim() ?? '15:00';
        final String desc = parsed['description']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          return {'placeName': name, 'time': time, 'description': desc};
        }
      }
    }

    final List fallbackPool = [
      {
        'placeName': '$destination 중앙시장 먹자골목',
        'time': '13:30',
        'description': '현지 길거리 간식과 로컬 분위기 체험',
      },
      {
        'placeName': '$destination 오션뷰 루프탑 카페',
        'time': '15:30',
        'description': '여유로운 커피 타임과 사진 명소',
      },
      {
        'placeName': '$destination 야경 전망대 산책로',
        'time': '19:30',
        'description': '저녁 식사 후 가볍게 걷기 좋은 야경 코스',
      },
      {
        'placeName': '$destination 로컬 베이커리 본점',
        'time': '11:00',
        'description': '지역 대표 빵집 투어',
      },
    ];
    final int pickIdx =
        DateTime.now().millisecondsSinceEpoch % fallbackPool.length;
    return fallbackPool[pickIdx];
  }

  static Future verifyAndResolvePlace({
    required String destination,
    required String placeName,
    required DateTime visitDate,
    required String visitTime,
  }) async {
    final String weekday = _getKoreanWeekday(visitDate);
    final String dateLabel = '${visitDate.month}월 ${visitDate.day}일 ($weekday)';

    final dynamic osmCoords = await WeatherService.searchPlaceCoords(
      destination,
      placeName,
    );

    final String apiKey = await _resolveApiKey();
    if (apiKey.isNotEmpty) {
      final String prompt =
          """
사용자가 "$destination" 여행 일정 중 $dateLabel $visitTime에 "$placeName" 방문을 추가하려 합니다.
실시간 검색을 통해 아래 사항을 점검하여 순수 JSON으로만 응답하세요. 문자열 내에 큰따옴표를 넣지 마세요.

1. "$destination" 인근(또는 해당 지역)에 "$placeName"이라는 장소가 실제로 존재하고 현재 폐업하지 않았는지 확인하세요.
2. 방문 예정일인 [$weekday] 또는 [$visitTime] 시간대에 정기 휴무일이거나 영업시간 외인지 확인하세요.
3. 해당 장소의 정확한 위도(lat), 경도(lng)와 공식 상호명을 기입하세요.

[출력 JSON 형식]
{
  "exists": true,
  "officialName": "실제 공식 상호명",
  "isClosedOnDay": false,
  "closedWarning": "만약 해당 요일이 정기휴무이거나 브레이크타임이면 구체적인 안내 문구 작성 (정상 영업이면 빈 문자열)",
  "businessHoursInfo": "영업시간 및 정기휴무 요약 (예: 10:00~21:00 · 매주 월요일 휴무)",
  "lat": 35.1587,
  "lng": 129.1604
}
""";

      final dynamic parsed = await _callGeminiJsonApi(
        apiKey: apiKey,
        prompt: prompt,
        enableSearchGrounding: true,
      );

      if (parsed != null) {
        try {
          final bool exists = parsed['exists'] != false;
          final bool isClosedOnDay = parsed['isClosedOnDay'] == true;
          final String officialName =
              parsed['officialName']?.toString().trim().isNotEmpty == true
              ? parsed['officialName'].toString().trim()
              : placeName;
          final String closedWarning =
              parsed['closedWarning']?.toString() ?? '';
          final String hoursInfo =
              parsed['businessHoursInfo']?.toString() ?? '';

          double? lat = double.tryParse(parsed['lat']?.toString() ?? '');
          double? lng = double.tryParse(parsed['lng']?.toString() ?? '');

          if (osmCoords is List && osmCoords.length >= 2) {
            lat ??= (osmCoords[0] as num).toDouble();
            lng ??= (osmCoords[1] as num).toDouble();
          }
          final List fallbackBase = WeatherService.getBaseCoords(destination);

          return {
            'exists': exists,
            'officialName': officialName,
            'isClosedOnDay': isClosedOnDay,
            'closedWarning': closedWarning,
            'businessHoursInfo': hoursInfo,
            'lat': lat ?? (fallbackBase[0] as num).toDouble(),
            'lng': lng ?? (fallbackBase[1] as num).toDouble(),
          };
        } catch (_) {}
      }
    }

    if (osmCoords is List && osmCoords.length >= 2) {
      return {
        'exists': true,
        'officialName': placeName,
        'isClosedOnDay': false,
        'closedWarning': '',
        'businessHoursInfo': '위치 확인 완료',
        'lat': (osmCoords[0] as num).toDouble(),
        'lng': (osmCoords[1] as num).toDouble(),
      };
    }

    final List base = WeatherService.getBaseCoords(destination);
    return {
      'exists': false,
      'officialName': placeName,
      'isClosedOnDay': false,
      'closedWarning': '실제 지도 데이터에서 해당 상호명을 찾을 수 없습니다.',
      'businessHoursInfo': '',
      'lat': (base[0] as num).toDouble(),
      'lng': (base[1] as num).toDouble(),
    };
  }

  static Future generateTripPackage({
    required String destination,
    required String accommodation,
    String checkInTime = 'AI 자동 확인',
    required DateTime startDate,
    required DateTime endDate,
    required String theme,
    required String weatherSummary,
  }) async {
    final int days = (endDate.difference(startDate).inDays + 1).clamp(1, 7);
    final String apiKey = await _resolveApiKey();
    final dynamic searchedCity = await WeatherService.searchPlaceCoords(
      '',
      destination,
    );
    final List baseCoords = (searchedCity is List && searchedCity.length >= 2)
        ? searchedCity
        : WeatherService.getBaseCoords(destination);

    final String stayName = accommodation.trim().isEmpty
        ? '$destination 중심 숙소'
        : accommodation.trim();

    final dynamic searchedStay = accommodation.trim().isNotEmpty
        ? await WeatherService.searchPlaceCoords(destination, stayName)
        : null;
    final List stayCoords = (searchedStay is List && searchedStay.length >= 2)
        ? searchedStay
        : baseCoords;

    final List dayScheduleLabels = [];
    for (int d = 1; d <= days; d++) {
      final DateTime currentDay = startDate.add(Duration(days: d - 1));
      final String wk = _getKoreanWeekday(currentDay);
      dayScheduleLabels.add(
        'Day $d: ${currentDay.month}월 ${currentDay.day}일 ($wk)',
      );
    }
    final String dayMappingText = dayScheduleLabels.join(', ');

    final String checkInInstruction = checkInTime == 'AI 자동 확인'
        ? '실시간 검색을 통해 숙소($stayName)의 실제 공식 체크인 시간(보통 15:00 또는 16:00)을 확인하여 resolvedCheckInTime 필드에 기입하고, 1일차 해당 시간에 "$stayName 체크인" 일정을 배치하세요.'
        : '사용자가 지정한 숙소 체크인 시간은 [$checkInTime]입니다. resolvedCheckInTime 필드에 "$checkInTime"을 기입하고, 1일차 [$checkInTime] 정각에 "$stayName 체크인" 일정을 배치하세요.';

    if (apiKey.isNotEmpty) {
      final String prompt =
          """
당신은 여행 준비 자동화 플래너 '보따리'의 수석 AI 엔진입니다.
실시간 검색을 활용해 입력된 여행 조건, 숙소 위치 및 체크인 시간, 방문 요일별 영업 여부를 검증한 뒤 반드시 아래 JSON 포맷으로만 응답하세요.
문자열 내부에는 절대 큰따옴표(")나 줄바꿈을 넣지 마세요.

[여행 정보]
- 목적지: $destination (중심 좌표: ${baseCoords[0]}, ${baseCoords[1]})
- 거점 숙소: $stayName (숙소 좌표: ${stayCoords[0]}, ${stayCoords[1]})
- 숙소 체크인 설정: $checkInTime
- 일차별 실제 날짜 및 요일: $dayMappingText
- 날씨 예보: $weatherSummary
- 여행 테마 및 맥락: $theme

[예외 처리 및 실존 장소/숙소 체크인·출발 동선 규칙 (매우 중요)]
1. 비현실적이거나 장난스러운 테마(예: 좀비 사태, 우주여행, 외계인 침공 등) 혹은 의미 없는 문자열(예: 아아아, ㅋㅋㅋ, 1234)이 입력된 경우:
   - 억지로 준비물이나 일정을 짜지 말고 반드시 아래와 같이 isError를 true로 반환하세요:
   {"isError": true, "errorMessage": "장난스럽거나 비현실적인 테마는 처리할 수 없습니다. 실제 여행 테마를 다시 입력해 주세요.", "packingList": [], "scheduleList": []}
2. 숙소 체크인 시간 검증 및 익일 숙소 출발 동선 필수 반영:
   - $checkInInstruction
   - 체크인 시간 이전에는 숙소 근처나 도착 역 주변 점심·카페·관광 코스를 배치하고, 체크인 시간에 맞춰 숙소 체크인 일정을 넣으세요.
   - 1박 이상(${days}일) 여행인 경우, 다음 날(예: Day 2) 첫 일정은 반드시 오전 "09:30"경 "$stayName 출발" (또는 체크아웃)로 시작하도록 구성하세요!
3. 실제 존재하는 영업 장소만 추천 & 방문 요일($dayMappingText) 휴무일 점검:
   - 반드시 현재 "$destination"에 실제로 존재하고 영업 중인 유명 맛집, 카페, 관광지 상호명만 넣으세요.
   - 각 일차의 실제 요일에 정기 휴무일인 곳은 배제하고, description 끝에 "✅ 요일 정상영업" 정보를 함께 적어주세요.
4. 준비물 규칙:
   - 숙소 형태와 날씨, 테마에 꼭 맞는 준비물을 6~9개 추천하되, 괄호 설명 없이 깔끔하게 물건 이름만 적으세요.

[출력 JSON 스키마]
{
  "isError": false,
  "resolvedCheckInTime": "15:00",
  "packingList": [
    {"title": "깔끔한 준비물 이름", "category": "의류"}
  ],
  "scheduleList": [
    {"day": 1, "time": "15:00", "placeName": "$stayName 체크인", "description": "공식 체크인 시간(15:00)에 맞춰 객실 체크인 및 짐 보관", "lat": ${stayCoords[0]}, "lng": ${stayCoords[1]}}
  ]
}
""";

      final dynamic parsed = await _callGeminiJsonApi(
        apiKey: apiKey,
        prompt: prompt,
        enableSearchGrounding: true,
      );

      if (parsed != null) {
        try {
          if (parsed['isError'] == true) {
            return {
              'isError': true,
              'errorMessage':
                  parsed['errorMessage']?.toString() ??
                  '올바른 여행 테마를 다시 입력해 주세요.',
            };
          }

          final String finalCheckInTime =
              (checkInTime != 'AI 자동 확인' && checkInTime.trim().isNotEmpty)
              ? checkInTime.trim()
              : (parsed['resolvedCheckInTime']?.toString().trim().isNotEmpty ==
                        true
                    ? parsed['resolvedCheckInTime'].toString().trim()
                    : '15:00');

          final List rawPacking = (parsed['packingList'] as List?) ?? [];
          final List rawSchedule = (parsed['scheduleList'] as List?) ?? [];

          final int ts = DateTime.now().millisecondsSinceEpoch;
          final List packingList = [];
          for (int i = 0; i < rawPacking.length; i++) {
            final dynamic item = rawPacking[i];
            final String rawTitle = item['title']?.toString() ?? '준비물';
            packingList.add(
              PackingItem(
                id: 'p_${ts}_$i',
                title: _stripParentheses(rawTitle),
                category: item['category']?.toString() ?? '기타',
              ),
            );
          }

          final List scheduleList = [];
          for (int i = 0; i < rawSchedule.length; i++) {
            final dynamic item = rawSchedule[i];
            final String placeName =
                item['placeName']?.toString() ?? destination;
            final int parsedDay =
                int.tryParse(item['day']?.toString() ?? '1') ?? 1;

            final dynamic verifiedOsmCoords =
                await WeatherService.searchPlaceCoords(destination, placeName);

            double? parsedLat =
                (verifiedOsmCoords is List && verifiedOsmCoords.length >= 2)
                ? (verifiedOsmCoords[0] as num).toDouble()
                : double.tryParse(item['lat']?.toString() ?? '');
            double? parsedLng =
                (verifiedOsmCoords is List && verifiedOsmCoords.length >= 2)
                ? (verifiedOsmCoords[1] as num).toDouble()
                : double.tryParse(item['lng']?.toString() ?? '');

            parsedLat ??=
                (baseCoords[0] as num).toDouble() + ((i % 3) - 1) * 0.012;
            parsedLng ??=
                (baseCoords[1] as num).toDouble() + ((i % 4) - 1.5) * 0.015;

            scheduleList.add(
              ScheduleItem(
                id: 's_${ts}_$i',
                day: parsedDay,
                time: item['time']?.toString() ?? '10:00',
                placeName: placeName,
                description: item['description']?.toString() ?? '',
                orderIndex: i,
                lat: parsedLat,
                lng: parsedLng,
              ),
            );
          }

          double resolvedStayLat = (stayCoords[0] as num).toDouble();
          double resolvedStayLng = (stayCoords[1] as num).toDouble();
          bool hasDay1CheckIn = false;

          for (final dynamic rawItem in scheduleList) {
            final ScheduleItem s = rawItem as ScheduleItem;
            if (s.placeName.contains(stayName) ||
                s.placeName.contains('숙소') ||
                s.placeName.contains('체크인')) {
              resolvedStayLat = s.lat;
              resolvedStayLng = s.lng;
              if (s.day == 1) {
                hasDay1CheckIn = true;
              }
            }
          }

          // 1일차에 숙소 체크인 일정이 누락되었으면 확인된 체크인 시간에 자동 삽입
          if (!hasDay1CheckIn) {
            scheduleList.add(
              ScheduleItem(
                id: 's_${ts}_checkin',
                day: 1,
                time: finalCheckInTime,
                placeName: '$stayName 체크인',
                description: '체크인 시간($finalCheckInTime)에 맞춰 숙소 입실 및 짐 정리',
                orderIndex: 0,
                lat: resolvedStayLat,
                lng: resolvedStayLng,
              ),
            );
          }

          // 2일차 이상 첫 일정에 '숙소 출발'이 누락되었으면 자동 삽입
          for (int d = 2; d <= days; d++) {
            final List dayItems = scheduleList
                .where((s) => (s as ScheduleItem).day == d)
                .toList();
            if (dayItems.isNotEmpty) {
              final ScheduleItem firstOfDay = dayItems.first as ScheduleItem;
              final bool startsAtStay =
                  firstOfDay.placeName.contains(stayName) ||
                  firstOfDay.placeName.contains('숙소') ||
                  firstOfDay.placeName.contains('출발') ||
                  firstOfDay.placeName.contains('체크아웃');
              if (!startsAtStay) {
                scheduleList.add(
                  ScheduleItem(
                    id: 's_${ts}_stay_start_$d',
                    day: d,
                    time: '09:30',
                    placeName: '$stayName 출발',
                    description: '${d}일차 오전 숙소에서 첫 행선지로 출발',
                    orderIndex: 0,
                    lat: resolvedStayLat,
                    lng: resolvedStayLng,
                  ),
                );
              }
            }
          }

          scheduleList.sort((a, b) {
            final ScheduleItem sa = a as ScheduleItem;
            final ScheduleItem sb = b as ScheduleItem;
            final int dayCmp = sa.day.compareTo(sb.day);
            if (dayCmp != 0) return dayCmp;
            return sa.time.compareTo(sb.time);
          });
          for (int i = 0; i < scheduleList.length; i++) {
            (scheduleList[i] as ScheduleItem).orderIndex = i;
          }

          if (packingList.isNotEmpty && scheduleList.isNotEmpty) {
            return {
              'isError': false,
              'resolvedCheckInTime': finalCheckInTime,
              'packingList': packingList,
              'scheduleList': scheduleList,
            };
          } else {
            _lastErrorDetail = 'AI 응답 내 리스트가 비어 있음';
          }
        } catch (e) {
          _lastErrorDetail = '데이터 변환 오류: $e';
        }
      }

      final fallback = _generateSmartContextualFallback(
        destination: destination,
        accommodation: accommodation,
        checkInTime: checkInTime,
        days: days,
        theme: theme,
        weatherSummary: weatherSummary,
        baseCoords: baseCoords,
      );
      fallback['warningMessage'] = 'AI 호출 실패 상세원인: $_lastErrorDetail';
      return fallback;
    }

    final fallback = _generateSmartContextualFallback(
      destination: destination,
      accommodation: accommodation,
      checkInTime: checkInTime,
      days: days,
      theme: theme,
      weatherSummary: weatherSummary,
      baseCoords: baseCoords,
    );
    fallback['warningMessage'] =
        'lib/config/api_keys.dart 파일의 geminiApiKey 변수에 API 키를 입력해주세요.';
    return fallback;
  }

  static Future<String> classifyCustomItemCategory(String itemTitle) async {
    final String apiKey = await _resolveApiKey();

    if (apiKey.isNotEmpty) {
      final String prompt =
          '사용자가 여행 준비물로 "$itemTitle"을(를) 추가했습니다. '
          '[의류, 세면도구, 전자기기, 상비약, 필수품, 기타] 중 가장 알맞은 카테고리 단어 딱 하나로만 답하세요.';
      final dynamic raw = await _callGeminiTextApi(
        apiKey: apiKey,
        prompt: prompt,
      );
      if (raw != null) {
        final String rawStr = raw.toString();
        for (final dynamic catObj in categories) {
          final String cat = catObj.toString();
          if (rawStr.contains(cat)) return cat;
        }
      }
    }

    final String t = itemTitle.toLowerCase();
    if (t.contains('충전') ||
        t.contains('배터리') ||
        t.contains('카메라') ||
        t.contains('이어폰') ||
        t.contains('에어팟') ||
        t.contains('고데기') ||
        t.contains('노트북') ||
        t.contains('어댑터')) {
      return '전자기기';
    }
    if (t.contains('칫솔') ||
        t.contains('치약') ||
        t.contains('샴푸') ||
        t.contains('세안') ||
        t.contains('폼') ||
        t.contains('로션') ||
        t.contains('선크림') ||
        t.contains('화장') ||
        t.contains('수건')) {
      return '세면도구';
    }
    if (t.contains('약') ||
        t.contains('밴드') ||
        t.contains('소화제') ||
        t.contains('진통제') ||
        t.contains('연고') ||
        t.contains('인공눈물') ||
        t.contains('비타민')) {
      return '상비약';
    }
    if (t.contains('옷') ||
        t.contains('바지') ||
        t.contains('셔츠') ||
        t.contains('티') ||
        t.contains('양말') ||
        t.contains('속옷') ||
        t.contains('신발') ||
        t.contains('운동화') ||
        t.contains('잠옷') ||
        t.contains('가디건')) {
      return '의류';
    }
    if (t.contains('지갑') ||
        t.contains('신분증') ||
        t.contains('여권') ||
        t.contains('티켓') ||
        t.contains('카드') ||
        t.contains('현금') ||
        t.contains('우산')) {
      return '필수품';
    }
    return '기타';
  }

  static dynamic _generateSmartContextualFallback({
    required String destination,
    required String accommodation,
    required String checkInTime,
    required int days,
    required String theme,
    required String weatherSummary,
    required List baseCoords,
  }) {
    final List badKeywords = ['좀비', '외계인', '우주여행', '화성', '마법학교', '아아아', 'ㅋㅋㅋ'];
    for (final dynamic kw in badKeywords) {
      if (theme.contains(kw.toString())) {
        return {
          'isError': true,
          'errorMessage': '장난스럽거나 비현실적인 테마는 처리할 수 없습니다. 실제 여행 테마를 다시 입력해 주세요.',
        };
      }
    }

    final String finalCheckIn = checkInTime == 'AI 자동 확인'
        ? '15:00'
        : checkInTime;

    final int ts = DateTime.now().millisecondsSinceEpoch;
    final List packing = [];
    int idx = 0;

    void addPack(String title, String category) {
      packing.add(
        PackingItem(id: 'p_${ts}_${idx++}', title: title, category: category),
      );
    }

    addPack('신분증 및 교통카드', '필수품');
    addPack('여벌 속옷 및 양말', '의류');
    addPack('휴대폰 충전기 및 보조배터리', '전자기기');
    addPack('개인 세면도구 세트', '세면도구');

    final String stayLabel = accommodation.trim().isEmpty
        ? '$destination 숙소'
        : accommodation.trim();

    final List dLat = [-0.015, 0.012, -0.005, 0.018, -0.022];
    final List dLng = [-0.018, 0.024, 0.011, -0.014, 0.019];

    final List schedules = [];
    int sIdx = 0;
    for (int d = 1; d <= days; d++) {
      final int i1 = sIdx % dLat.length;
      if (d == 1) {
        schedules.add(
          ScheduleItem(
            id: 's_${ts}_${sIdx++}',
            day: 1,
            time: '12:00',
            placeName: '$destination 도착 및 점심 식사',
            description: '[$theme] 맞춤 일정 시작',
            orderIndex: sIdx,
            lat:
                (baseCoords[0] as num).toDouble() +
                (dLat[i1] as num).toDouble(),
            lng:
                (baseCoords[1] as num).toDouble() +
                (dLng[i1] as num).toDouble(),
          ),
        );
        schedules.add(
          ScheduleItem(
            id: 's_${ts}_${sIdx++}',
            day: 1,
            time: finalCheckIn,
            placeName: '$stayLabel 체크인',
            description: '체크인 시간($finalCheckIn)에 맞춰 숙소 입실 및 짐 보관',
            orderIndex: sIdx,
            lat: (baseCoords[0] as num).toDouble(),
            lng: (baseCoords[1] as num).toDouble(),
          ),
        );
      } else {
        schedules.add(
          ScheduleItem(
            id: 's_${ts}_${sIdx++}',
            day: d,
            time: '09:30',
            placeName: '$stayLabel 출발',
            description: '${d}일차 오전 숙소에서 출발',
            orderIndex: sIdx,
            lat: (baseCoords[0] as num).toDouble(),
            lng: (baseCoords[1] as num).toDouble(),
          ),
        );
      }
    }

    return {
      'isError': false,
      'resolvedCheckInTime': finalCheckIn,
      'packingList': packing,
      'scheduleList': schedules,
    };
  }
}
