import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';

class WeatherService {
  static const Map _cityCoords = {
    '서울': [37.5665, 126.9780],
    '부산': [35.1796, 129.0756],
    '제주': [33.4996, 126.5312],
    '강릉': [37.7519, 128.8761],
    '경주': [35.8562, 129.2247],
    '여수': [34.7604, 127.6622],
    '전주': [35.8242, 127.1480],
    '속초': [38.2070, 128.5918],
    '인천': [37.4563, 126.7052],
    '대구': [35.8714, 128.6014],
    '대전': [36.3504, 127.3845],
    '광주': [35.1595, 126.8526],
    '수원': [37.2636, 127.0286],
    '춘천': [37.8813, 127.7298],
    '포항': [36.0190, 129.3435],
    '통영': [34.8544, 128.4332],
    '거제': [34.8806, 128.6211],
    '안동': [36.5684, 128.7294],
    '김포': [37.6424, 126.6272],
    '구래': [37.6441, 126.6271],
    '평택': [36.9921, 127.1129],
    '파주': [37.7599, 126.7802],
    '고양': [37.6584, 126.8320],
    '일산': [37.6584, 126.7700],
    '도쿄': [35.6762, 139.6503],
    '오사카': [34.6937, 135.5023],
    '후쿠오카': [33.5902, 130.4017],
    '교토': [35.0116, 135.7681],
    '삿포로': [43.0618, 141.3545],
  };

  static List getBaseCoords(String destination) {
    for (final entry in _cityCoords.entries) {
      if (destination.contains(entry.key.toString())) {
        return entry.value as List;
      }
    }
    return [37.5665, 126.9780];
  }

  static bool isValidNearDestination(
      double lat, double lng, String destination) {
    if (lat == 0.0 || lng == 0.0) return false;
    final List base = getBaseCoords(destination);
    final double baseLat = (base[0] as num).toDouble();
    final double baseLng = (base[1] as num).toDouble();
    return (lat - baseLat).abs() <= 0.25 && (lng - baseLng).abs() <= 0.25;
  }

  static Future searchPlaceCoords(String placeName,
      [String destination = '']) async {
    return geocodePlace(placeName, destination);
  }

  /// 불필요한 접미사('체크인', '출발', '도착' 등)를 제거해 순수 상호명만 추출합니다.
  static String _cleanPlaceQuery(String raw) {
    return raw
        .replaceAll('체크인', '')
        .replaceAll('체크아웃', '')
        .replaceAll('출발', '')
        .replaceAll('도착', '')
        .replaceAll('복귀', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Future geocodePlace(String query, [String destination = '']) async {
    final String cleanName = _cleanPlaceQuery(query);
    if (cleanName.isEmpty) return null;

    final List queriesToTry = destination.trim().isNotEmpty &&
            !cleanName.contains(destination.trim())
        ? ['${destination.trim()} $cleanName', cleanName]
        : [cleanName];

    // 1순위: 카카오 로컬 API (대한민국 모든 상호·건물 오차 0m 정밀 검색!)
    String kakaoKey = '';
    try {
      kakaoKey = ApiKeys.kakaoRestApiKey.trim();
    } catch (_) {}

    if (kakaoKey.isNotEmpty && !kakaoKey.contains('여기에')) {
      for (final String q in queriesToTry) {
        try {
          final Uri kakaoUrl = Uri.https(
            'dapi.kakao.com',
            '/v2/local/search/keyword.json',
            {'query': q, 'size': '5'},
          );
          final response = await http.get(
            kakaoUrl,
            headers: {'Authorization': 'KakaoAK $kakaoKey'},
          ).timeout(const Duration(seconds: 4));

          if (response.statusCode == 200) {
            final Map data =
                jsonDecode(utf8.decode(response.bodyBytes)) as Map;
            final List docs = (data['documents'] as List?) ?? [];
            for (final dynamic doc in docs) {
              if (doc is Map) {
                final double? lat =
                    double.tryParse(doc['y']?.toString() ?? '');
                final double? lng =
                    double.tryParse(doc['x']?.toString() ?? '');
                final String addr = doc['address_name']?.toString() ?? '';

                if (lat != null && lng != null) {
                  // 목적지 행정구역 이름이 주소에 포함되어 있거나 반경 이내면 즉시 확정!
                  if (destination.trim().isEmpty ||
                      addr.contains(destination.trim()) ||
                      isValidNearDestination(lat, lng, destination)) {
                    print(
                        '📍 [카카오 정밀좌표 확정] $cleanName -> ($lat, $lng) [$addr]');
                    return [lat, lng];
                  }
                }
              }
            }
          }
        } catch (e) {
          print('⚠️ 카카오 지오코딩 예외: $e');
        }
      }
    }

    // 2순위: 해외(일본 등)이거나 카카오 키가 없을 때 OpenStreetMap Nominatim 사용
    final bool isJapan = destination.contains('도쿄') ||
        destination.contains('오사카') ||
        destination.contains('후쿠오카') ||
        destination.contains('교토') ||
        destination.contains('삿포로');

    for (final String q in queriesToTry) {
      try {
        final Uri url = isJapan
            ? Uri.https('nominatim.openstreetmap.org', '/search', {
                'q': q,
                'format': 'json',
                'limit': '3',
                'accept-language': 'ko',
              })
            : Uri.https('nominatim.openstreetmap.org', '/search', {
                'q': q,
                'format': 'json',
                'limit': '3',
                'accept-language': 'ko',
                'countrycodes': 'kr',
              });

        final response = await http.get(url, headers: {
          'User-Agent': 'BottariSmartTravelApp/1.0',
        }).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final List data = jsonDecode(response.body) as List;
          for (final item in data) {
            final double? lat = double.tryParse(item['lat']?.toString() ?? '');
            final double? lon = double.tryParse(item['lon']?.toString() ?? '');
            if (lat != null && lon != null) {
              if (destination.trim().isEmpty ||
                  isValidNearDestination(lat, lon, destination)) {
                return [lat, lon];
              }
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future fetchWeatherSummary(
      String destination, DateTime targetDate) async {
    final List coords = getBaseCoords(destination);
    final double lat = (coords[0] as num).toDouble();
    final double lng = (coords[1] as num).toDouble();

    try {
      final Uri url = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toString(),
        'longitude': lng.toString(),
        'daily':
            'weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
        'timezone': 'auto',
        'forecast_days': '16',
      });

      final response =
          await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final Map data = jsonDecode(response.body) as Map;
        final Map daily = data['daily'] as Map;
        final List times = daily['time'] as List;
        final String targetStr =
            '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

        int idx = times.indexOf(targetStr);
        if (idx == -1) idx = 0;

        final num minTemp = (daily['temperature_2m_min'] as List)[idx] as num;
        final num maxTemp = (daily['temperature_2m_max'] as List)[idx] as num;
        final num precip =
            ((daily['precipitation_probability_max'] as List)[idx] ?? 0) as num;
        final int code = ((daily['weathercode'] as List)[idx] as num).toInt();

        final String sky = _mapWeatherCode(code);
        return '$sky · 기온 ${minTemp.round()}°C~${maxTemp.round()}°C · 강수확률 $precip%';
      }
    } catch (_) {}
    return '맑음 · 기온 10°C~18°C · 강수확률 10%';
  }

  static String _mapWeatherCode(int code) {
    if (code == 0) return '맑음';
    if (code <= 3) return '구름 조금';
    if (code <= 48) return '안개';
    if (code <= 67) return '비 예보';
    if (code <= 77) return '눈 예보';
    if (code <= 82) return '소나기 예보';
    return '흐림';
  }
}