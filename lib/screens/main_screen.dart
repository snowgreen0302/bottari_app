import 'package:flutter/material.dart';

import '../models/trip_model.dart';
import '../services/storage_service.dart';
import 'create_trip_screen.dart';
import 'trip_detail_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State createState() => _MainScreenState();
}

class _MainScreenState extends State {
  List _trips = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedTrips();
  }

  Future _loadSavedTrips() async {
    final List loaded = await StorageService.loadTrips();
    if (!mounted) return;
    setState(() {
      _trips = loaded;
      _isLoading = false;
    });
  }

  Future _editTripTitle(TripPlan trip) async {
    final TextEditingController controller = TextEditingController(
      text: trip.title,
    );

    final dynamic newTitleObj = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_outlined, color: Color(0xFF006B3E), size: 22),
            SizedBox(width: 8),
            Text('일정 이름 수정'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '새로운 일정 이름',
            hintText: '예: 부모님과 부산 효도 여행 보따리',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF006B3E),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    final String newTitle = newTitleObj?.toString().trim() ?? '';
    if (newTitle.isNotEmpty && newTitle != trip.title) {
      setState(() {
        trip.title = newTitle;
      });
      await StorageService.updateSingleTrip(trip);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('일정 이름이 변경되었습니다.'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future _confirmDeleteTrip(TripPlan trip) async {
    final dynamic confirmed = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('일정 삭제'),
        content: Text('"${trip.title}" 일정을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await StorageService.deleteTrip(trip.id);
      await _loadSavedTrips();
    }
  }

  String _formatDateRange(DateTime start, DateTime end) {
    final String s =
        '${start.month.toString().padLeft(2, '0')}.${start.day.toString().padLeft(2, '0')}';
    final String e =
        '${end.month.toString().padLeft(2, '0')}.${end.day.toString().padLeft(2, '0')}';
    return '$s ~ $e';
  }

  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF006B3E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '날씨와 테마를 읽고\n짐부터 일정까지 알아서 챙겨주는',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '나만의 스마트 여행 보따리',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF006B3E),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () async {
                final dynamic created = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateTripScreen()),
                );
                await _loadSavedTrips();
                if (created is TripPlan && mounted) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TripDetailScreen(trip: created),
                    ),
                  );
                  await _loadSavedTrips();
                }
              },
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: const Text(
                '새로운 일정 생성',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(dynamic rawTrip) {
    final TripPlan trip = rawTrip as TripPlan;
    final int total = trip.packingList.length;
    final int checked = trip.packingList.where((e) => e.isChecked).length;
    final int percent = (trip.packingProgress * 100).round();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TripDetailScreen(trip: trip)),
          );
          await _loadSavedTrips();
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF006B3E).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      trip.destination,
                      style: const TextStyle(
                        color: Color(0xFF006B3E),
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _formatDateRange(trip.startDate, trip.endDate),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '일정 이름 수정',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: Color(0xFF006B3E),
                      size: 20,
                    ),
                    onPressed: () => _editTripTitle(trip),
                  ),
                  IconButton(
                    tooltip: '일정 삭제',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    onPressed: () => _confirmDeleteTrip(trip),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                trip.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                trip.theme,
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.wb_sunny_outlined,
                    color: Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trip.weatherSummary,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '짐 싸기 달성률',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '$percent% ($checked/$total)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF006B3E),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: trip.packingProgress,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF006B3E)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.luggage_rounded, color: Color(0xFF006B3E), size: 22),
            SizedBox(width: 6),
            Text('보따리'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _buildHeroBanner(),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '현재 진행중인 일정 확인',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '총 ${_trips.length}개',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_trips.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.luggage_outlined,
                          size: 42,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '아직 생성된 여행 보따리가 없습니다.\n상단 버튼을 눌러 첫 여행을 준비해보세요!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._trips.map(_buildTripCard),
              ],
            ),
    );
  }
}
