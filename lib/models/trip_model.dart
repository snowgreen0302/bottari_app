import 'dart:convert';

class PackingItem {
  String id;
  String title;
  String category;
  bool isChecked;

  PackingItem({
    required this.id,
    required this.title,
    required this.category,
    this.isChecked = false,
  });

  Map toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'isChecked': isChecked,
    };
  }

  factory PackingItem.fromMap(Map map) {
    return PackingItem(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      category: map['category']?.toString() ?? '기타',
      isChecked: map['isChecked'] == true,
    );
  }
}

class ScheduleItem {
  String id;
  int day;
  String time;
  String placeName;
  String description;
  int orderIndex;
  double lat;
  double lng;

  ScheduleItem({
    required this.id,
    required this.day,
    required this.time,
    required this.placeName,
    required this.description,
    required this.orderIndex,
    this.lat = 35.1796,
    this.lng = 129.0756,
  });

  Map toMap() {
    return {
      'id': id,
      'day': day,
      'time': time,
      'placeName': placeName,
      'description': description,
      'orderIndex': orderIndex,
      'lat': lat,
      'lng': lng,
    };
  }

  factory ScheduleItem.fromMap(Map map) {
    return ScheduleItem(
      id: map['id']?.toString() ?? '',
      day: map['day'] is int
          ? map['day'] as int
          : int.tryParse(map['day']?.toString() ?? '1') ?? 1,
      time: map['time']?.toString() ?? '',
      placeName: map['placeName']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      orderIndex: map['orderIndex'] is int
          ? map['orderIndex'] as int
          : int.tryParse(map['orderIndex']?.toString() ?? '0') ?? 0,
      lat: map['lat'] is num
          ? (map['lat'] as num).toDouble()
          : double.tryParse(map['lat']?.toString() ?? '') ?? 35.1796,
      lng: map['lng'] is num
          ? (map['lng'] as num).toDouble()
          : double.tryParse(map['lng']?.toString() ?? '') ?? 129.0756,
    );
  }
}

class TripPlan {
  String id;
  String title;
  String destination;
  String accommodation;
  String checkInTime;
  DateTime startDate;
  DateTime endDate;
  String theme;
  String weatherSummary;
  List packingList;
  List scheduleList;

  TripPlan({
    required this.id,
    required this.title,
    required this.destination,
    this.accommodation = '',
    this.checkInTime = '15:00',
    required this.startDate,
    required this.endDate,
    required this.theme,
    required this.weatherSummary,
    required this.packingList,
    required this.scheduleList,
  });

  double get packingProgress {
    if (packingList.isEmpty) return 0.0;
    final int checkedCount = packingList
        .where((item) => (item as PackingItem).isChecked)
        .length;
    return checkedCount / packingList.length;
  }

  int get totalDays {
    final int diff = endDate.difference(startDate).inDays + 1;
    return diff < 1 ? 1 : diff;
  }

  Map toMap() {
    return {
      'id': id,
      'title': title,
      'destination': destination,
      'accommodation': accommodation,
      'checkInTime': checkInTime,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'theme': theme,
      'weatherSummary': weatherSummary,
      'packingList': packingList
          .map((item) => (item as PackingItem).toMap())
          .toList(),
      'scheduleList': scheduleList
          .map((item) => (item as ScheduleItem).toMap())
          .toList(),
    };
  }

  factory TripPlan.fromMap(Map map) {
    final List rawPacking = (map['packingList'] as List?) ?? [];
    final List rawSchedule = (map['scheduleList'] as List?) ?? [];

    return TripPlan(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      destination: map['destination']?.toString() ?? '',
      accommodation: map['accommodation']?.toString() ?? '',
      checkInTime: map['checkInTime']?.toString() ?? '15:00',
      startDate:
          DateTime.tryParse(map['startDate']?.toString() ?? '') ??
          DateTime.now(),
      endDate:
          DateTime.tryParse(map['endDate']?.toString() ?? '') ?? DateTime.now(),
      theme: map['theme']?.toString() ?? '',
      weatherSummary: map['weatherSummary']?.toString() ?? '',
      packingList: rawPacking
          .map((item) => PackingItem.fromMap(Map.from(item as Map)))
          .toList(),
      scheduleList: rawSchedule
          .map((item) => ScheduleItem.fromMap(Map.from(item as Map)))
          .toList(),
    );
  }

  String toJson() => json.encode(toMap());
  factory TripPlan.fromJson(String source) =>
      TripPlan.fromMap(Map.from(json.decode(source) as Map));
}
