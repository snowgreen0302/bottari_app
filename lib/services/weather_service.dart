import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherService {
  static const Map _cityCoords = {
    '부산': [35.1796, 129.0756],
    '제주': [33.4996, 126.5312],
    '강릉': [37.7519, 128.8761],
    '경주': [35.8562, 129.2247],
    '여수': [34.7604, 127.6622],
    '속초': [38.2070, 128.5918],
    '전주': [35.8242, 127.1480],
    '대전': [36.3504, 127.3845],
    '대구': [35.8714, 128.6014],
    '광주': [35.1595, 126.8526],
    '인천': [37.4563, 126.7052],
    '서울': [37.5665, 126.9780],
    '도쿄': [35.6762, 139.6503],
    '오사카': [34.6937, 135.5023],
    '후쿠오카': [33.5902, 130.4017],
  };

  static List getBaseCoords(String destination) {
    for (final entry in _cityCoords.entries) {
      if (destination.contains(entry.key.toString())) {
        final List val = entry.value as List;
        return [(val[0] as num).toDouble(), (val[1] as num).toDouble()];
      }
    }
    return [37.5665, 126.9780];
  }

  /// 목적지 중심에서 너무 멀리 떨어진 엉뚱한 좌표인지 확인합니다.
  static bool _isValidNearDestination(
    String destination,
    double lat,
    double lng,
  ) {
    if (destination.trim().isEmpty) return true;
    final List base = getBaseCoords(destination);
    final double baseLat = (base[0] as num).toDouble();
    final double baseLng = (base[1] as num).toDouble();
    final double diffLat = (lat - baseLat).abs();
    final double diffLng = (lng - baseLng).abs();
    // 목적지 반경 약 1.2도(약 120km) 이내인 경우만 정상 좌표로 인정
    return diffLat <= 1.2 && diffLng <= 1.2;
  }

  /// OpenStreetMap Nominatim으로 정확한 실제 좌표를 검색합니다.
  static Future searchPlaceCoords(String destination, String placeName) async {
    final List queries = [
      '${destination.trim()} ${placeName.trim()}',
      placeName.trim(),
    ];

    final bool isJapan =
        destination.contains('도쿄') ||
        destination.contains('오사카') ||
        destination.contains('후쿠오카');

    for (final dynamic qObj in queries) {
      final String q = qObj.toString().trim();
      if (q.isEmpty) continue;
      try {
        final Map<String, String> params = {
          'q': q,
          'format': 'json',
          'limit': '3',
          'accept-language': 'ko',
        };
        if (!isJapan) {
          params['countrycodes'] = 'kr';
        }

        final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
        final resp = await http
            .get(uri, headers: {'User-Agent': 'BottariTravelPlannerApp/1.0'})
            .timeout(const Duration(seconds: 5));

        if (resp.statusCode == 200) {
          final dynamic decoded = json.decode(utf8.decode(resp.bodyBytes));
          if (decoded is List && decoded.isNotEmpty) {
            for (final dynamic item in decoded) {
              final double? lat = double.tryParse(
                item['lat']?.toString() ?? '',
              );
              final double? lon = double.tryParse(
                item['lon']?.toString() ?? '',
              );
              if (lat != null &&
                  lon != null &&
                  _isValidNearDestination(destination, lat, lon)) {
                return [lat, lon];
              }
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  static Future _resolveCityCoordsOnline(String destination) async {
    final dynamic searched = await searchPlaceCoords('', destination);
    if (searched is List && searched.length >= 2) {
      return searched;
    }
    return getBaseCoords(destination);
  }

  static Future<String> fetchWeatherSummary(
    String destination,
    DateTime targetDate,
  ) async {
    final List coords = await _resolveCityCoordsOnline(destination);
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': coords[0].toString(),
        'longitude': coords[1].toString(),
        'daily': 'weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
        'timezone': 'auto',
        'forecast_days': '16',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final dynamic data = json.decode(utf8.decode(response.bodyBytes));
        final dynamic daily = data['daily'];
        final List times = (daily['time'] as List?) ?? [];
        final List maxTemps = (daily['temperature_2m_max'] as List?) ?? [];
        final List minTemps = (daily['temperature_2m_min'] as List?) ?? [];
        final List probs =
            (daily['precipitation_probability_max'] as List?) ?? [];
        final List codes = (daily['weathercode'] as List?) ?? [];

        final String targetStr =
            '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

        int idx = times.indexOf(targetStr);
        if (idx == -1 && times.isNotEmpty) {
          idx = 0;
        }

        if (idx != -1 && idx != times.length && maxTemps.isNotEmpty) {
          final int tMax = (double.tryParse(maxTemps[idx].toString()) ?? 18)
              .round();
          final int tMin = (double.tryParse(minTemps[idx].toString()) ?? 10)
              .round();
          final int rainProb = (probs.length > idx && probs[idx] != null)
              ? (double.tryParse(probs[idx].toString()) ?? 0).round()
              : 0;
          final int code = (codes.length > idx && codes[idx] != null)
              ? (int.tryParse(codes[idx].toString()) ?? 0)
              : 0;

          final String sky = _mapWeatherCodeToKorean(code, rainProb);
          return '$sky · 기온 $tMin°C~$tMax°C · 강수확률 $rainProb%';
        }
      }
    } catch (_) {}

    return '맑음 · 기온 10°C~18°C · 강수확률 10%';
  }

  static String _mapWeatherCodeToKorean(int code, int rainProb) {
    if (code >= 71 && code <= 77) return '눈 예보';
    if (code >= 51 || rainProb >= 60) return '비 예보';
    if (code == 2 || code == 3) return '구름많음';
    if (code == 1) return '대체로 맑음';
    return '맑음';
  }
}
