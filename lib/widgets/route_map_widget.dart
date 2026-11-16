import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/trip_model.dart';
import '../services/weather_service.dart';

class RouteMapWidget extends StatefulWidget {
  final String destination;
  final String accommodation;
  final List scheduleList;
  final double height;
  final int? selectedIndex;
  final Function(int)? onSelectStop;
  final Function(int)? onMarkerTap;
  final Function(int)? onStopSelected;

  const RouteMapWidget({
    super.key,
    required this.destination,
    this.accommodation = '',
    required this.scheduleList,
    this.height = 240,
    this.selectedIndex,
    this.onSelectStop,
    this.onMarkerTap,
    this.onStopSelected,
  });

  @override
  State createState() => _RouteMapWidgetState();
}

class _RouteMapWidgetState extends State<RouteMapWidget> {
  double _centerLat = 37.5665;
  double _centerLng = 126.9780;
  double _zoom = 12.0;
  int _selectedDay = 0; // 0 = 전체

  double? _stayLat;
  double? _stayLng;

  // 홀수 Day = 초록색, 짝수 Day = 하늘색 (며칠이든 명확하게 구분!)
  static const Color _oddDayColor = Color(0xFF006B3E); // 포레스트 그린
  static const Color _evenDayColor = Color(0xFF0288D1); // 스카이 블루

  Color _getColorForDay(int day) {
    return (day % 2 == 1) ? _oddDayColor : _evenDayColor;
  }

  @override
  void initState() {
    super.initState();
    _initMapCenter();
    _resolveStayCoords();
  }

