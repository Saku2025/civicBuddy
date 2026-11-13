import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/survey_service.dart';
import '../services/upload_queue.dart';
import 'previous_surveys_screen.dart';

/// All submitted surveys on an OpenStreetMap: every survey point (and
/// citizen interview) as a blinking circle at its GPS position.
class SurveyMapScreen extends StatefulWidget {
  const SurveyMapScreen({super.key});

  @override
  State<SurveyMapScreen> createState() => _SurveyMapScreenState();
}

enum _Period { week, month, all }

enum _ColorBy { surveyor, cleanliness, survey, single }

enum _Kind { point, interview }

/// One circle on the map.
class _MapItem {
  _MapItem({
    required this.survey,
    required this.surveyIndex,
    required this.kind,
    required this.number,
    required this.position,
    required this.area,
    required this.date,
    required this.accuracy,
    required this.cleanliness,
    required this.firstPhotoPath,
    required this.details,
  });

  final Map<String, dynamic> survey;

  // Position of the survey in the loaded list (for per-survey colours).
  final int surveyIndex;

  final _Kind kind;

  final int number;

  final LatLng position;

  final String area;

  final DateTime? date;

  final double? accuracy;

  // "Very Clean" / "Mildly Dirty" / "Very Dirty", or null.
  final String? cleanliness;

  final String? firstPhotoPath;

  // Interview: "Occupation · Gender · Age".
  final String? details;

  String get surveyId => survey['survey_id']?.toString() ?? 'Survey';
}

