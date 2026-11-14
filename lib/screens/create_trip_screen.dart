import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/trip_model.dart';
import '../services/ai_service.dart';
import '../services/storage_service.dart';
import '../services/weather_service.dart';

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State {
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _accommodationController =
      TextEditingController();
  final TextEditingController _themeController = TextEditingController();

  String _selectedCheckInOption = 'AI 자동 확인';
  final List _checkInOptions = [
    'AI 자동 확인',
    '14:00',
    '15:00',
    '16:00',
    '17:00',
    '18:00',
  ];

  DateTime _focusedDay = DateTime.now();
  DateTime? _rangeStart = DateTime.now().add(const Duration(days: 2));
  DateTime? _rangeEnd = DateTime.now().add(const Duration(days: 3));
  bool _isGenerating = false;

  final List _quickCities = ['부산', '제주', '강릉', '경주', '여수', '서울', '도쿄'];

  @override
  void dispose() {
    _destinationController.dispose();
    _accommodationController.dispose();
    _themeController.dispose();
    super.dispose();
  }

  Future _handleGenerateTrip() async {
    final String dest = _destinationController.text.trim();
    final String stay = _accommodationController.text.trim();
    final String theme = _themeController.text.trim();

    if (dest.isEmpty || stay.isEmpty || theme.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('목적지, 숙소, 여행 테마를 모두 입력해주세요.')),
      );
      return;
    }

    final DateTime start = _rangeStart ?? DateTime.now();
    final DateTime end = _rangeEnd ?? start;

    setState(() => _isGenerating = true);

    try {
      final String weatherSummary = await WeatherService.fetchWeatherSummary(
        dest,
        start,
      );

      final dynamic generated = await AiService.generateTripPackage(
        destination: dest,
        accommodation: stay,
        checkInTime: _selectedCheckInOption,
        startDate: start,
        endDate: end,
        theme: theme,
        weatherSummary: weatherSummary,
      );

      if (!mounted) return;

      if (generated['isError'] == true) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('안내'),
              ],
            ),
            content: Text(
              generated['errorMessage']?.toString() ??
                  '장난스럽거나 비현실적인 테마는 처리할 수 없습니다.\n실제 여행 테마를 다시 입력해 주세요.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        return;
      }

      if (generated['warningMessage'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(generated['warningMessage'].toString()),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      final int days = end.difference(start).inDays + 1;
      final String resolvedCheckIn =
          generated['resolvedCheckInTime']?.toString() ??
          (_selectedCheckInOption == 'AI 자동 확인'
              ? '15:00'
              : _selectedCheckInOption);

      final TripPlan newTrip = TripPlan(
        id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
        title: '$dest${days == 1 ? "당일치기" : "${days - 1}박 ${days}일"} 보따리',
        destination: dest,
        accommodation: stay,
        checkInTime: resolvedCheckIn,
        startDate: start,
        endDate: end,
        theme: theme,
        weatherSummary: weatherSummary,
        packingList: List.from(generated['packingList'] as List),
        scheduleList: List.from(generated['scheduleList'] as List),
      );

      await StorageService.updateSingleTrip(newTrip);

      if (!mounted) return;
      Navigator.pop(context, newTrip);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새로운 일정 생성')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. 어디로 떠나시나요?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _destinationController,
              decoration: InputDecoration(
                hintText: '목적지 입력 (예: 부산, 강릉, 제주)',
                prefixIcon: const Icon(
                  Icons.place_outlined,
                  color: Color(0xFF006B3E),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _quickCities.map((city) {
                return ActionChip(
                  label: Text(city.toString()),
                  onPressed: () {
                    setState(() {
                      _destinationController.text = city.toString();
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            const Text(
              '2. 숙소는 어디인가요? (동선 최적화 거점)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '숙소 이름과 체크인 시간을 확인하여 1일차 체크인 및 2일차 출발 동선을 짭니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _accommodationController,
              decoration: InputDecoration(
                hintText: '예: 해운대 신라스테이, 광안리 게스트하우스',
                prefixIcon: const Icon(
                  Icons.hotel_outlined,
                  color: Color(0xFF006B3E),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.access_time_filled_rounded,
                  size: 16,
                  color: Color(0xFF006B3E),
                ),
                const SizedBox(width: 6),
                Text(
                  '숙소 체크인 시간 선택',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _checkInOptions.map((opt) {
                final String label = opt.toString();
                final bool isSelected = _selectedCheckInOption == label;
                return ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  selectedColor: const Color(0xFF006B3E),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : const Color(0xFF1C1C1E),
                  ),
                  onSelected: (_) {
                    setState(() {
                      _selectedCheckInOption = label;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            const Text(
              '3. 여행 날짜 선택 (캘린더)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: TableCalendar(
                  firstDay: DateTime.now().subtract(const Duration(days: 30)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _focusedDay,
                  rangeStartDay: _rangeStart,
                  rangeEndDay: _rangeEnd,
                  rangeSelectionMode: RangeSelectionMode.toggledOn,
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                  calendarStyle: CalendarStyle(
                    rangeHighlightColor: const Color(0xFF006B3E)
                        .withOpacity(0.15),
                    rangeStartDecoration: const BoxDecoration(
                      color: Color(0xFF006B3E),
                      shape: BoxShape.circle,
                    ),
                    rangeEndDecoration: const BoxDecoration(
                      color: Color(0xFF006B3E),
                      shape: BoxShape.circle,
                    ),
                    todayDecoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
                  onRangeSelected: (start, end, focusedDay) {
                    setState(() {
                      _rangeStart = start;
                      _rangeEnd = end ?? start;
                      _focusedDay = focusedDay;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '4. 여행 테마 및 맥락 입력',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              '구체적인 맥락을 적으면 AI가 날씨·숙소·체크인 시간과 결합해 맞춤형 준비물과 동선을 도출합니다.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _themeController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '예: 친구들이랑 가는 뚜벅이 식도락 여행 / 부모님 모시고 가는 힐링 온천 여행',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF006B3E),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isGenerating ? null : _handleGenerateTrip,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _isGenerating
                      ? '숙소 체크인·영업시간 검증 및 AI 보따리 생성 중...'
                      : 'AI 맞춤 준비물 & 동선 생성하기',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
