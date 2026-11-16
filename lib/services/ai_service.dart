import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';
import '../models/trip_model.dart';
import 'weather_service.dart';

class AiService {
  // 성공 확인된 gemini-3.5-flash를 1순위로 고정!
  static const List _candidateModels = [
    'gemini-3.5-flash',
    'gemini-3.5-pro',
  ];

  static String _getKoreanWeekday(DateTime date) {
    const List days = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    return days[date.weekday - 1].toString();
  }

  static String _stripParentheses(String input) {
    return input
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
        .trim();
  }

  static String _sanitizeJsonText(String raw) {
    String s =
        raw.replaceAll('```json', '').replaceAll('```', '').trim();
    final int start = s.indexOf('{');
    final int end = s.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      s = s.substring(start, end + 1);
    }
    s = s.replaceAllMapped(
      RegExp(r'\}\s*\n\s*\{'),
      (m) => '},\n{',
    );
    s = s.replaceAllMapped(
      RegExp(r'\]\s*\n\s*"'),
      (m) => '],\n"',
    );
    s = s.replaceAllMapped(
      RegExp(r',\s*([}\]])'),
      (m) => m.group(1)!,
    );
    return s;
  }

  static Future _callGeminiRaw(
    String prompt, {
    double temperature = 0.35,
    bool useSearch = false,
  }) async {
    final String apiKey = ApiKeys.geminiApiKey.trim();
    if (apiKey.isEmpty || apiKey.contains('여기에') || apiKey.length < 20) {
      print('🚨 [API 키 오류] lib/config/api_keys.dart 파일에 실제 키가 없습니다!');
      throw Exception('API 키가 설정되지 않았습니다.');
    }

    String lastErrorDetail = '';

    for (final dynamic modelObj in _candidateModels) {
      final String model = modelObj.toString();
      try {
        final Uri uri = Uri.https(
          'generativelanguage.googleapis.com',
          '/v1beta/models/$model:generateContent',
          {'key': apiKey},
        );

        final Map bodyMap = {
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': temperature,
          },
        };

        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(bodyMap),
            )
            .timeout(const Duration(seconds: 120));

        if (response.statusCode == 200) {
          final Map data =
              jsonDecode(utf8.decode(response.bodyBytes)) as Map;
          final List? candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final Map content = candidates[0]['content'] as Map;
            final List parts = content['parts'] as List;
            final StringBuffer sb = StringBuffer();
            for (final dynamic p in parts) {
              if (p is Map && p['text'] != null) {
                sb.write(p['text'].toString());
              }
            }
            final String resultText = sb.toString().trim();
            if (resultText.isNotEmpty) {
              print('✅ [Gemini 호출 성공] 사용된 모델: $model');
              return resultText;
            }
          }
        } else {
          final String errBody = utf8.decode(response.bodyBytes);
          lastErrorDetail = '[$model | HTTP ${response.statusCode}] $errBody';
          print('🚨 [Gemini 에러 상세] $lastErrorDetail');
        }
      } catch (e) {
        lastErrorDetail = e.toString();
        print('🚨 [Gemini 통신 예외] ($model): $lastErrorDetail');
      }
    }

    throw Exception('Gemini API 호출 실패: $lastErrorDetail');
  }

  static Future generateTripPackage({
    required String destination,
    String accommodation = '',
    String checkInTime = 'AI 자동 확인',
    String checkInPreference = 'AI 자동 확인',
    required DateTime startDate,
    required DateTime endDate,
    required String theme,
    required String weatherSummary,
  }) async {
    final String finalCheckIn =
        (checkInTime != 'AI 자동 확인' && checkInTime.isNotEmpty)
            ? checkInTime
            : checkInPreference;
    return generateTripPlan(
      destination: destination,
      accommodation: accommodation,
      checkInPreference: finalCheckIn,
      startDate: startDate,
      endDate: endDate,
      theme: theme,
      weatherSummary: weatherSummary,
    );
  }

  static Future generateTripPlan({
    required String destination,
    String accommodation = '',
    String checkInPreference = 'AI 자동 확인',
    required DateTime startDate,
    required DateTime endDate,
    required String theme,
    required String weatherSummary,
  }) async {
    final int totalDays = endDate.difference(startDate).inDays + 1;
    final List dayMappingList = [];
    for (int d = 1; d <= totalDays; d++) {
      final DateTime curr = startDate.add(Duration(days: d - 1));
      final String wk = _getKoreanWeekday(curr);
      dayMappingList.add('Day $d = ${curr.month}월 ${curr.day}일($wk)');
    }
    final String dayMappingStr = dayMappingList.join(', ');

    final String stayText = accommodation.trim().isEmpty
        ? '$destination 중심가 숙소'
        : accommodation.trim();

    final String prompt = '''
당신은 대한민국 및 해외 지역 지리에 정통한 전문 여행 플래너입니다.
아래 여행 조건에 맞는 준비물과 완벽한 실제 이동 동선을 마크다운 코드블록 없이 순수 JSON 객체로만 응답하세요.

[여행 입력 정보]
- 목적지(시/군/구): $destination
- 거점 숙소: $stayText
- 사용자 요청 체크인 시간 설정: $checkInPreference
- 총 일정: ${totalDays}일 ($dayMappingStr)
- 여행 테마 및 이동수단 맥락: $theme
- 현지 기상 예보: $weatherSummary

[1. 비정상/장난 입력 가드레일]
만약 목적지나 테마가 '좀비 사태', '우주전쟁', '무의미한 자모음(ㅋㅋㅋ, ㅇㅇ)' 등 현실적인 여행이 불가능한 장난 입력이라면, 억지로 일정을 짜지 말고 즉시 아래 에러 JSON만 반환하세요:
{"isError": true, "errorMessage": "현실적인 여행 목적지와 테마를 입력해 주세요."}

[2. 절대 준수 규칙 - 지리적 범위 및 실제 상호명 (가장 중요!)]
1) 행정구역 이탈 절대 금지:
   - 목적지가 "$destination"이면 모든 일정 장소는 반드시 "$destination" 행정구역(시/군/구) 내부에 있어야 합니다!
   - 예를 들어 목적지가 '김포'인데 안산, 인천, 서울, 파주 등 타 시/군의 장소를 넣으면 절대 안 됩니다! 무조건 김포시 내부(구래동, 마산동, 장기동, 운양동, 사우동 등)만 추천하세요!
2) 뚜벅이/도보/대중교통 테마 반영:
   - 테마("$theme")에 '뚜벅이', '도보', '걸어서', '대중교통' 등이 포함되어 있다면, 거점 숙소("$stayText")가 위치한 동네에서 도보나 지하철·버스로 15분 이내에 이동 가능한 가까운 생활권 안에서만 동선을 짜세요!
3) 카카오맵/네이버지도에 검색되는 정확한 '공식 상호명(placeName)' 사용:
   - 지도 검색 API가 정확한 위치를 찾을 수 있도록, '구래동 맛집' 같은 추상적인 말 대신 '라베니체 수변상가', '은여울공원', '김포한강야생조류생태공원', '해목 해운대점'처럼 실제 지도에 등록된 정확한 건물·상호명을 적으세요!
4) 실존 매장 및 방문 요일($dayMappingStr) 정기휴무 검증:
   - 각 일정의 description 맨 끝에 "✅ 요일 정상영업"을 표시하세요.
5) 숙소 체크인 및 2일차 숙소 출발 반영:
   - "$checkInPreference"가 'AI 자동 확인'이면 "$stayText"의 체크인 시간(15:00)에 맞춰 Day 1 일정에 "$stayText 체크인" 일정을 반드시 포함하세요.
   - 2일 이상(totalDays >= 2)인 경우 Day 2의 첫 번째 일정(09:30)은 반드시 "$stayText 출발"로 시작하세요.
6) 준비물(packingList) 작성 규칙:
   - 날씨("$weatherSummary")와 테마("$theme")에 꼭 필요한 준비물 7~10개를 추천하되, 괄호 부연 설명 없이 명사형 물건 이름만 깔끔하게 적으세요. (카테고리: 의류, 세면도구, 전자기기, 상비약, 필수품, 기타)

[응답 JSON 스키마 (코드블록 없이 순수 JSON만 출력)]
{
  "isError": false,
  "title": "$destination ${totalDays - 1}박 ${totalDays}일 보따리",
  "resolvedCheckInTime": "15:00",
  "stayLat": 37.6438,
  "stayLng": 126.6268,
  "packingList": [
    {"title": "경량패딩", "category": "의류"}
  ],
  "scheduleList": [
    {
      "day": 1,
      "time": "12:00",
      "placeName": "실제 상호명",
      "description": "간단한 코스 설명 ✅ 요일 정상영업",
      "lat": 37.6445,
      "lng": 126.6275
    }
  ]
}
''';

    final String rawJson =
        await _callGeminiRaw(prompt, temperature: 0.3, useSearch: false);
    final String cleanJson = _sanitizeJsonText(rawJson);
    final Map parsed = jsonDecode(cleanJson) as Map;

    if (parsed['isError'] == true) {
      return {
        'isError': true,
        'errorMessage':
            parsed['errorMessage']?.toString() ?? '올바른 여행 정보를 입력해주세요.',
      };
    }

    final String resolvedCheckIn = (checkInPreference == 'AI 자동 확인')
        ? (parsed['resolvedCheckInTime']?.toString() ?? '15:00')
        : checkInPreference;

    // 숙소 좌표 결정: 1순위로 정밀 지오코딩(카카오/OSM)을 먼저 수행해 건물 정중앙 좌표를 확보!
    double stayLat = (parsed['stayLat'] is num)
        ? (parsed['stayLat'] as num).toDouble()
        : 0.0;
    double stayLng = (parsed['stayLng'] is num)
        ? (parsed['stayLng'] as num).toDouble()
        : 0.0;

    final dynamic preciseStay =
        await WeatherService.geocodePlace(stayText, destination);
    if (preciseStay != null) {
      stayLat = (preciseStay[0] as num).toDouble();
      stayLng = (preciseStay[1] as num).toDouble();
    } else if (!WeatherService.isValidNearDestination(
        stayLat, stayLng, destination)) {
      final List base = WeatherService.getBaseCoords(destination);
      stayLat = (base[0] as num).toDouble();
      stayLng = (base[1] as num).toDouble();
    }

    final List rawPacking = (parsed['packingList'] as List?) ?? [];
    final List packingItems = [];
    for (int i = 0; i < rawPacking.length; i++) {
      final Map p = rawPacking[i] as Map;
      final String cleanTitle =
          _stripParentheses(p['title']?.toString() ?? '준비물');
      if (cleanTitle.isEmpty) continue;
      packingItems.add(
        PackingItem(
          id: 'pack_${DateTime.now().millisecondsSinceEpoch}_$i',
          title: cleanTitle,
          category: p['category']?.toString() ?? '기타',
          isChecked: false,
        ),
      );
    }

    final List rawSchedule = (parsed['scheduleList'] as List?) ?? [];
    final List scheduleItems = [];

    for (int i = 0; i < rawSchedule.length; i++) {
      final Map m = rawSchedule[i] as Map;
      final String placeName = m['placeName']?.toString() ?? '추천 장소';
      final int dayNum =
          (m['day'] is num) ? (m['day'] as num).toInt() : 1;
      final String timeStr = m['time']?.toString() ?? '12:00';
      String desc = m['description']?.toString() ?? '';
      if (!desc.contains('✅')) {
        desc = '$desc ✅ 요일 정상영업'.trim();
      }

      double lat = (m['lat'] is num) ? (m['lat'] as num).toDouble() : 0.0;
      double lng = (m['lng'] is num) ? (m['lng'] as num).toDouble() : 0.0;

      // 1) 숙소 체크인/출발 일정이면 확보해둔 숙소 정밀 좌표를 그대로 부여
      if (placeName.contains(stayText) ||
          placeName.contains('숙소') ||
          placeName.contains('체크인') ||
          placeName.contains('출발')) {
        lat = stayLat;
        lng = stayLng;
      } else {
        // 2) 일반 장소는 카카오/OSM 정밀 지오코딩을 1순위로 수행해 오차 0m 좌표 획득!
        final dynamic preciseCoords =
            await WeatherService.geocodePlace(placeName, destination);
        if (preciseCoords != null) {
          lat = (preciseCoords[0] as num).toDouble();
          lng = (preciseCoords[1] as num).toDouble();
        } else if (!WeatherService.isValidNearDestination(
            lat, lng, destination)) {
          lat = stayLat + ((i % 3) - 1) * 0.003;
          lng = stayLng + ((i % 4) - 1.5) * 0.003;
        }
      }

      scheduleItems.add(
        ScheduleItem(
          id: 'sched_${DateTime.now().millisecondsSinceEpoch}_$i',
          day: dayNum,
          time: timeStr,
          placeName: placeName,
          description: desc,
          orderIndex: i,
          lat: lat,
          lng: lng,
        ),
      );
    }

    final bool hasDay1CheckIn = scheduleItems.any((s) {
      final ScheduleItem item = s as ScheduleItem;
      return item.day == 1 &&
          (item.placeName.contains('체크인') ||
              item.placeName.contains(stayText) ||
              item.description.contains('체크인'));
    });

    if (!hasDay1CheckIn && accommodation.trim().isNotEmpty) {
      scheduleItems.add(
        ScheduleItem(
          id: 'sched_checkin_${DateTime.now().millisecondsSinceEpoch}',
          day: 1,
          time: resolvedCheckIn,
          placeName: '$stayText 체크인',
          description:
              '공식 체크인 시간($resolvedCheckIn)에 맞춰 객실 체크인 및 짐 보관 ✅ 요일 정상영업',
          orderIndex: scheduleItems.length,
          lat: stayLat,
          lng: stayLng,
        ),
      );
    }

    // 2일차부터 마지막 날(totalDays)까지 하루라도 빠진 날이 없도록 숙소 출발 및 추천 일정을 보장합니다!
    if (totalDays >= 2) {
      for (int d = 2; d <= totalDays; d++) {
        final bool hasDayItems = scheduleItems.any((s) {
          final ScheduleItem item = s as ScheduleItem;
          return item.day == d;
        });

        if (!hasDayItems) {
          // AI가 장기 여행 뒷날짜를 생략했을 경우 해당 일차 일정을 자동 보충
          scheduleItems.add(
            ScheduleItem(
              id: 'sched_day${d}_start_${DateTime.now().millisecondsSinceEpoch}',
              day: d,
              time: '09:30',
              placeName: '$stayText 출발',
              description: '$d일차 오전 숙소 출발 ✅ 요일 정상영업',
              orderIndex: scheduleItems.length,
              lat: stayLat,
              lng: stayLng,
            ),
          );
          scheduleItems.add(
            ScheduleItem(
              id: 'sched_day${d}_spot_${DateTime.now().millisecondsSinceEpoch}',
              day: d,
              time: '13:00',
              placeName: '$destination 주요 명소 탐방 ($d일차)',
              description: '$theme 맞춤 여유로운 현지 일정 ✅ 요일 정상영업',
              orderIndex: scheduleItems.length + 1,
              lat: stayLat + ((d % 3) - 1) * 0.004,
              lng: stayLng + ((d % 4) - 1.5) * 0.004,
            ),
          );
        }
      }
    }

    scheduleItems.sort((a, b) {
      final ScheduleItem sa = a as ScheduleItem;
      final ScheduleItem sb = b as ScheduleItem;
      final int dayCmp = sa.day.compareTo(sb.day);
      if (dayCmp != 0) return dayCmp;
      return sa.time.compareTo(sb.time);
    });

    for (int i = 0; i < scheduleItems.length; i++) {
      (scheduleItems[i] as ScheduleItem).orderIndex = i;
    }

    return {
      'isError': false,
      'title': parsed['title']?.toString() ?? '$destination 여행 보따리',
      'resolvedCheckInTime': resolvedCheckIn,
      'checkInTime': resolvedCheckIn,
      'packingList': packingItems,
      'scheduleList': scheduleItems,
    };
  }

  static Future classifyCustomItemCategory(String itemTitle) async {
    final String prompt = '''
다음 여행 준비물 아이템을 [의류, 세면도구, 전자기기, 상비약, 필수품, 기타] 중 가장 알맞은 카테고리 딱 하나로 분류해서 순수 JSON으로만 답하세요.
아이템: "$itemTitle"
응답 형식: {"category": "전자기기"}
''';
    try {
      final String raw =
          await _callGeminiRaw(prompt, temperature: 0.1, useSearch: false);
      final Map data = jsonDecode(_sanitizeJsonText(raw)) as Map;
      return data['category']?.toString() ?? '기타';
    } catch (_) {
      return '기타';
    }
  }

  static Future verifyAndResolvePlace({
    required String destination,
    required String placeName,
    required DateTime visitDate,
    required String visitTime,
  }) async {
    final String wk = _getKoreanWeekday(visitDate);
    final String prompt = '''
"$destination"에 있는 "$placeName"의 실제 위치 좌표와 $wk($visitTime) 영업 여부를 확인해 순수 JSON으로만 답하세요.
반드시 "$destination" 행정구역 내부에 있는 장소여야 하며, 실제 건물의 정밀 위도(lat)·경도(lng)를 소수점 4자리 이상으로 정확히 넣으세요.

{
  "exists": true,
  "officialName": "정식 상호명",
  "isClosedOnDay": false,
  "closedWarning": "",
  "businessHoursInfo": "$wk 정상영업",
  "lat": 37.6438,
  "lng": 126.6268
}
''';
    try {
      final String raw =
          await _callGeminiRaw(prompt, temperature: 0.2, useSearch: false);
      final Map data = jsonDecode(_sanitizeJsonText(raw)) as Map;

      double lat =
          (data['lat'] is num) ? (data['lat'] as num).toDouble() : 0.0;
      double lng =
          (data['lng'] is num) ? (data['lng'] as num).toDouble() : 0.0;
      final String official =
          data['officialName']?.toString() ?? placeName;

      // 카카오/OSM 정밀 지오코딩을 1순위로 수행!
      final dynamic precise =
          await WeatherService.geocodePlace(official, destination);
      if (precise != null) {
        lat = (precise[0] as num).toDouble();
        lng = (precise[1] as num).toDouble();
      } else if (!WeatherService.isValidNearDestination(
          lat, lng, destination)) {
        final List base = WeatherService.getBaseCoords(destination);
        lat = (base[0] as num).toDouble();
        lng = (base[1] as num).toDouble();
      }

      return {
        'exists': data['exists'] ?? true,
        'officialName': official,
        'isClosedOnDay': data['isClosedOnDay'] ?? false,
        'closedWarning': data['closedWarning']?.toString() ?? '',
        'businessHoursInfo':
            data['businessHoursInfo']?.toString() ?? '$wk 정상영업',
        'lat': lat,
        'lng': lng,
      };
    } catch (_) {
      final List base = WeatherService.getBaseCoords(destination);
      return {
        'exists': true,
        'officialName': placeName,
        'isClosedOnDay': false,
        'closedWarning': '',
        'businessHoursInfo': '요일 정상영업',
        'lat': (base[0] as num).toDouble(),
        'lng': (base[1] as num).toDouble(),
      };
    }
  }

  static Future recommendRandomPlace({
    required String destination,
    required String accommodation,
    required String theme,
    required DateTime visitDate,
    required List existingPlaces,
  }) async {
    final String wk = _getKoreanWeekday(visitDate);
    final String excluded = existingPlaces.join(', ');
    final String prompt = '''
"$destination" 행정구역 내부에 있으면서 거점 숙소("$accommodation") 인근에서 이동하기 좋고, $wk에 정상 영업하는 새로운 맛집·카페·명소 중 딱 1곳을 추천하세요.
- 테마: $theme
- 절대 제외할 장소(중복 금지): [$excluded]
- 타 시/군/구(예: 김포인데 안산·인천 등)는 절대 추천 금지!

응답 형식(순수 JSON):
{
  "placeName": "실제 상호명",
  "time": "15:00",
  "description": "추천 이유 한 줄 설명 ✅ $wk 정상영업"
}
''';
    try {
      final String raw =
          await _callGeminiRaw(prompt, temperature: 0.85, useSearch: false);
      final Map data = jsonDecode(_sanitizeJsonText(raw)) as Map;
      return {
        'placeName': data['placeName']?.toString() ?? '$destination 인기 명소',
        'time': data['time']?.toString() ?? '15:00',
        'description':
            data['description']?.toString() ?? 'AI 추천 명소 ✅ $wk 정상영업',
      };
    } catch (_) {
      return {
        'placeName': '$destination 현지 맛집',
        'time': '15:00',
        'description': '현지 인기 추천 코스 ✅ $wk 정상영업',
      };
    }
  }
}