  @override
  void didUpdateWidget(covariant RouteMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination ||
        oldWidget.scheduleList.length != widget.scheduleList.length) {
      _fitBoundsToItems();
    }
    if (oldWidget.accommodation != widget.accommodation) {
      _resolveStayCoords();
    }
    if (widget.selectedIndex != null &&
        widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex! >= 0 &&
        widget.selectedIndex! < widget.scheduleList.length) {
      final ScheduleItem target =
          widget.scheduleList[widget.selectedIndex!] as ScheduleItem;
      final List coords = _getSafeLatLng(target, widget.selectedIndex!);
      setState(() {
        _centerLat = (coords[0] as num).toDouble();
        _centerLng = (coords[1] as num).toDouble();
        if (_zoom < 13.5) _zoom = 14.0;
      });
    }
  }

  void _initMapCenter() {
    final List base = WeatherService.getBaseCoords(widget.destination);
    _centerLat = (base[0] as num).toDouble();
    _centerLng = (base[1] as num).toDouble();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitBoundsToItems();
    });
  }

  Future _resolveStayCoords() async {
    final String stay = widget.accommodation.trim();
    if (stay.isEmpty) return;

    for (final dynamic raw in widget.scheduleList) {
      final ScheduleItem item = raw as ScheduleItem;
      if (item.placeName.contains(stay) ||
          item.placeName.contains('체크인') ||
          item.placeName.contains('출발')) {
        if (WeatherService.isValidNearDestination(
            item.lat, item.lng, widget.destination)) {
          if (mounted) {
            setState(() {
              _stayLat = item.lat;
              _stayLng = item.lng;
            });
          }
          return;
        }
      }
    }

    final dynamic searched = await WeatherService.searchPlaceCoords(
      stay,
      widget.destination,
    );
    if (searched != null && mounted) {
      setState(() {
        _stayLat = (searched[0] as num).toDouble();
        _stayLng = (searched[1] as num).toDouble();
      });
    }
  }

  List _getSafeLatLng(ScheduleItem item, int index) {
    final List base = WeatherService.getBaseCoords(widget.destination);
    final double baseLat = (base[0] as num).toDouble();
    final double baseLng = (base[1] as num).toDouble();

    if (item.lat == 0.0 ||
        item.lng == 0.0 ||
        (item.lat - baseLat).abs() > 0.25 ||
        (item.lng - baseLng).abs() > 0.25) {
      return [
        baseLat + ((index % 3) - 1) * 0.004,
        baseLng + ((index % 4) - 1.5) * 0.005,
      ];
    }
    return [item.lat, item.lng];
  }

  List _getFilteredItemsWithOriginalIndex() {
    final List result = [];
    for (int i = 0; i < widget.scheduleList.length; i++) {
      final ScheduleItem item = widget.scheduleList[i] as ScheduleItem;
      if (_selectedDay == 0 || item.day == _selectedDay) {
        result.add({
          'item': item,
          'originalIndex': i,
          'globalNumber': i + 1,
        });
      }
    }
    return result;
  }

  void _fitBoundsToItems() {
    final List filtered = _getFilteredItemsWithOriginalIndex();
    if (filtered.isEmpty) {
      final List base = WeatherService.getBaseCoords(widget.destination);
      setState(() {
        _centerLat = (base[0] as num).toDouble();
        _centerLng = (base[1] as num).toDouble();
        _zoom = 12.5;
      });
      return;
    }

    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    for (int i = 0; i < filtered.length; i++) {
      final ScheduleItem item = filtered[i]['item'] as ScheduleItem;
      final int origIdx = filtered[i]['originalIndex'] as int;
      final List coords = _getSafeLatLng(item, origIdx);
      final double lat = (coords[0] as num).toDouble();
      final double lng = (coords[1] as num).toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    if (_stayLat != null && _stayLng != null) {
      if (_stayLat! < minLat) minLat = _stayLat!;
      if (_stayLat! > maxLat) maxLat = _stayLat!;
      if (_stayLng! < minLng) minLng = _stayLng!;
      if (_stayLng! > maxLng) maxLng = _stayLng!;
    }

    final double centerLat = (minLat + maxLat) / 2.0;
    final double centerLng = (minLng + maxLng) / 2.0;
    final double latSpan = (maxLat - minLat).abs();
    final double lngSpan = (maxLng - minLng).abs();
    final double maxSpan = math.max(latSpan, lngSpan);

    double targetZoom = 13.5;
    if (maxSpan > 0.18) {
      targetZoom = 10.5;
    } else if (maxSpan > 0.09) {
      targetZoom = 11.5;
    } else if (maxSpan > 0.04) {
      targetZoom = 12.5;
    } else if (maxSpan > 0.015) {
      targetZoom = 13.5;
    } else {
      targetZoom = 14.2;
    }

    if (mounted) {
      setState(() {
        _centerLat = centerLat;
        _centerLng = centerLng;
        _zoom = targetZoom;
      });
    }
  }

  static double _lonToTileX(double lon, int z) {
    return (lon + 180.0) / 360.0 * (1 << z);
  }

  static double _latToTileY(double lat, int z) {
    final double latRad = lat * math.pi / 180.0;
    return (1.0 -
            math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
        2.0 *
        (1 << z);
  }

  static double _tileXToLon(double x, int z) {
    return x / (1 << z) * 360.0 - 180.0;
  }

  static double _tileYToLat(double y, int z) {
    final double n = math.pi - 2.0 * math.pi * y / (1 << z);
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final int z = _zoom.round().clamp(7, 17);
    final double currentTileX = _lonToTileX(_centerLng, z);
    final double currentTileY = _latToTileY(_centerLat, z);

    final double newTileX = currentTileX - (details.delta.dx / 256.0);
    final double newTileY = currentTileY - (details.delta.dy / 256.0);

    setState(() {
      _centerLng = _tileXToLon(newTileX, z);
      _centerLat = _tileYToLat(newTileY, z).clamp(-85.0, 85.0);
    });
  }

  Offset _latLngToPixel(
      double lat, double lng, double width, double height, int z) {
    final double centerTileX = _lonToTileX(_centerLng, z);
    final double centerTileY = _latToTileY(_centerLat, z);
    final double pointTileX = _lonToTileX(lng, z);
    final double pointTileY = _latToTileY(lat, z);

    final double dx = (pointTileX - centerTileX) * 256.0 + (width / 2.0);
    final double dy = (pointTileY - centerTileY) * 256.0 + (height / 2.0);
    return Offset(dx, dy);
  }

  /// 일정 중 가장 큰 Day 번호까지 1부터 빠짐없이 버튼 목록을 생성합니다.
  List _getAvailableDays() {
    int maxDay = 1;
    for (final dynamic raw in widget.scheduleList) {
      final ScheduleItem item = raw as ScheduleItem;
      if (item.day > maxDay) {
        maxDay = item.day;
      }
    }
    final List days = [];
    for (int d = 1; d <= maxDay; d++) {
      days.add(d);
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final List availableDays = _getAvailableDays();
    final List filteredEntries = _getFilteredItemsWithOriginalIndex();
    final int z = _zoom.round().clamp(7, 17);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1번째 줄: 지도 타이틀 + 우측 전체 정렬 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.map_outlined,
                  size: 18,
                  color: Color(0xFF006B3E),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${widget.destination} 실시간 동선 지도',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2924),
                    ),
                  ),
                ),
                InkWell(
                  onTap: _fitBoundsToItems,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F3EC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.my_location,
                          size: 14,
                          color: Color(0xFF006B3E),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '전체 정렬',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF006B3E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2번째 줄: PC 마우스 드래그 + 폰 터치 스크롤이 모두 되는 가로 스크롤 Day 필터 바!
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildDayFilterChip(
                      label: '전체',
                      isSelected: _selectedDay == 0,
                      activeColor: const Color(0xFF1F2924),
                      onTap: () {
                        setState(() => _selectedDay = 0);
                        _fitBoundsToItems();
                      },
                    ),
                    for (final dynamic d in availableDays)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _buildDayFilterChip(
                          label: 'Day $d',
                          isSelected: _selectedDay == (d as int),
                          activeColor: _getColorForDay(d),
                          onTap: () {
                            setState(() => _selectedDay = d);
                            _fitBoundsToItems();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 3번째 줄: 인터랙티브 지도 캔버스
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(18),
            ),
            child: SizedBox(
              height: widget.height,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double mapW = constraints.maxWidth;
                  final double mapH = constraints.maxHeight;

                  final double centerTileX = _lonToTileX(_centerLng, z);
                  final double centerTileY = _latToTileY(_centerLat, z);
                  final int baseTileX = centerTileX.floor();
                  final int baseTileY = centerTileY.floor();

                  final List tileWidgets = [];
                  for (int dx = -2; dx <= 2; dx++) {
                    for (int dy = -2; dy <= 2; dy++) {
                      final int tx = baseTileX + dx;
                      final int ty = baseTileY + dy;
                      final int maxTile = 1 << z;
                      if (ty < 0 || ty >= maxTile) continue;
                      final int wrappedTx =
                          ((tx % maxTile) + maxTile) % maxTile;

                      final double leftPx =
                          (tx - centerTileX) * 256.0 + (mapW / 2.0);
                      final double topPx =
                          (ty - centerTileY) * 256.0 + (mapH / 2.0);

                      tileWidgets.add(
                        Positioned(
                          left: leftPx,
                          top: topPx,
                          width: 256.5,
                          height: 256.5,
                          child: Image.network(
                            'https://tile.openstreetmap.org/$z/$wrappedTx/$ty.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFFEAEFEA),
                            ),
                          ),
                        ),
                      );
                    }
                  }

                  Offset? stayPixel;
                  if (_stayLat != null && _stayLng != null) {
                    stayPixel =
                        _latLngToPixel(_stayLat!, _stayLng!, mapW, mapH, z);
                  }

                  final List markerPoints = [];
                  for (int i = 0; i < filteredEntries.length; i++) {
                    final ScheduleItem item =
                        filteredEntries[i]['item'] as ScheduleItem;
                    final int origIdx =
                        filteredEntries[i]['originalIndex'] as int;
                    final int globalNum =
                        filteredEntries[i]['globalNumber'] as int;
                    final List coords = _getSafeLatLng(item, origIdx);
                    final Offset pt = _latLngToPixel(
                      (coords[0] as num).toDouble(),
                      (coords[1] as num).toDouble(),
                      mapW,
                      mapH,
                      z,
                    );
                    markerPoints.add({
                      'offset': pt,
                      'day': item.day,
                      'originalIndex': origIdx,
                      'number': globalNum,
                      'color': _getColorForDay(item.day),
                      'isSelected': widget.selectedIndex == origIdx,
                    });
                  }

                  return Listener(
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        setState(() {
                          if (pointerSignal.scrollDelta.dy < 0) {
                            _zoom = (_zoom + 1.0).clamp(7.0, 17.0);
                          } else {
                            _zoom = (_zoom - 1.0).clamp(7.0, 17.0);
                          }
                        });
                      }
                    },
                    child: GestureDetector(
                      onPanUpdate: _onPanUpdate,
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Container(color: const Color(0xFFE8EFEA)),
                          ...tileWidgets,
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _RouteLinePainter(
                                points: markerPoints,
                                stayOffset: stayPixel,
                              ),
                            ),
                          ),
                          if (stayPixel != null)
                            Positioned(
                              left: stayPixel.dx - 16,
                              top: stayPixel.dy - 16,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F2924),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFFFD54F),
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.hotel,
                                  size: 16,
                                  color: Color(0xFFFFD54F),
                                ),
                              ),
                            ),
                          for (final dynamic m in markerPoints)
                            Positioned(
                              left: (m['offset'] as Offset).dx -
                                  ((m['isSelected'] == true) ? 16 : 13),
                              top: (m['offset'] as Offset).dy -
                                  ((m['isSelected'] == true) ? 16 : 13),
                              child: GestureDetector(
                                onTap: () {
                                  final int idx = m['originalIndex'] as int;
                                  if (widget.onSelectStop != null) {
                                    widget.onSelectStop!(idx);
                                  }
                                  if (widget.onMarkerTap != null) {
                                    widget.onMarkerTap!(idx);
                                  }
                                  if (widget.onStopSelected != null) {
                                    widget.onStopSelected!(idx);
                                  }
                                },
                                child: Container(
                                  width: (m['isSelected'] == true) ? 32 : 26,
                                  height: (m['isSelected'] == true) ? 32 : 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: m['color'] as Color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: (m['isSelected'] == true)
                                          ? const Color(0xFFFFD54F)
                                          : Colors.white,
                                      width:
                                          (m['isSelected'] == true) ? 3.0 : 2.0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '${m['number']}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize:
                                          (m['isSelected'] == true) ? 13 : 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Column(
                              children: [
                                _buildZoomBtn(Icons.add, () {
                                  setState(() {
                                    _zoom = (_zoom + 1.0).clamp(7.0, 17.0);
                                  });
                                }),
                                const SizedBox(height: 6),
                                _buildZoomBtn(Icons.remove, () {
                                  setState(() {
                                    _zoom = (_zoom - 1.0).clamp(7.0, 17.0);
                                  });
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayFilterChip({
    required String label,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : const Color(0xFFF1F4F2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF5A6660),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 18, color: const Color(0xFF1F2924)),
        ),
      ),
    );
  }
}

class _RouteLinePainter extends CustomPainter {
  final List points;
  final Offset? stayOffset;

  _RouteLinePainter({
    required this.points,
    this.stayOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    for (int i = 0; i < points.length - 1; i++) {
      final Map curr = points[i] as Map;
      final Map next = points[i + 1] as Map;
      final Offset p1 = curr['offset'] as Offset;
      final Offset p2 = next['offset'] as Offset;
      final int day1 = curr['day'] as int;
      final int day2 = next['day'] as int;

      final Paint borderPaint = Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round;

      if (day1 != day2 && stayOffset != null) {
        final Paint linePaint1 = Paint()
          ..color = curr['color'] as Color
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round;
        final Paint linePaint2 = Paint()
          ..color = next['color'] as Color
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(p1, stayOffset!, borderPaint);
        canvas.drawLine(p1, stayOffset!, linePaint1);

        canvas.drawLine(stayOffset!, p2, borderPaint);
        canvas.drawLine(stayOffset!, p2, linePaint2);
      } else {
        final Paint linePaint = Paint()
          ..color = curr['color'] as Color
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(p1, p2, borderPaint);
        canvas.drawLine(p1, p2, linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RouteLinePainter oldDelegate) => true;
}