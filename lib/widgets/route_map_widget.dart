import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/trip_model.dart';
import '../services/weather_service.dart';

class RouteMapWidget extends StatefulWidget {
  final String destination;
  final String accommodation;
  final List scheduleList;
  final int? selectedIndex;
  final ValueChanged onSelectStop;

  const RouteMapWidget({
    super.key,
    required this.destination,
    this.accommodation = '',
    required this.scheduleList,
    required this.selectedIndex,
    required this.onSelectStop,
  });

  @override
  State createState() => _RouteMapWidgetState();
}

class _RouteMapWidgetState extends State {
  int _selectedDayFilter = 0;
  double _centerLat = 35.1796;
  double _centerLng = 129.0756;
  int _zoom = 12;
  bool _initialized = false;
  List? _resolvedStayCoords;
  String _lastStayQuery = '';

  @override
  RouteMapWidget get widget => super.widget as RouteMapWidget;

  @override
  void initState() {
    super.initState();
    _resolveStayLocation();
    _fitAllPins(setStateNow: false);
    _initialized = true;
  }

  @override
  void didUpdateWidget(covariant RouteMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.accommodation != oldWidget.accommodation ||
        widget.destination != oldWidget.destination) {
      _resolveStayLocation();
    }
    if (widget.selectedIndex != null &&
        widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex! >= 0 &&
        widget.selectedIndex! < widget.scheduleList.length) {
      final ScheduleItem item =
          widget.scheduleList[widget.selectedIndex!] as ScheduleItem;
      setState(() {
        _centerLat = item.lat;
        _centerLng = item.lng;
        if (_zoom < 14) _zoom = 14;
      });
    } else if (widget.scheduleList.length != oldWidget.scheduleList.length ||
        widget.destination != oldWidget.destination) {
      _fitAllPins(setStateNow: true);
    }
  }

  /// 일정 중 숙소 항목이 있으면 그 좌표를 쓰고, 없으면 숙소명으로 실제 좌표를 검색합니다.
  Future _resolveStayLocation() async {
    final String stayName = widget.accommodation.trim();
    for (final dynamic raw in widget.scheduleList) {
      final ScheduleItem s = raw as ScheduleItem;
      if ((stayName.isNotEmpty && s.placeName.contains(stayName)) ||
          s.placeName.contains('숙소') ||
          s.placeName.contains('체크인') ||
          s.placeName.contains('호텔') ||
          s.placeName.contains('펜션') ||
          s.placeName.contains('리조트') ||
          s.placeName.contains('게스트하우스') ||
          s.description.contains('숙소') ||
          s.description.contains('체크인')) {
        final List safe = _getSafeLatLng(s);
        if (mounted) {
          setState(() {
            _resolvedStayCoords = safe;
          });
        }
        return;
      }
    }

    if (stayName.isNotEmpty && _lastStayQuery != stayName) {
      _lastStayQuery = stayName;
      final dynamic searched = await WeatherService.searchPlaceCoords(
        widget.destination,
        stayName,
      );
      if (searched is List && searched.length >= 2 && mounted) {
        setState(() {
          _resolvedStayCoords = [
            (searched[0] as num).toDouble(),
            (searched[1] as num).toDouble(),
          ];
        });
      }
    }
  }

  List? _getAccommodationLatLng() {
    if (_resolvedStayCoords != null) return _resolvedStayCoords;
    final String stayName = widget.accommodation.trim();
    for (final dynamic raw in widget.scheduleList) {
      final ScheduleItem s = raw as ScheduleItem;
      if ((stayName.isNotEmpty && s.placeName.contains(stayName)) ||
          s.placeName.contains('숙소') ||
          s.placeName.contains('체크인') ||
          s.placeName.contains('호텔') ||
          s.description.contains('체크인')) {
        return _getSafeLatLng(s);
      }
    }
    if (stayName.isNotEmpty) {
      return WeatherService.getBaseCoords(widget.destination);
    }
    return null;
  }

  List _getAvailableDays() {
    final List days = [];
    for (final dynamic s in widget.scheduleList) {
      final int d = (s as ScheduleItem).day;
      if (!days.contains(d)) {
        days.add(d);
      }
    }
    days.sort();
    return days;
  }

  List _getVisibleItems() {
    final List visible = [];
    for (int i = 0; i < widget.scheduleList.length; i++) {
      final ScheduleItem item = widget.scheduleList[i] as ScheduleItem;
      if (_selectedDayFilter == 0 || item.day == _selectedDayFilter) {
        visible.add(item);
      }
    }
    return visible;
  }

  List _getSafeLatLng(ScheduleItem item) {
    final List base = WeatherService.getBaseCoords(widget.destination);
    final double baseLat = (base[0] as num).toDouble();
    final double baseLng = (base[1] as num).toDouble();

    if ((item.lat - baseLat).abs() > 1.2 || (item.lng - baseLng).abs() > 1.2) {
      final int idx = item.orderIndex;
      return [
        baseLat + ((idx % 3) - 1) * 0.008,
        baseLng + ((idx % 4) - 1.5) * 0.010,
      ];
    }
    return [item.lat, item.lng];
  }

  void _fitAllPins({bool setStateNow = true}) {
    final List visible = _getVisibleItems();
    final List base = WeatherService.getBaseCoords(widget.destination);

    if (visible.isEmpty) {
      _centerLat = (base[0] as num).toDouble();
      _centerLng = (base[1] as num).toDouble();
      _zoom = 12;
      if (setStateNow && mounted) setState(() {});
      return;
    }

    double minLat = 999.0;
    double maxLat = -999.0;
    double minLng = 999.0;
    double maxLng = -999.0;

    for (final dynamic e in visible) {
      final ScheduleItem s = e as ScheduleItem;
      final List safe = _getSafeLatLng(s);
      final double lat = (safe[0] as num).toDouble();
      final double lng = (safe[1] as num).toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    final List? stayCoords = _getAccommodationLatLng();
    if (stayCoords != null) {
      final double sLat = (stayCoords[0] as num).toDouble();
      final double sLng = (stayCoords[1] as num).toDouble();
      if (sLat < minLat) minLat = sLat;
      if (sLat > maxLat) maxLat = sLat;
      if (sLng < minLng) minLng = sLng;
      if (sLng > maxLng) maxLng = sLng;
    }

    _centerLat = (minLat + maxLat) / 2.0;
    _centerLng = (minLng + maxLng) / 2.0;

    final double latSpan = (maxLat - minLat).abs();
    final double lngSpan = (maxLng - minLng).abs();
    final double maxSpan = math.max(latSpan, lngSpan);

    if (maxSpan < 0.015) {
      _zoom = 14;
    } else if (maxSpan < 0.045) {
      _zoom = 13;
    } else if (maxSpan < 0.12) {
      _zoom = 12;
    } else if (maxSpan < 0.28) {
      _zoom = 11;
    } else {
      _zoom = 10;
    }

    if (setStateNow && mounted) setState(() {});
  }

  Color _colorForDay(int day) {
    if (day == 1) return const Color(0xFF006B3E);
    if (day == 2) return const Color(0xFF0077B6);
    if (day == 3) return const Color(0xFFD97706);
    return const Color(0xFF7C3AED);
  }

  double _lonToTileX(double lon, int zoom) {
    return (lon + 180.0) / 360.0 * math.pow(2.0, zoom);
  }

  double _latToTileY(double lat, int zoom) {
    final double latRad = lat * math.pi / 180.0;
    return (1.0 -
            math.log(math.tan(latRad) + (1.0 / math.cos(latRad))) / math.pi) /
        2.0 *
        math.pow(2.0, zoom);
  }

  double _tileXToLon(double tileX, int zoom) {
    return tileX / math.pow(2.0, zoom) * 360.0 - 180.0;
  }

  double _tileYToLat(double tileY, int zoom) {
    final double n = math.pi - 2.0 * math.pi * tileY / math.pow(2.0, zoom);
    return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
  }

  void _panMapByPixels(double dx, double dy) {
    final double currentTileX = _lonToTileX(_centerLng, _zoom);
    final double currentTileY = _latToTileY(_centerLat, _zoom);

    final double newTileX = currentTileX - (dx / 256.0);
    final double newTileY = currentTileY - (dy / 256.0);

    setState(() {
      _centerLng = _tileXToLon(newTileX, _zoom).clamp(-179.0, 179.0);
      _centerLat = _tileYToLat(newTileY, _zoom).clamp(-80.0, 80.0);
    });
  }

  void _changeZoom(int delta) {
    setState(() {
      _zoom = (_zoom + delta).clamp(7, 17);
    });
  }

  String _buildTileUrl(int z, int x, int y) {
    final int maxTile = math.pow(2, z).toInt();
    final int wrappedX = ((x % maxTile) + maxTile) % maxTile;
    final int clampedY = y.clamp(0, maxTile - 1);
    final Uri uri = Uri.https(
      'tile.openstreetmap.org',
      '/$z/$wrappedX/$clampedY.png',
    );
    return uri.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      _fitAllPins(setStateNow: false);
      _initialized = true;
    }

    final List availableDays = _getAvailableDays();
    if (_selectedDayFilter != 0 &&
        !availableDays.contains(_selectedDayFilter)) {
      _selectedDayFilter = 0;
    }

    final List visibleGlobalIndices = [];
    final List visibleItems = [];
    for (int i = 0; i < widget.scheduleList.length; i++) {
      final ScheduleItem item = widget.scheduleList[i] as ScheduleItem;
      if (_selectedDayFilter == 0 || item.day == _selectedDayFilter) {
        visibleGlobalIndices.add(i);
        visibleItems.add(item);
      }
    }

    final double centerTileX = _lonToTileX(_centerLng, _zoom);
    final double centerTileY = _latToTileY(_centerLat, _zoom);
    final int baseTileX = centerTileX.floor();
    final int baseTileY = centerTileY.floor();
    final List? stayCoords = _getAccommodationLatLng();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                _buildDayChip(0, '전체'),
                for (final dynamic d in availableDays) ...[
                  const SizedBox(width: 4),
                  _buildDayChip(d as int, 'Day $d'),
                ],
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _fitAllPins(setStateNow: true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      size: 16,
                      color: Color(0xFF006B3E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(17),
            ),
            child: SizedBox(
              height: 235,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double w = constraints.maxWidth;
                  final double h = constraints.maxHeight;

                  final double baseLeft =
                      (w / 2.0) - (centerTileX - baseTileX) * 256.0;
                  final double baseTop =
                      (h / 2.0) - (centerTileY - baseTileY) * 256.0;

                  Offset? stayPixelPoint;
                  if (stayCoords != null) {
                    final double sTx = _lonToTileX(
                      (stayCoords[1] as num).toDouble(),
                      _zoom,
                    );
                    final double sTy = _latToTileY(
                      (stayCoords[0] as num).toDouble(),
                      _zoom,
                    );
                    stayPixelPoint = Offset(
                      (w / 2.0) + (sTx - centerTileX) * 256.0,
                      (h / 2.0) + (sTy - centerTileY) * 256.0,
                    );
                  }

                  final List exactPoints = [];
                  for (final dynamic e in visibleItems) {
                    final ScheduleItem item = e as ScheduleItem;
                    final List safe = _getSafeLatLng(item);
                    final double lat = (safe[0] as num).toDouble();
                    final double lng = (safe[1] as num).toDouble();

                    final double tx = _lonToTileX(lng, _zoom);
                    final double ty = _latToTileY(lat, _zoom);
                    final double px = (w / 2.0) + (tx - centerTileX) * 256.0;
                    final double py = (h / 2.0) + (ty - centerTileY) * 256.0;
                    exactPoints.add(Offset(px, py));
                  }

                  return Listener(
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        if (pointerSignal.scrollDelta.dy < 0) {
                          _changeZoom(1);
                        } else if (pointerSignal.scrollDelta.dy > 0) {
                          _changeZoom(-1);
                        }
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (details) {
                        _panMapByPixels(details.delta.dx, details.delta.dy);
                      },
                      onDoubleTap: () => _changeZoom(1),
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          for (int dx = -2; dx <= 2; dx++)
                            for (int dy = -2; dy <= 2; dy++)
                              Positioned(
                                key: ValueKey(
                                  'tile_${_zoom}_${baseTileX + dx}_${baseTileY + dy}',
                                ),
                                left: baseLeft + dx * 256.0,
                                top: baseTop + dy * 256.0,
                                width: 256.0,
                                height: 256.0,
                                child: Image.network(
                                  _buildTileUrl(
                                    _zoom,
                                    baseTileX + dx,
                                    baseTileY + dy,
                                  ),
                                  fit: BoxFit.fill,
                                  errorBuilder: (_, __, ___) =>
                                      Container(color: const Color(0xFFEAF2EF)),
                                ),
                              ),
                          // 동선 연결 (일차 변경 시 자동으로 숙소(stayPoint)를 경유하여 연결)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _RouteLinePainter(
                                points: exactPoints,
                                items: visibleItems,
                                stayPoint: stayPixelPoint,
                                selectedDayFilter: _selectedDayFilter,
                                colorForDay: _colorForDay,
                              ),
                            ),
                          ),
                          // 거점 숙소 마커 배지 (🏨)
                          if (stayPixelPoint != null)
                            Positioned(
                              left: stayPixelPoint.dx - 16.0,
                              top: stayPixelPoint.dy - 16.0,
                              child: Tooltip(
                                message: widget.accommodation.trim().isEmpty
                                    ? '거점 숙소'
                                    : '숙소: ${widget.accommodation}',
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1C1C1E),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.amber,
                                      width: 2.2,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black38,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.hotel_rounded,
                                    color: Colors.amber,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          // 번호 마커 핀
                          for (int idx = 0; idx < visibleItems.length; idx++)
                            _buildMarkerPin(
                              localIdx: idx,
                              globalIdx: visibleGlobalIndices[idx] as int,
                              item: visibleItems[idx] as ScheduleItem,
                              point: exactPoints[idx] as Offset,
                            ),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildZoomButton(
                                  icon: Icons.add,
                                  onTap: () => _changeZoom(1),
                                ),
                                const SizedBox(height: 6),
                                _buildZoomButton(
                                  icon: Icons.remove,
                                  onTap: () => _changeZoom(-1),
                                ),
                              ],
                            ),
                          ),
                          if (widget.selectedIndex != null &&
                              widget.selectedIndex! <
                                  widget.scheduleList.length)
                            Positioned(
                              left: 10,
                              right: 54,
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF006B3E),
                                    width: 1.2,
                                  ),
                                ),
                                child: Text(
                                  '📍 ${widget.selectedIndex! + 1}번 핀: ${(widget.scheduleList[widget.selectedIndex!] as ScheduleItem).placeName} (${(widget.scheduleList[widget.selectedIndex!] as ScheduleItem).time})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF006B3E),
                                  ),
                                ),
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

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 18, color: const Color(0xFF1C1C1E)),
        ),
      ),
    );
  }

  Widget _buildDayChip(int dayValue, String label) {
    final bool selected = _selectedDayFilter == dayValue;
    final Color activeColor = dayValue == 0
        ? const Color(0xFF006B3E)
        : _colorForDay(dayValue);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDayFilter = dayValue;
          _fitAllPins(setStateNow: false);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildMarkerPin({
    required int localIdx,
    required int globalIdx,
    required ScheduleItem item,
    required Offset point,
  }) {
    final bool isSelected = widget.selectedIndex == globalIdx;
    final Color color = _colorForDay(item.day);
    final double pinSize = isSelected ? 28.0 : 23.0;

    return Positioned(
      left: point.dx - 65.0,
      top: point.dy - (pinSize / 2.0) - (isSelected ? 24.0 : 0.0),
      width: 130.0,
      child: GestureDetector(
        onTap: () => widget.onSelectStop(globalIdx),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  item.placeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            Container(
              width: pinSize,
              height: pinSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: isSelected ? 2.5 : 2.0,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '${globalIdx + 1}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSelected ? 12 : 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteLinePainter extends CustomPainter {
  final List points;
  final List items;
  final Offset? stayPoint;
  final int selectedDayFilter;
  final Color Function(int) colorForDay;

  _RouteLinePainter({
    required this.points,
    required this.items,
    required this.stayPoint,
    required this.selectedDayFilter,
    required this.colorForDay,
  });

  void _drawStyledSegment(Canvas canvas, Offset p1, Offset p2, Color color) {
    final Paint outlinePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 5.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint linePaint = Paint()
      ..color = color.withOpacity(0.9)
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(p1, p2, outlinePaint);
    canvas.drawLine(p1, p2, linePaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // 2일차 이상 단독 필터 선택 시: 숙소(stayPoint)에서 해당 일차 첫 장소로 출발하는 선 표시
    if (selectedDayFilter >= 2 && stayPoint != null) {
      final Offset firstPt = points.first as Offset;
      if ((stayPoint! - firstPt).distance > 6.0) {
        _drawStyledSegment(
          canvas,
          stayPoint!,
          firstPt,
          colorForDay(selectedDayFilter),
        );
      }
    }

    if (points.length < 2) return;

    for (int i = 0; i < points.length - 1; i++) {
      final ScheduleItem currItem = items[i] as ScheduleItem;
      final ScheduleItem nextItem = items[i + 1] as ScheduleItem;
      final Offset p1 = points[i] as Offset;
      final Offset p2 = points[i + 1] as Offset;

      // 같은 날(Day) 안에서 이동할 때
      if (currItem.day == nextItem.day) {
        _drawStyledSegment(canvas, p1, p2, colorForDay(currItem.day));
      } else {
        // 날짜가 바뀔 때(예: 1일차 4번 -> 2일차 5번):
        // 1일차 마지막 장소 -> 숙소 복귀(1일차 색상) + 숙소 출발 -> 2일차 첫 장소(2일차 색상)
        if (stayPoint != null) {
          if ((p1 - stayPoint!).distance > 6.0) {
            _drawStyledSegment(
              canvas,
              p1,
              stayPoint!,
              colorForDay(currItem.day),
            );
          }
          if ((stayPoint! - p2).distance > 6.0) {
            _drawStyledSegment(
              canvas,
              stayPoint!,
              p2,
              colorForDay(nextItem.day),
            );
          }
        } else {
          _drawStyledSegment(canvas, p1, p2, colorForDay(nextItem.day));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RouteLinePainter oldDelegate) => true;
}
