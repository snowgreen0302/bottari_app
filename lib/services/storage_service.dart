import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_model.dart';

class StorageService {
  // 새로운 저장 키를 사용하여 기존에 들어있던 예시 일정을 즉시 비웁니다.
  static const String _tripsKey = 'bottari_saved_trips_v3_clean';
  static const String _apiKeyPref = 'bottari_gemini_api_key';

  static Future<List<TripPlan>> loadTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_tripsKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decoded = json.decode(jsonString);
      return decoded
          .map((item) => TripPlan.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTrips(List<TripPlan> trips) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(trips.map((t) => t.toMap()).toList());
    await prefs.setString(_tripsKey, encoded);
  }

  static Future<void> updateSingleTrip(TripPlan updatedTrip) async {
    final trips = await loadTrips();
    final idx = trips.indexWhere((t) => t.id == updatedTrip.id);
    if (idx >= 0) {
      trips[idx] = updatedTrip;
    } else {
      trips.insert(0, updatedTrip);
    }
    await saveTrips(trips);
  }

  static Future<void> deleteTrip(String tripId) async {
    final trips = await loadTrips();
    trips.removeWhere((t) => t.id == tripId);
    await saveTrips(trips);
  }

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyPref) ?? '';
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, key.trim());
  }
}