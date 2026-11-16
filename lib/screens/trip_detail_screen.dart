import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/trip_model.dart';
import '../services/ai_service.dart';
import '../services/poster_saver.dart';
import '../services/storage_service.dart';
import '../services/weather_service.dart';
import '../widgets/route_map_widget.dart';

class TripDetailScreen extends StatefulWidget {
  final TripPlan trip;

  const TripDetailScreen({super.key, required this.trip});

  @override
  State createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State {
  late TripPlan _trip;
  int _currentTabIndex = 0;
  bool _isClassifyingItem = false;
  bool _isGeocodingPlace = false;
  int? _selectedStopIndex;

  // 포스터 캡처 시 CORS 보안 에러가 나지 않도록 지도 타일 바이트를 캐싱합니다.
  final Map _tileBytesCache = {};

  @override
  TripDetailScreen get widget => super.widget as TripDetailScreen;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
  }

  Future _saveChanges() async {
    await StorageService.updateSingleTrip(_trip);
  }

  void _realignScheduleDaysAndTimes(List orderedSlots) {
    orderedSlots.sort((a, b) {
      final int dayCmp = (a['day'] as int).compareTo(b['day'] as int);
      if (dayCmp != 0) return dayCmp;
      return (a['time'] as String).compareTo(b['time'] as String);
    });

    for (int i = 0; i < _trip.scheduleList.length; i++) {
      _trip.scheduleList[i].orderIndex = i;
      if (i < orderedSlots.length) {
        _trip.scheduleList[i].day = orderedSlots[i]['day'] as int;
        _trip.scheduleList[i].time = orderedSlots[i]['time'] as String;
      }
    }
  }

  String _getFormattedDateForDay(int day) {
    final DateTime targetDate = _trip.startDate.add(Duration(days: day - 1));
    const List weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final String wk = weekdays[targetDate.weekday - 1].toString();
    return '${targetDate.month}.${targetDate.day}($wk)';
  }