class _SurveyMapScreenState extends State<SurveyMapScreen>
    with SingleTickerProviderStateMixin {
  // Default view (Kolkata) until points are loaded.
  static const LatLng _defaultCenter = LatLng(22.5726, 88.3639);

  static const Color _clean = Color(0xFF2E9E50);
  static const Color _mild = Color(0xFFF2B544);
  static const Color _dirty = Color(0xFFD93B30);
  static const Color _unrated = Color(0xFF8A9A90);
  static const Color _interviewColor = Color(0xFF2F6FDB);

  // "Color by surveyor": you are green, others get these in order.
  static const Color _myColor = Color(0xFF2E9E50);
  static const List<Color> _surveyorPalette = [
    Color(0xFF2F6FDB), // blue
    Color(0xFF8E44AD), // purple
    Color(0xFFE67E22), // orange
    Color(0xFFC2185B), // pink
    Color(0xFF0097A7), // teal
    Color(0xFF6D4C41), // brown
    Color(0xFFD93B30), // red
    Color(0xFF5C6BC0), // indigo
  ];

  // Distinct colours for "Color by survey".
  static const List<Color> _surveyPalette = [
    Color(0xFF256D3F),
    Color(0xFF2F6FDB),
    Color(0xFFD9534F),
    Color(0xFF8E44AD),
    Color(0xFFE67E22),
    Color(0xFF16A085),
    Color(0xFFC2185B),
    Color(0xFF6D4C41),
    Color(0xFF0097A7),
    Color(0xFF7CB342),
  ];

  final MapController _mapController = MapController();

  // One controller drives every blinking circle.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  bool _loading = true;

  bool _offline = false;

  String? _error;

  List<Map<String, dynamic>> _surveys = [];

  List<_MapItem> _items = [];

  _Period _period = _Period.all;

  // Only this surveyor's surveys (user id), or null for everyone.
  String? _userFilter;

  // "You", "Surveyor 1", "Surveyor 2"… by user id (other surveyors' names
  // and emails are not visible to the app).
  Map<String, String> _surveyorNames = {};

  _ColorBy _colorBy = _ColorBy.surveyor;

  bool _showInterviews = true;

  // Only this survey (its database id), or null for all.
  Object? _surveyFilter;

  late final String? _myUserId = AuthService.getCurrentUser()?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _offline = false;
      _error = null;
    });

    if (await UploadQueue.checkNetwork() == NetworkStatus.offline) {
      if (mounted) {
        setState(() {
          _loading = false;
          _offline = true;
        });
      }
      return;
    }

    try {
      final surveys = await SurveyService.getAllSurveys();
      if (!mounted) return;
      setState(() {
        _surveys = surveys;
        _items = _buildItems(surveys);
        _surveyorNames = _nameSurveyors(surveys);
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToVisible());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ------------------------------------------------------------
  // Data
  // ------------------------------------------------------------

  static List<Map<String, dynamic>> _maps(Object? list) => [
    if (list is List)
      for (final item in list)
        if (item is Map) Map<String, dynamic>.from(item),
  ];

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  static String? _cleanlinessOf(Map<String, dynamic> point) {
    final answers = point['surveyor_answers'];
    if (answers is! Map) return null;
    for (final entry in answers.entries) {
      if ('${entry.key}'.startsWith('Visual Cleanliness')) {
        return entry.value?.toString();
      }
    }
    return null;
  }

  List<_MapItem> _buildItems(List<Map<String, dynamic>> surveys) {
    final items = <_MapItem>[];

    for (final (index, survey) in surveys.indexed) {
      final data = survey['survey_data'] is Map
          ? Map<String, dynamic>.from(survey['survey_data'] as Map)
          : const <String, dynamic>{};

      for (final point in _maps(data['points'])) {
        final lat = _number(point['latitude']);
        final lng = _number(point['longitude']);
        if (lat == null || lng == null || (lat == 0 && lng == 0)) continue;

        final photos = _maps(point['photos']);
        items.add(
          _MapItem(
            survey: survey,
            surveyIndex: index,
            kind: _Kind.point,
            number: (point['point_number'] as num?)?.toInt() ?? 0,
            position: LatLng(lat, lng),
            area: point['area']?.toString() ?? '',
            date: DateTime.tryParse(point['captured_at']?.toString() ?? ''),
            accuracy: _number(point['accuracy_m']),
            cleanliness: _cleanlinessOf(point),
            firstPhotoPath: photos.isEmpty
                ? null
                : photos.first['storage_path']?.toString(),
            details: null,
          ),
        );
      }

      // App versions up to 1.7.4 saved a single interview.
      final citizens = data['citizens'] is List
          ? _maps(data['citizens'])
          : _maps([if (data['citizen'] != null) data['citizen']]);

      for (final (i, citizen) in citizens.indexed) {
        final lat = _number(citizen['latitude']);
        final lng = _number(citizen['longitude']);
        if (lat == null || lng == null || (lat == 0 && lng == 0)) continue;

        items.add(
          _MapItem(
            survey: survey,
            surveyIndex: index,
            kind: _Kind.interview,
            number: (citizen['interview_number'] as num?)?.toInt() ?? i + 1,
            position: LatLng(lat, lng),
            area: citizen['area']?.toString() ?? '',
            date: DateTime.tryParse(
              citizen['location_captured_at']?.toString() ?? '',
            ),
            accuracy: _number(citizen['accuracy_m']),
            cleanliness: null,
            firstPhotoPath: null,
            details: [
              citizen['occupation'],
              citizen['gender'],
              if (citizen['age'] != null) 'Age ${citizen['age']}',
            ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
          ),
        );
      }
    }
    return items;
  }

  /// "You" for the signed-in user; other accounts numbered by how many
  /// surveys they submitted (most first).
  Map<String, String> _nameSurveyors(List<Map<String, dynamic>> surveys) {
    final counts = <String, int>{};
    for (final survey in surveys) {
      final id = survey['user_id']?.toString() ?? '';
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final others = counts.keys.where((id) => id != _myUserId).toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return {
      if (_myUserId != null && counts.containsKey(_myUserId)) _myUserId: 'You',
      for (final (i, id) in others.indexed) id: 'Surveyor ${i + 1}',
    };
  }

  /// Green for you; "Surveyor N" gets the N-th palette colour.
  Color _surveyorColor(Object? userId) {
    if (userId != null && userId == _myUserId) return _myColor;
    final name = _surveyorNames[userId?.toString()] ?? '';
    final n = int.tryParse(name.replaceFirst('Surveyor ', '')) ?? 1;
    return _surveyorPalette[(n - 1) % _surveyorPalette.length];
  }

  String _surveyorName(Object? userId) =>
      _surveyorNames[userId?.toString()] ?? 'Surveyor';

  /// Surveys, points and interviews per surveyor, for the date filter.
  List<({String userId, int surveys, int points, int interviews})>
  _surveyorTotals() {
    final totals = <String, ({int surveys, int points, int interviews})>{};
    for (final survey in _surveys) {
      final userId = survey['user_id']?.toString() ?? '';
      if (!_inPeriod(survey)) continue;

      final items = _items.where((i) => identical(i.survey, survey));
      final points = items.where((i) => i.kind == _Kind.point).length;
      final current = totals[userId] ?? (surveys: 0, points: 0, interviews: 0);
      totals[userId] = (
        surveys: current.surveys + 1,
        points: current.points + points,
        interviews: current.interviews + items.length - points,
      );
    }
    final list = [
      for (final entry in totals.entries)
        (
          userId: entry.key,
          surveys: entry.value.surveys,
          points: entry.value.points,
          interviews: entry.value.interviews,
        ),
    ];
    // You first, then the others by number of surveys.
    list.sort((a, b) {
      if (a.userId == _myUserId) return -1;
      if (b.userId == _myUserId) return 1;
      return b.surveys.compareTo(a.surveys);
    });
    return list;
  }

  Future<void> _pickSurveyor() async {
    final totals = _surveyorTotals();
    final allSurveys = totals.fold<int>(0, (sum, t) => sum + t.surveys);

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Surveyors',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('Everyone'),
                subtitle: Text(
                  '$allSurveys surveys from ${totals.length} '
                  'surveyor${totals.length == 1 ? '' : 's'}',
                ),
                selected: _userFilter == null,
                onTap: () => Navigator.pop(sheetContext, ''),
              ),
              for (final t in totals)
                ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: _surveyorColor(t.userId),
                    child: Icon(
                      t.userId == _myUserId
                          ? Icons.person
                          : Icons.person_outline,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(_surveyorName(t.userId)),
                  subtitle: Text(
                    '${t.surveys} survey${t.surveys == 1 ? '' : 's'} · '
                    '${t.points} points · ${t.interviews} interviews',
                  ),
                  trailing: Text(
                    '${t.surveys}',
                    style: Theme.of(sheetContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  selected: _userFilter == t.userId,
                  onTap: () => Navigator.pop(sheetContext, t.userId),
                ),
            ],
          ),
        ),
      ),
    );

    if (picked == null) return;
    _changeFilters(() => _userFilter = picked.isEmpty ? null : picked);
  }

  DateTime? _surveyDate(Map<String, dynamic> survey) => DateTime.tryParse(
    (survey['ended_at'] ?? survey['created_at'])?.toString() ?? '',
  );

  bool _inPeriod(Map<String, dynamic> survey) {
    if (_period == _Period.all) return true;
    final date = _surveyDate(survey);
    final days = _period == _Period.week ? 7 : 30;
    return date != null &&
        !date.isBefore(DateTime.now().subtract(Duration(days: days)));
  }

  bool _surveyMatches(Map<String, dynamic> survey) =>
      (_userFilter == null || survey['user_id'] == _userFilter) &&
      _inPeriod(survey);

  List<_MapItem> get _visibleItems => [
    for (final item in _items)
      if (_surveyMatches(item.survey) &&
          (_surveyFilter == null || item.survey['id'] == _surveyFilter) &&
          (_showInterviews || item.kind == _Kind.point))
        item,
  ];

  Color _colorOf(_MapItem item) {
    // Interviews keep the surveyor's / survey's colour (square shape tells
    // them apart); in the other modes they are blue.
    if (item.kind == _Kind.interview &&
        _colorBy != _ColorBy.survey &&
        _colorBy != _ColorBy.surveyor) {
      return _interviewColor;
    }
    switch (_colorBy) {
      case _ColorBy.surveyor:
        return _surveyorColor(item.survey['user_id']);
      case _ColorBy.single:
        return Theme.of(context).colorScheme.primary;
      case _ColorBy.survey:
        return _surveyPalette[item.surveyIndex % _surveyPalette.length];
      case _ColorBy.cleanliness:
        return switch (item.cleanliness?.toLowerCase()) {
          'very clean' => _clean,
          'mildly dirty' => _mild,
          'very dirty' => _dirty,
          _ => _unrated,
        };
    }
  }

  void _fitToVisible() {
    final points = _visibleItems.map((i) => i.position).toList();
    if (points.isEmpty) return;
    try {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(48, 140, 48, 120),
          maxZoom: 16,
        ),
      );
    } catch (_) {
      // Map not laid out yet; the next filter change fits it.
    }
  }

  void _changeFilters(VoidCallback change) {
    setState(change);
    // A survey that no longer matches the date / who filter is cleared.
    if (_surveyFilter != null &&
        !_surveys.any((s) => s['id'] == _surveyFilter && _surveyMatches(s))) {
      setState(() => _surveyFilter = null);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToVisible());
  }

  // ------------------------------------------------------------
  // Tapping a circle
  // ------------------------------------------------------------

  String _dateText(DateTime? date) {
    if (date == null) return '—';
    final d = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}  '
        '${two(d.hour)}:${two(d.minute)}';
  }

  void _showItem(_MapItem item) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        final isPoint = item.kind == _Kind.point;
        final mine = item.survey['user_id'] == _myUserId;

        Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MarkerShape(
                      color: _colorOf(item),
                      isInterview: !isPoint,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isPoint
                            ? 'Point ${item.number}'
                            : 'Citizen interview ${item.number}',
                        style: Theme.of(sheetContext).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (mine)
                      Chip(
                        label: const Text('Yours'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: colors.primaryContainer,
                        side: BorderSide.none,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          line(Icons.tag, item.surveyId),
                          line(
                            Icons.person_outline,
                            'By ${_surveyorName(item.survey['user_id'])}',
                          ),
                          line(
                            Icons.place_outlined,
                            item.area.isEmpty ? 'Unknown Area' : item.area,
                          ),
                          line(Icons.schedule, _dateText(item.date)),
                          line(
                            Icons.gps_fixed,
                            item.accuracy == null
                                ? 'GPS accuracy: not recorded'
                                : 'GPS accuracy: ±${item.accuracy!.round()} m',
                          ),
                          if (item.cleanliness != null)
                            line(
                              Icons.cleaning_services_outlined,
                              'Cleanliness: ${item.cleanliness}',
                            ),
                          if (item.details != null && item.details!.isNotEmpty)
                            line(Icons.person_outline, item.details!),
                        ],
                      ),
                    ),
                    if (item.firstPhotoPath != null) ...[
                      const SizedBox(width: 12),
                      _FirstPhoto(path: item.firstPhotoPath!),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SurveyDetailsScreen(survey: item.survey),
                        ),
                      );
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open survey'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // Filters
  // ------------------------------------------------------------

  Future<void> _pickSurvey() async {
    final choices = _surveys.where(_surveyMatches).toList();

    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('All surveys'),
                selected: _surveyFilter == null,
                onTap: () => Navigator.pop(sheetContext, 'all'),
              ),
              for (final survey in choices)
                ListTile(
                  leading: CircleAvatar(
                    radius: 8,
                    backgroundColor:
                        _surveyPalette[_surveys.indexOf(survey) %
                            _surveyPalette.length],
                  ),
                  title: Text(survey['survey_id']?.toString() ?? 'Survey'),
                  subtitle: Text(
                    '${_dateText(_surveyDate(survey))}'
                    ' · ${_surveyorName(survey['user_id'])}',
                  ),
                  selected: _surveyFilter == survey['id'],
                  onTap: () => Navigator.pop(sheetContext, survey['id']),
                ),
            ],
          ),
        ),
      ),
    );

    if (picked == null) return;
    _changeFilters(() => _surveyFilter = picked == 'all' ? null : picked);
  }

  Widget _filterBar(ColorScheme colors) {
    Widget choice<T>(String label, T value, T group, ValueChanged<T> onTap) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label),
            selected: value == group,
            onSelected: (_) => onTap(value),
            visualDensity: VisualDensity.compact,
          ),
        );

    Widget divider() => Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: colors.outlineVariant,
    );

    String surveyLabel() {
      if (_surveyFilter == null) return 'All surveys';
      final survey = _surveys.firstWhere(
        (s) => s['id'] == _surveyFilter,
        orElse: () => const {},
      );
      return survey['survey_id']?.toString() ?? 'Survey';
    }

    return Material(
      color: colors.surface.withValues(alpha: 0.95),
      elevation: 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            choice(
              '7 days',
              _Period.week,
              _period,
              (v) => _changeFilters(() => _period = v),
            ),
            choice(
              '30 days',
              _Period.month,
              _period,
              (v) => _changeFilters(() => _period = v),
            ),
            choice(
              'All time',
              _Period.all,
              _period,
              (v) => _changeFilters(() => _period = v),
            ),
            divider(),
            choice<String?>(
              'Everyone',
              null,
              _userFilter,
              (v) => _changeFilters(() => _userFilter = v),
            ),
            choice<String?>(
              'Mine',
              _myUserId,
              _userFilter,
              (v) => _changeFilters(() => _userFilter = v),
            ),
            ActionChip(
              avatar: const Icon(Icons.groups_outlined, size: 18),
              label: Text(
                _userFilter != null && _userFilter != _myUserId
                    ? _surveyorName(_userFilter)
                    : 'Surveyors (${_surveyorNames.length})',
              ),
              onPressed: _pickSurveyor,
              visualDensity: VisualDensity.compact,
            ),
            divider(),
            ActionChip(
              avatar: const Icon(Icons.layers_outlined, size: 18),
              label: Text(surveyLabel()),
              onPressed: _pickSurvey,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            FilterChip(
              avatar: const Icon(Icons.person_pin_circle_outlined, size: 18),
              label: const Text('Interviews'),
              selected: _showInterviews,
              onSelected: (v) => _changeFilters(() => _showInterviews = v),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(ColorScheme colors, List<_MapItem> visible) {
    Widget row(Color color, String label, {bool interview = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MarkerShape(color: color, isInterview: interview, size: 14),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );

    final points = visible.where((i) => i.kind == _Kind.point).length;
    final interviews = visible.length - points;
    final surveys = visible.map((i) => i.survey['id']).toSet().length;
    final surveyors = visible.map((i) => i.survey['user_id']).toSet().length;

    return Card(
      elevation: 3,
      margin: EdgeInsets.zero,
      color: colors.surface.withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$surveys surveys · $surveyors surveyor'
              '${surveyors == 1 ? '' : 's'}\n'
              '$points points · $interviews interviews',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 6),
            if (_colorBy == _ColorBy.surveyor) ...[
              for (final userId
                  in visible.map((i) => i.survey['user_id']).toSet().toList()
                    ..sort(
                      (a, b) => _surveyorName(a) == 'You'
                          ? -1
                          : _surveyorName(b) == 'You'
                          ? 1
                          : _surveyorName(a).compareTo(_surveyorName(b)),
                    ))
                row(_surveyorColor(userId), _surveyorName(userId)),
              if (_showInterviews)
                row(
                  colors.onSurfaceVariant,
                  'Square = citizen interview',
                  interview: true,
                ),
            ] else if (_colorBy == _ColorBy.cleanliness) ...[
              row(_clean, 'Very clean'),
              row(_mild, 'Mildly dirty'),
              row(_dirty, 'Very dirty'),
              row(_unrated, 'Not rated'),
            ] else if (_colorBy == _ColorBy.survey)
              row(_surveyPalette[0], 'One colour per survey')
            else
              row(colors.primary, 'Survey point'),
            if (_showInterviews &&
                _colorBy != _ColorBy.survey &&
                _colorBy != _ColorBy.surveyor)
              row(_interviewColor, 'Citizen interview', interview: true),
            if (_showInterviews && _colorBy == _ColorBy.survey)
              row(_surveyPalette[0], 'Citizen interview', interview: true),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // Build
  // ------------------------------------------------------------

  Widget _message({
    required IconData icon,
    required String title,
    required String text,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colors.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Survey Map'),
        actions: [
          PopupMenuButton<_ColorBy>(
            tooltip: 'Color by',
            icon: const Icon(Icons.palette_outlined),
            initialValue: _colorBy,
            onSelected: (v) => setState(() => _colorBy = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ColorBy.surveyor,
                child: Text('Color by surveyor'),
              ),
              PopupMenuItem(
                value: _ColorBy.cleanliness,
                child: Text('Color by cleanliness'),
              ),
              PopupMenuItem(
                value: _ColorBy.survey,
                child: Text('Color by survey'),
              ),
              PopupMenuItem(
                value: _ColorBy.single,
                child: Text('Single color'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _offline
          ? _message(
              icon: Icons.cloud_off_outlined,
              title: 'Map needs internet',
              text:
                  'Connect to Wi-Fi or mobile data to load the map and the '
                  'surveys.',
            )
          : _error != null
          ? _message(
              icon: Icons.error_outline,
              title: 'Could not load surveys',
              text: _error!,
            )
          : _buildMap(colors),
    );
  }

  Widget _buildMap(ColorScheme colors) {
    final visible = _visibleItems;
    final byKey = <Key, _MapItem>{};

    // Marker keys map taps back to their point or interview.
    final markers = <Marker>[];
    for (final (i, item) in visible.indexed) {
      final key = ValueKey('marker-$i');
      byKey[key] = item;
      markers.add(
        Marker(
          key: key,
          point: item.position,
          width: 44,
          height: 44,
          child: _PulsingMarker(
            animation: _pulse,
            color: _colorOf(item),
            isInterview: item.kind == _Kind.interview,
          ),
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: visible.isEmpty
                ? _defaultCenter
                : visible.first.position,
            initialZoom: 12,
            minZoom: 3,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.civicbuddy.app',
              maxNativeZoom: 19,
            ),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                markers: markers,
                maxClusterRadius: 45,
                size: const Size(44, 44),
                padding: const EdgeInsets.all(60),
                maxZoom: 17,
                showPolygon: false,
                onMarkerTap: (marker) {
                  final item = byKey[marker.key];
                  if (item != null) _showItem(item);
                },
                builder: (context, clustered) => Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // The markers' colour if they all share one (e.g. all
                    // from one surveyor), otherwise the app colour.
                    color: () {
                      final shades = {
                        for (final m in clustered)
                          if (byKey[m.key] case final item?) _colorOf(item),
                      };
                      return shades.length == 1 ? shades.first : colors.primary;
                    }(),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(blurRadius: 6, color: Colors.black26),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${clustered.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomRight,
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                  onTap: () => launchUrl(
                    Uri.parse('https://openstreetmap.org/copyright'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(top: 0, left: 0, right: 0, child: _filterBar(colors)),
        Positioned(left: 12, bottom: 12, child: _legend(colors, visible)),
        if (visible.isEmpty)
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  _items.isEmpty
                      ? 'No surveys with GPS points yet.'
                      : 'No points match these filters.',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A circle (survey point) or rounded square with a person (interview).
class _MarkerShape extends StatelessWidget {
  const _MarkerShape({
    required this.color,
    required this.isInterview,
    required this.size,
  });

  final Color color;

  final bool isInterview;

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: isInterview ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isInterview ? BorderRadius.circular(size * 0.28) : null,
        border: Border.all(color: Colors.white, width: size > 16 ? 2.5 : 1.5),
        boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black26)],
      ),
      child: isInterview
          ? Icon(Icons.person, size: size * 0.7, color: Colors.white)
          : null,
    );
  }
}

/// Blinking marker: a solid shape with a ring that grows and fades.
class _PulsingMarker extends StatelessWidget {
  const _PulsingMarker({
    required this.animation,
    required this.color,
    required this.isInterview,
  });

  final Animation<double> animation;

  final Color color;

  final bool isInterview;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 16 + 28 * t,
              height: 16 + 28 * t,
              decoration: BoxDecoration(
                shape: isInterview ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: isInterview ? BorderRadius.circular(10) : null,
                color: color.withValues(alpha: 0.45 * (1 - t)),
              ),
            ),
            child!,
          ],
        );
      },
      child: _MarkerShape(color: color, isInterview: isInterview, size: 18),
    );
  }
}

/// First photo of a point, loaded through a short-lived signed URL.
class _FirstPhoto extends StatelessWidget {
  const _FirstPhoto({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 110,
        height: 110,
        child: FutureBuilder<String>(
          future: Supabase.instance.client.storage
              .from(SurveyService.photoBucket)
              .createSignedUrl(path, 3600),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ColoredBox(
                color: colors.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              );
            }
            if (!snapshot.hasData) {
              return ColoredBox(
                color: colors.surfaceContainerHighest,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return Image.network(
              snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(
                color: colors.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
            );
          },
        ),
      ),
    );
  }
}