  // 홀수 일차(Day 1, 3, 5...): 초록색 / 짝수 일차(Day 2, 4, 6...): 하늘색
  Color _dayColor(int day) {
    return (day % 2 == 1)
        ? const Color(0xFF006B3E)
        : const Color(0xFF0288D1);
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

  /// 웹 환경에서도 RepaintBoundary 캡처가 100% 성공하도록 지도 타일을 바이트로 미리 받아옵니다.
  Future _preloadPosterMapTiles(int zoom, int baseTileX, int baseTileY) async {
    final List futures = [];
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        final String url = _buildTileUrl(zoom, baseTileX + dx, baseTileY + dy);
        if (!_tileBytesCache.containsKey(url)) {
          futures.add(() async {
            try {
              final resp = await http
                  .get(Uri.parse(url))
                  .timeout(const Duration(seconds: 4));
              if (resp.statusCode == 200) {
                _tileBytesCache[url] = resp.bodyBytes;
              }
            } catch (_) {}
          }());
        }
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures.cast());
    }
  }

  List _getSafeLatLng(ScheduleItem item) {
    final List base = WeatherService.getBaseCoords(_trip.destination);
    final double baseLat = (base[0] as num).toDouble();
    final double baseLng = (base[1] as num).toDouble();

    if (item.lat == 0.0 ||
        item.lng == 0.0 ||
        (item.lat - baseLat).abs() > 0.25 ||
        (item.lng - baseLng).abs() > 0.25) {
      final int idx = item.orderIndex;
      return [
        baseLat + ((idx % 3) - 1) * 0.004,
        baseLng + ((idx % 4) - 1.5) * 0.005,
      ];
    }
    return [item.lat, item.lng];
  }

  List? _findStayLatLngInTrip() {
    final String stayName = _trip.accommodation.trim();
    for (final ScheduleItem s in _trip.scheduleList) {
      if ((stayName.isNotEmpty && s.placeName.contains(stayName)) ||
          s.placeName.contains('숙소') ||
          s.placeName.contains('체크인') ||
          s.placeName.contains('호텔') ||
          s.placeName.contains('펜션') ||
          s.placeName.contains('리조트') ||
          s.description.contains('숙소') ||
          s.description.contains('체크인')) {
        return _getSafeLatLng(s);
      }
    }
    if (stayName.isNotEmpty) {
      return WeatherService.getBaseCoords(_trip.destination);
    }
    return null;
  }

  Map _computePosterMapMeta() {
    final List base = WeatherService.getBaseCoords(_trip.destination);
    final List? stayCoords = _findStayLatLngInTrip();
    double minLat = 999.0;
    double maxLat = -999.0;
    double minLng = 999.0;
    double maxLng = -999.0;

    if (_trip.scheduleList.isEmpty) {
      minLat = maxLat = (base[0] as num).toDouble();
      minLng = maxLng = (base[1] as num).toDouble();
    } else {
      for (final ScheduleItem s in _trip.scheduleList) {
        final List safe = _getSafeLatLng(s);
        final double lat = (safe[0] as num).toDouble();
        final double lng = (safe[1] as num).toDouble();
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lng < minLng) minLng = lng;
        if (lng > maxLng) maxLng = lng;
      }
      if (stayCoords != null) {
        final double sLat = (stayCoords[0] as num).toDouble();
        final double sLng = (stayCoords[1] as num).toDouble();
        if (sLat < minLat) minLat = sLat;
        if (sLat > maxLat) maxLat = sLat;
        if (sLng < minLng) minLng = sLng;
        if (sLng > maxLng) maxLng = sLng;
      }
    }

    final double centerLat = (minLat + maxLat) / 2.0;
    final double centerLng = (minLng + maxLng) / 2.0;
    final double maxSpan = math.max(
      (maxLat - minLat).abs(),
      (maxLng - minLng).abs(),
    );

    int zoom = 12;
    if (maxSpan < 0.02) {
      zoom = 13;
    } else if (maxSpan < 0.07) {
      zoom = 12;
    } else if (maxSpan < 0.18) {
      zoom = 11;
    } else {
      zoom = 10;
    }

    final double centerTileX = _lonToTileX(centerLng, zoom);
    final double centerTileY = _latToTileY(centerLat, zoom);

    return {
      'zoom': zoom,
      'centerTileX': centerTileX,
      'centerTileY': centerTileY,
      'baseTileX': centerTileX.floor(),
      'baseTileY': centerTileY.floor(),
      'stayCoords': stayCoords,
    };
  }

  Widget _buildPosterRealMapSection(Map mapMeta) {
    final int zoom = mapMeta['zoom'] as int;
    final double centerTileX = mapMeta['centerTileX'] as double;
    final double centerTileY = mapMeta['centerTileY'] as double;
    final int baseTileX = mapMeta['baseTileX'] as int;
    final int baseTileY = mapMeta['baseTileY'] as int;
    final List? stayCoords = mapMeta['stayCoords'] as List?;

    return Container(
      width: double.infinity,
      height: 175,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2EF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF006B3E).withOpacity(0.3),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double w = constraints.maxWidth;
            final double h = constraints.maxHeight;

            final double baseLeft =
                (w / 2.0) - (centerTileX - baseTileX) * 256.0;
            final double baseTop =
                (h / 2.0) - (centerTileY - baseTileY) * 256.0;

            Offset? stayPixelPt;
            if (stayCoords != null) {
              final double sTx = _lonToTileX(
                (stayCoords[1] as num).toDouble(),
                zoom,
              );
              final double sTy = _latToTileY(
                (stayCoords[0] as num).toDouble(),
                zoom,
              );
              stayPixelPt = Offset(
                ((w / 2.0) + (sTx - centerTileX) * 256.0).clamp(18.0, w - 18.0),
                ((h / 2.0) + (sTy - centerTileY) * 256.0).clamp(32.0, h - 18.0),
              );
            }

            final List mapPoints = [];
            for (final ScheduleItem item in _trip.scheduleList) {
              final List safe = _getSafeLatLng(item);
              final double lat = (safe[0] as num).toDouble();
              final double lng = (safe[1] as num).toDouble();

              final double tx = _lonToTileX(lng, zoom);
              final double ty = _latToTileY(lat, zoom);
              final double px = (w / 2.0) + (tx - centerTileX) * 256.0;
              final double py = (h / 2.0) + (ty - centerTileY) * 256.0;
              mapPoints.add(
                Offset(px.clamp(18.0, w - 18.0), py.clamp(32.0, h - 18.0)),
              );
            }

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (int dx = -2; dx <= 2; dx++)
                  for (int dy = -1; dy <= 1; dy++)
                    Positioned(
                      left: baseLeft + dx * 256.0,
                      top: baseTop + dy * 256.0,
                      width: 256.0,
                      height: 256.0,
                      child: Builder(
                        builder: (_) {
                          final String url = _buildTileUrl(
                            zoom,
                            baseTileX + dx,
                            baseTileY + dy,
                          );
                          final Uint8List? cached =
                              _tileBytesCache[url] as Uint8List?;
                          if (cached != null) {
                            return Image.memory(cached, fit: BoxFit.fill);
                          }
                          return Image.network(
                            url,
                            fit: BoxFit.fill,
                            errorBuilder: (_, __, ___) =>
                                Container(color: const Color(0xFFEAF2EF)),
                          );
                        },
                      ),
                    ),
                Positioned.fill(
                  child: Container(color: Colors.white.withOpacity(0.12)),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PosterMapPinPainter(
                      points: mapPoints,
                      scheduleList: _trip.scheduleList,
                      stayPoint: stayPixelPt,
                      dayColor: _dayColor,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF006B3E).withOpacity(0.35),
                      ),
                    ),
                    child: const Text(
                      '🗺️ 전체 이동 동선 (숙소 복귀·출발 포함)',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF006B3E),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 팝업을 열자마자 자동으로 고화질 PNG를 생성해 두고, 하단 [사진 다운로드] 버튼으로 즉시 저장합니다.
  Future _showShareRouteCardDialog() async {
    if (_trip.scheduleList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유할 동선 일정이 없습니다. 먼저 동선을 추가해주세요.')),
      );
      return;
    }

    final GlobalKey boundaryKey = GlobalKey();
    Uint8List? capturedBytes;
    bool isDownloading = false;
    bool autoCaptureStarted = false;

    final Map mapMeta = _computePosterMapMeta();
    await _preloadPosterMapTiles(
      mapMeta['zoom'] as int,
      mapMeta['baseTileX'] as int,
      mapMeta['baseTileY'] as int,
    );

    final Map groupedByDay = {};
    for (int i = 0; i < _trip.scheduleList.length; i++) {
      final ScheduleItem item = _trip.scheduleList[i];
      if (!groupedByDay.containsKey(item.day)) {
        groupedByDay[item.day] = [];
      }
      (groupedByDay[item.day] as List).add({
        'globalNumber': i + 1,
        'item': item,
      });
    }
    final List sortedDays = groupedByDay.keys.toList()..sort();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          if (!autoCaptureStarted) {
            autoCaptureStarted = true;
            Future.delayed(const Duration(milliseconds: 280), () async {
              try {
                final BuildContext? bCtx = boundaryKey.currentContext;
                if (bCtx != null) {
                  final RenderRepaintBoundary boundary =
                      bCtx.findRenderObject() as RenderRepaintBoundary;
                  final ui.Image image = await boundary.toImage(
                    pixelRatio: 2.5,
                  );
                  final ByteData? byteData = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  if (byteData != null && ctx.mounted) {
                    setModalState(() {
                      capturedBytes = byteData.buffer.asUint8List();
                    });
                  }
                }
              } catch (_) {}
            });
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460, maxHeight: 780),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F4),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.photo_camera_back_rounded,
                          color: Color(0xFF006B3E),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '고화질 동선 이미지 변환 완료!',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: RepaintBoundary(
                        key: boundaryKey,
                        child: _buildPosterCardWidget(
                          sortedDays,
                          groupedByDay,
                          mapMeta,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF006B3E),
                              side: const BorderSide(color: Color(0xFF006B3E)),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () async {
                              final String textSummary = _buildShareTextSummary(
                                sortedDays,
                                groupedByDay,
                              );
                              await Clipboard.setData(
                                ClipboardData(text: textSummary),
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('일정 요약 텍스트가 클립보드에 복사되었습니다!'),
                                    backgroundColor: Color(0xFF006B3E),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text(
                              '카톡 텍스트 복사',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF006B3E),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: isDownloading
                                ? null
                                : () async {
                                    setModalState(() => isDownloading = true);
                                    try {
                                      if (capturedBytes == null) {
                                        final RenderRepaintBoundary boundary =
                                            boundaryKey.currentContext!
                                                    .findRenderObject()
                                                as RenderRepaintBoundary;
                                        final ui.Image image = await boundary
                                            .toImage(pixelRatio: 2.5);
                                        final ByteData? byteData = await image
                                            .toByteData(
                                              format: ui.ImageByteFormat.png,
                                            );
                                        if (byteData != null) {
                                          capturedBytes = byteData.buffer
                                              .asUint8List();
                                        }
                                      }

                                      if (capturedBytes != null) {
                                        final String safeFileName =
                                            '${_trip.destination}_보따리_동선표.png';
                                        final bool ok =
                                            await triggerPosterDownload(
                                              capturedBytes!,
                                              safeFileName,
                                            );
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    ok
                                                        ? '📥 동선 포스터 사진 다운로드가 시작되었습니다!'
                                                        : '이미지가 생성되었습니다!',
                                                  ),
                                                  backgroundColor: const Color(
                                                    0xFF006B3E,
                                                  ),
                                                ),
                                              );
                                        }
                                      }
                                    } catch (_) {}
                                    if (ctx.mounted) {
                                      setModalState(
                                        () => isDownloading = false,
                                      );
                                    }
                                  },
                            icon: isDownloading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.download_rounded, size: 19),
                            label: const Text(
                              '사진 다운로드',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPosterCardWidget(
    List sortedDays,
    Map groupedByDay,
    Map mapMeta,
  ) {
    final String stayLabel = _trip.accommodation.trim().isEmpty
        ? '${_trip.destination} 거점 숙소'
        : _trip.accommodation.trim();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF006B3E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(19)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '🎒 보따리 공식 동선표 · ${_trip.destination}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${_getFormattedDateForDay(1)} ~ ${_getFormattedDateForDay(_trip.totalDays)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _trip.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _trip.theme,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.wb_sunny_rounded,
                            color: Colors.amber,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _trip.weatherSummary,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_trip.accommodation.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.hotel_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '거점 숙소: ${_trip.accommodation} (체크인 ${_trip.checkInTime})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildPosterRealMapSection(mapMeta),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final dynamic dayObj in sortedDays) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _dayColor(dayObj as int),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Day $dayObj · ${_getFormattedDateForDay(dayObj)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Divider(
                          color: _dayColor(dayObj).withOpacity(0.3),
                          thickness: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if ((dayObj as int) >= 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.hotel_rounded,
                            size: 16,
                            color: _dayColor(dayObj),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '오전 출발 거점: $stayLabel에서 출발',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: _dayColor(dayObj),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final dynamic entry in (groupedByDay[dayObj] as List))
                    _buildPosterTimelineRow(
                      globalNum: entry['globalNumber'] as int,
                      item: entry['item'] as ScheduleItem,
                      color: _dayColor(dayObj),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPosterTimelineRow({
    required int globalNum,
    required ScheduleItem item,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              '$globalNum',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 46,
            margin: const EdgeInsets.only(top: 3),
            child: Text(
              item.time,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAF9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.placeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  if (item.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildShareTextSummary(List sortedDays, Map groupedByDay) {
    final String stayLabel = _trip.accommodation.trim().isEmpty
        ? '${_trip.destination} 숙소'
        : _trip.accommodation.trim();
    final StringBuffer sb = StringBuffer();
    sb.writeln('🎒 [${_trip.title}] 여행 동선표');
    sb.writeln('📍 목적지: ${_trip.destination}');
    sb.writeln('🏨 거점 숙소: $stayLabel (체크인 ${_trip.checkInTime})');
    sb.writeln('☀️ 날씨: ${_trip.weatherSummary}');
    sb.writeln('');

    for (final dynamic dayObj in sortedDays) {
      final int d = dayObj as int;
      sb.writeln('■ Day $d (${_getFormattedDateForDay(d)})');
      if (d >= 2) {
        sb.writeln('  🏨 [오전 출발] $stayLabel에서 출발');
      }
      final List entries = groupedByDay[d] as List;
      for (final dynamic entry in entries) {
        final int num = entry['globalNumber'] as int;
        final ScheduleItem item = entry['item'] as ScheduleItem;
        sb.writeln('  $num. [${item.time}] ${item.placeName}');
      }
      sb.writeln('');
    }
    return sb.toString().trim();
  }

  Future _showAddPackingItemDialog() async {
    final TextEditingController controller = TextEditingController();
    final dynamic addedTitleObj = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('나만의 준비물 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '물건 이름만 입력하면 AI가 백그라운드에서 분석해 알맞은 카테고리로 자동 분류합니다.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '예: 고데기, 인공눈물, 보조배터리, 잠옷',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('AI 자동 분류 추가'),
          ),
        ],
      ),
    );

    final String addedTitle = addedTitleObj?.toString().trim() ?? '';
    if (addedTitle.isEmpty) return;

    setState(() => _isClassifyingItem = true);
    final String category = await AiService.classifyCustomItemCategory(
      addedTitle,
    );

    final PackingItem newItem = PackingItem(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      title: addedTitle,
      category: category,
      isChecked: false,
    );

    setState(() {
      _trip.packingList.add(newItem);
      _isClassifyingItem = false;
    });
    await _saveChanges();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI가 "$addedTitle" 아이템을 [$category] 카테고리에 자동 분류했습니다!'),
          backgroundColor: const Color(0xFF006B3E),
        ),
      );
    }
  }

  Future _showAddScheduleDialog() async {
    final TextEditingController timeController = TextEditingController(
      text: '15:00',
    );
    final TextEditingController placeController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    int selectedDay = 1;
    bool isPickingRandom = false;
    final List pickedHistory = _trip.scheduleList
        .map((e) => e.placeName)
        .toList();

    final dynamic confirmed = await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('새로운 동선 장소 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '직접 장소를 입력하거나, 아래 랜덤 추천 버튼을 눌러 당일 영업하는 새로운 명소를 추천받아 보세요!',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF006B3E),
                      side: const BorderSide(
                        color: Color(0xFF006B3E),
                        width: 1.3,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: isPickingRandom
                        ? null
                        : () async {
                            setModalState(() => isPickingRandom = true);
                            final DateTime targetDate = _trip.startDate.add(
                              Duration(days: selectedDay - 1),
                            );
                            final dynamic rec =
                                await AiService.recommendRandomPlace(
                                  destination: _trip.destination,
                                  accommodation: _trip.accommodation,
                                  theme: _trip.theme,
                                  visitDate: targetDate,
                                  existingPlaces: pickedHistory,
                                );
                            final String recName =
                                rec['placeName']?.toString() ?? '';
                            if (recName.isNotEmpty &&
                                !pickedHistory.contains(recName)) {
                              pickedHistory.add(recName);
                            }
                            setModalState(() {
                              placeController.text = recName;
                              timeController.text =
                                  rec['time']?.toString() ?? '15:00';
                              descController.text =
                                  rec['description']?.toString() ?? '';
                              isPickingRandom = false;
                            });
                          },
                    icon: isPickingRandom
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.casino_outlined, size: 19),
                    label: Text(
                      isPickingRandom
                          ? 'AI가 영업 중인 장소를 고르는 중...'
                          : '🎲 AI 랜덤 장소 추천받기 (다시 뽑기 가능)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField(
                  value: selectedDay,
                  decoration: const InputDecoration(labelText: '일차 선택'),
                  items: List.generate(_trip.totalDays, (idx) => idx + 1)
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text('Day $d (${_getFormattedDateForDay(d)})'),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val is int) setModalState(() => selectedDay = val);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: timeController,
                  decoration: const InputDecoration(
                    labelText: '방문 시간 (예: 15:00)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: placeController,
                  decoration: const InputDecoration(
                    labelText: '장소명 (실제 상호명/관광지)',
                    hintText: '직접 입력하거나 위 랜덤 추천 버튼을 눌러보세요',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: '간단 메모 (선택)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('영업 확인 후 추가'),
            ),
          ],
        ),
      ),
    );

    final String placeName = placeController.text.trim();
    final String visitTime = timeController.text.trim();
    if (confirmed == true && placeName.isNotEmpty) {
      setState(() => _isGeocodingPlace = true);

      final DateTime visitDate = _trip.startDate.add(
        Duration(days: selectedDay - 1),
      );
      final dynamic checkResult = await AiService.verifyAndResolvePlace(
        destination: _trip.destination,
        placeName: placeName,
        visitDate: visitDate,
        visitTime: visitTime,
      );

      setState(() => _isGeocodingPlace = false);
      if (!mounted) return;

      final bool exists = checkResult['exists'] == true;
      final bool isClosed = checkResult['isClosedOnDay'] == true;
      final String officialName =
          checkResult['officialName']?.toString() ?? placeName;
      final String closedWarning =
          checkResult['closedWarning']?.toString() ?? '';
      final String hoursInfo =
          checkResult['businessHoursInfo']?.toString() ?? '';

      if (!exists || isClosed) {
        final dynamic forceAdd = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  !exists
                      ? Icons.help_outline_rounded
                      : Icons.event_busy_rounded,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 8),
                Text(!exists ? '장소 확인 필요' : '방문 요일 휴무일 주의'),
              ],
            ),
            content: Text(
              !exists
                  ? '"${_trip.destination}"에서 "$placeName"의 실제 영업 정보를 찾을 수 없습니다.\n이름이 정확한지 확인해 주세요. 그래도 일정에 추가할까요?'
                  : '"$officialName"은(는) 선택하신 Day $selectedDay(${_getFormattedDateForDay(selectedDay)})에 휴무이거나 영업시간 외일 가능성이 높습니다.\n\n• 사유: $closedWarning\n• 영업정보: $hoursInfo\n\n그래도 일정에 추가하시겠습니까?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소 (다시 선택)'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('그래도 추가'),
              ),
            ],
          ),
        );

        if (forceAdd != true) return;
      }

      final double lat = (checkResult['lat'] as num).toDouble();
      final double lng = (checkResult['lng'] as num).toDouble();

      String finalDesc = descController.text.trim();
      if (finalDesc.isEmpty) {
        finalDesc = hoursInfo.isNotEmpty ? '영업정보: $hoursInfo' : '사용자 추가 일정';
      } else if (hoursInfo.isNotEmpty && !finalDesc.contains(hoursInfo)) {
        finalDesc = '$finalDesc · ($hoursInfo)';
      }

      final String newId = 'sched_${DateTime.now().millisecondsSinceEpoch}';
      final ScheduleItem addedItem = ScheduleItem(
        id: newId,
        day: selectedDay,
        time: visitTime,
        placeName: officialName,
        description: finalDesc,
        orderIndex: _trip.scheduleList.length,
        lat: lat,
        lng: lng,
      );

      setState(() {
        _trip.scheduleList.add(addedItem);
        _trip.scheduleList.sort((a, b) {
          final int dayCmp = a.day.compareTo(b.day);
          if (dayCmp != 0) return dayCmp;
          return a.time.compareTo(b.time);
        });
        for (int i = 0; i < _trip.scheduleList.length; i++) {
          _trip.scheduleList[i].orderIndex = i;
        }
        _selectedStopIndex = _trip.scheduleList.indexWhere(
          (e) => e.id == newId,
        );
      });
      await _saveChanges();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "$officialName" 영업 확인 및 지도 핀 등록이 완료되었습니다!'),
            backgroundColor: const Color(0xFF006B3E),
          ),
        );
      }
    }
  }

  Widget _buildWeatherAndProgressHeader() {
    final int percent = (_trip.packingProgress * 100).round();
    final int checkedCount = _trip.packingList
        .where((e) => (e as PackingItem).isChecked)
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.wb_sunny_rounded,
                color: Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _trip.weatherSummary,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (_trip.accommodation.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.hotel_rounded,
                  color: Color(0xFF006B3E),
                  size: 17,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '숙소 거점: ${_trip.accommodation} (체크인 ${_trip.checkInTime})',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF006B3E),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '테마: ${_trip.theme}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '짐 싸기 진행률',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                '$percent% 완료 ($checkedCount/${_trip.packingList.length})',
                style: const TextStyle(
                  color: Color(0xFF006B3E),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _trip.packingProgress,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF006B3E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistView() {
    final Map grouped = {};
    for (final dynamic raw in _trip.packingList) {
      final PackingItem item = raw as PackingItem;
      if (!grouped.containsKey(item.category)) {
        grouped[item.category] = [];
      }
      (grouped[item.category] as List).add(item);
    }

    final List categories = grouped.keys.toList();

    return Column(
      children: [
        _buildWeatherAndProgressHeader(),
        if (_isClassifyingItem)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('AI가 아이템 카테고리를 자동 분류하고 있습니다...'),
              ],
            ),
          ),
        Expanded(
          child: categories.isEmpty
              ? const Center(child: Text('준비물이 없습니다. 우측 하단 + 버튼으로 추가해보세요!'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                  itemCount: categories.length,
                  itemBuilder: (context, catIdx) {
                    final String category = categories[catIdx].toString();
                    final List items = grouped[category] as List;
                    final int checkedInCat = items
                        .where((i) => (i as PackingItem).isChecked)
                        .length;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF006B3E)
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      category,
                                      style: const TextStyle(
                                        color: Color(0xFF006B3E),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$checkedInCat/${items.length}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...items.map((rawItem) {
                              final PackingItem item = rawItem as PackingItem;
                              return Dismissible(
                                key: ValueKey(item.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: Colors.redAccent,
                                  child: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.white,
                                  ),
                                ),
                                onDismissed: (_) async {
                                  setState(() {
                                    _trip.packingList.removeWhere(
                                      (e) => (e as PackingItem).id == item.id,
                                    );
                                  });
                                  await _saveChanges();
                                },
                                child: ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.only(
                                    left: 8,
                                    right: 8,
                                  ),
                                  leading: Checkbox(
                                    value: item.isChecked,
                                    activeColor: const Color(0xFF006B3E),
                                    onChanged: (checked) async {
                                      setState(() {
                                        item.isChecked = checked ?? false;
                                      });
                                      await _saveChanges();
                                    },
                                  ),
                                  title: GestureDetector(
                                    onTap: () async {
                                      setState(() {
                                        item.isChecked = !item.isChecked;
                                      });
                                      await _saveChanges();
                                    },
                                    child: Text(
                                      item.title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        decoration: item.isChecked
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: item.isChecked
                                            ? Colors.grey
                                            : const Color(0xFF1C1C1E),
                                      ),
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: '준비물 삭제',
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.redAccent.withOpacity(0.8),
                                      size: 20,
                                    ),
                                    onPressed: () async {
                                      setState(() {
                                        _trip.packingList.removeWhere(
                                          (e) =>
                                              (e as PackingItem).id == item.id,
                                        );
                                      });
                                      await _saveChanges();
                                    },
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildScheduleView() {
    return Column(
      children: [
        RouteMapWidget(
          destination: _trip.destination,
          accommodation: _trip.accommodation,
          scheduleList: _trip.scheduleList,
          selectedIndex: _selectedStopIndex,
          onSelectStop: (idx) {
            setState(() => _selectedStopIndex = idx as int);
          },
        ),
        if (_isGeocodingPlace)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  '실제 존재하는 장소인지 및 방문 요일 휴무 여부를 점검하고 있습니다...',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF006B3E).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.hotel_rounded,
                size: 17,
                color: Color(0xFF006B3E),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _trip.accommodation.trim().isEmpty
                      ? '1일차 종료 후 숙소 복귀 · 2일차 아침 숙소 출발 동선이 지도에 자동 반영됩니다.'
                      : '1일차 종료 후 [${_trip.accommodation}] 복귀 · 2일차 아침 숙소 출발 동선이 자동 연결됩니다.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF006B3E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _trip.scheduleList.isEmpty
              ? const Center(child: Text('등록된 일정이 없습니다. 우측 하단 버튼으로 추가해보세요!'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                  itemCount: _trip.scheduleList.length,
                  onReorder: (oldIndex, newIndex) async {
                    setState(() {
                      final List currentSlots = _trip.scheduleList
                          .map(
                            (s) => {
                              'day': (s as ScheduleItem).day,
                              'time': s.time,
                            },
                          )
                          .toList();

                      if (newIndex > oldIndex) newIndex -= 1;
                      final ScheduleItem moved =
                          _trip.scheduleList.removeAt(oldIndex) as ScheduleItem;
                      _trip.scheduleList.insert(newIndex, moved);

                      _realignScheduleDaysAndTimes(currentSlots);
                      _selectedStopIndex = newIndex;
                    });
                    await _saveChanges();
                    if (mounted) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          duration: Duration(seconds: 1),
                          content: Text('동선 순서 변경에 맞춰 날짜·시간·지도가 자동 조정되었습니다.'),
                        ),
                      );
                    }
                  },
                  itemBuilder: (context, index) {
                    final ScheduleItem sched =
                        _trip.scheduleList[index] as ScheduleItem;
                    final bool isSelected = _selectedStopIndex == index;
                    final Color badgeColor = _dayColor(sched.day);

                    return Dismissible(
                      key: ValueKey('sched_${sched.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      onDismissed: (_) async {
                        setState(() {
                          _trip.scheduleList.removeAt(index);
                          for (int i = 0; i < _trip.scheduleList.length; i++) {
                            (_trip.scheduleList[i] as ScheduleItem).orderIndex =
                                i;
                          }
                        });
                        await _saveChanges();
                      },
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSelected
                                ? badgeColor
                                : Colors.grey.shade200,
                            width: isSelected ? 1.8 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          onTap: () {
                            setState(() => _selectedStopIndex = index);
                          },
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          leading: Container(
                            width: 76,
                            height: 52,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Day ${sched.day} ${_getFormattedDateForDay(sched.day)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    sched.time,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: badgeColor.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: badgeColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  sched.placeName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              sched.description,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '일정 삭제',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent.withOpacity(0.85),
                                  size: 20,
                                ),
                                onPressed: () async {
                                  setState(() {
                                    _trip.scheduleList.removeAt(index);
                                    for (
                                      int i = 0;
                                      i < _trip.scheduleList.length;
                                      i++
                                    ) {
                                      (_trip.scheduleList[i] as ScheduleItem)
                                              .orderIndex =
                                          i;
                                    }
                                    if (_selectedStopIndex == index) {
                                      _selectedStopIndex = null;
                                    }
                                  });
                                  await _saveChanges();
                                },
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.drag_handle_rounded,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_trip.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF006B3E).withOpacity(0.12),
                foregroundColor: const Color(0xFF006B3E),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _showShareRouteCardDialog,
              icon: const Icon(Icons.photo_camera_back_rounded, size: 18),
              label: const Text(
                '동선 한 장 요약',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
      body: _currentTabIndex == 0
          ? _buildChecklistView()
          : _buildScheduleView(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF006B3E),
        foregroundColor: Colors.white,
        onPressed: _currentTabIndex == 0
            ? _showAddPackingItemDialog
            : _showAddScheduleDialog,
        icon: const Icon(Icons.add),
        label: Text(_currentTabIndex == 0 ? '준비물 추가 (AI 분류)' : '동선 추가'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (idx) => setState(() => _currentTabIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_rtl_rounded),
            label: '체크리스트 화면',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            label: '동선 일정 뷰',
          ),
        ],
      ),
    );
  }
}

class _PosterMapPinPainter extends CustomPainter {
  final List points;
  final List scheduleList;
  final Offset? stayPoint;
  final Color Function(int) dayColor;

  _PosterMapPinPainter({
    required this.points,
    required this.scheduleList,
    required this.stayPoint,
    required this.dayColor,
  });

  void _drawSegment(Canvas canvas, Offset p1, Offset p2, Color color) {
    final Paint outlinePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(p1, p2, outlinePaint);
    canvas.drawLine(p1, p2, linePaint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    for (int i = 0; i < points.length - 1; i++) {
      final ScheduleItem curr = scheduleList[i] as ScheduleItem;
      final ScheduleItem next = scheduleList[i + 1] as ScheduleItem;
      final Offset p1 = points[i] as Offset;
      final Offset p2 = points[i + 1] as Offset;

      if (curr.day == next.day) {
        _drawSegment(canvas, p1, p2, dayColor(curr.day));
      } else if (stayPoint != null) {
        if ((p1 - stayPoint!).distance > 5.0) {
          _drawSegment(canvas, p1, stayPoint!, dayColor(curr.day));
        }
        if ((stayPoint! - p2).distance > 5.0) {
          _drawSegment(canvas, stayPoint!, p2, dayColor(next.day));
        }
      } else {
        _drawSegment(canvas, p1, p2, dayColor(next.day));
      }
    }

    if (stayPoint != null) {
      final Paint stayPaint = Paint()..color = const Color(0xFF1C1C1E);
      final Paint stayBorder = Paint()
        ..color = Colors.amber
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(stayPoint!, 10.5, stayPaint);
      canvas.drawCircle(stayPoint!, 10.5, stayBorder);
    }

    for (int i = 0; i < points.length; i++) {
      final ScheduleItem s = scheduleList[i] as ScheduleItem;
      final Offset pt = points[i] as Offset;

      final Paint shadowPaint = Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      final Paint circlePaint = Paint()..color = dayColor(s.day);
      final Paint borderPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(pt.translate(0, 1.5), 11.0, shadowPaint);
      canvas.drawCircle(pt, 11.0, circlePaint);
      canvas.drawCircle(pt, 11.0, borderPaint);

      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.0,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pt.dx - tp.width / 2, pt.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PosterMapPinPainter oldDelegate) => true;
}