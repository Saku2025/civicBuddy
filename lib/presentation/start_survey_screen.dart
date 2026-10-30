import 'dart:io';

import 'package:camera/camera.dart';

import 'package:flutter/material.dart';

import '../services/location_service.dart';
import '../services/survey_service.dart';

import 'camera_screen.dart';

class StartSurveyScreen extends StatefulWidget {
  const StartSurveyScreen({super.key});

  @override
  State<StartSurveyScreen> createState() {
    return _StartSurveyScreenState();
  }
}

class CitizenInterviewResult {
  final String occupation;

  final String gender;

  final int age;

  final Map<int, String> answers;

  // Where the interview took place.
  final double latitude;

  final double longitude;

  final String area;

  final DateTime locationCapturedAt;

  const CitizenInterviewResult({
    required this.occupation,

    required this.gender,

    required this.age,

    required this.answers,

    required this.latitude,

    required this.longitude,

    required this.area,

    required this.locationCapturedAt,
  });
}

class _SurveyPoint {
  _SurveyPoint({
    required this.number,

    required this.capturedAt,

    required this.latitude,

    required this.longitude,

    required this.area,
  });

  int number;

  final DateTime capturedAt;

  final double latitude;

  final double longitude;

  final String area;

  final List<XFile> photos = [];

  final Map<int, String> answers = {};
}

class _StartSurveyScreenState extends State<StartSurveyScreen> {
  final LocationService _locationService = LocationService();

  static const int _maxPhotosPerPoint = 10;

  final List<_SurveyPoint> _points = [];

  // Citizen interviews in the order they were taken.
  final List<CitizenInterviewResult> _interviews = [];

  late final DateTime _startedAt = DateTime.now();

  late final String _surveyId = 'SUR-${_startedAt.microsecondsSinceEpoch}';

  bool _isAddingPoint = false;

  bool _isSavingSurvey = false;

  bool _surveyEnded = false;

  static const List<Map<String, dynamic>> _surveyorQuestions = [
    {
      'question':
          'Visual Cleanliness: Based on the captured photo, how would you rate the cleanliness of this specific spot? Are there visible garbage heaps or betel leaf (paan) stains? '
          '(দৃশ্যমান পরিচ্ছন্নতা: তোলা ছবির ভিত্তিতে এই নির্দিষ্ট জায়গাটির পরিচ্ছন্নতা আপনি কেমন মূল্যায়ন করবেন? এখানে কি আবর্জনার স্তূপ বা পানের পিকের দাগ দেখা যাচ্ছে?)',

      'options': ['Very Clean', 'Mildly Dirty', 'Very Dirty'],
    },

    {
      'question':
          'Type of Waste: What is the primary type of garbage dumped here? '
          '(বর্জ্যের ধরন: এখানে প্রধানত কোন ধরনের আবর্জনা ফেলা হয়েছে?)',

      'options': ['Plastic waste', 'Organic/Food', 'Clean'],
    },

    {
      'question':
          'Odor Intensity: How strong is the foul smell in this immediate area? '
          '(দুর্গন্ধের তীব্রতা: এই জায়গার আশেপাশে দুর্গন্ধ কতটা তীব্র?)',

      'options': ['Mild', 'Unbearable', 'No Smell'],
    },

    {
      'question':
          'Road Blockage: Is the dumped garbage spilling over onto the main road or walking path? '
          '(রাস্তা অবরোধ: ফেলে রাখা আবর্জনা কি মূল রাস্তা বা হাঁটার পথে ছড়িয়ে পড়ছে?)',

      'options': ['Yes', 'No'],
    },

    {
      'question':
          'Dustbin Status: Is there a designated public dustbin available, and what is its condition? '
          '(ডাস্টবিনের অবস্থা: এখানে কি নির্দিষ্ট সরকারি ডাস্টবিন আছে, এবং সেটির অবস্থা কেমন?)',

      'options': [
        'Not Available',

        'Available & Clean',

        'Available but Overflowing/Broken',
      ],
    },
  ];

  static const List<Map<String, dynamic>> _citizenQuestions = [
    {
      'question':
          'Dirtiness Frequency: How often does this spot get noticeably dirty with garbage? '
          '(নোংরা হওয়ার হার: এই জায়গাটি কত ঘন ঘন আবর্জনায় স্পষ্টভাবে নোংরা হয়ে যায়?)',

      'options': ['Daily', 'Several times a week', 'Weekly', 'Rarely'],
    },

    {
      'question':
          'Sweeper Regularity: Do the municipal sweepers come to collect the garbage regularly? '
          '(সাফাইকর্মীদের নিয়মিততা: পৌরসভার সাফাইকর্মীরা কি নিয়মিত আবর্জনা সংগ্রহ করতে আসেন?)',

      'options': ['Yes', 'No'],
    },

    {
      'question':
          'Source of Garbage: In your observation, where does most of this garbage come from? '
          '(আবর্জনার উৎস: আপনার পর্যবেক্ষণে, এই আবর্জনার বেশিরভাগ কোথা থেকে আসে?)',

      'options': ['Households', 'Local Market', 'Shops', 'Outsiders'],
    },

    {
      'question':
          'Complaint Resolution: If residents report an open garbage dump to the local authorities, do they take action to clear it? '
          '(অভিযোগের সমাধান: বাসিন্দারা খোলা আবর্জনার স্তূপের কথা স্থানীয় কর্তৃপক্ষকে জানালে, তারা কি তা পরিষ্কার করার ব্যবস্থা নেয়?)',

      'options': ['Always', 'Sometimes', 'Never', 'Unaware'],
    },

    {
      'question':
          'CCTV Intervention: Do you think installing CCTV cameras would stop people from littering in this spot? '
          '(সিসিটিভি নজরদারি: আপনার কি মনে হয় সিসিটিভি ক্যামেরা বসালে মানুষ এই জায়গায় আবর্জনা ফেলা বন্ধ করবে?)',

      'options': ['Yes', 'No'],
    },

    {
      'question':
          "Municipal Rating: How would you rate the local municipality's overall efficiency in handling public hygiene? "
          '(পৌরসভার মূল্যায়ন: জনস্বাস্থ্য ও পরিচ্ছন্নতা রক্ষায় স্থানীয় পৌরসভার সামগ্রিক দক্ষতাকে আপনি কেমন মূল্যায়ন করবেন?)',

      'options': ['Good', 'Average', 'Poor'],
    },

    {
      'question':
          'Community Participation: Would you be willing to actively participate in a community cleanliness drive for your neighborhood? '
          '(সামাজিক অংশগ্রহণ: আপনি কি আপনার এলাকার পরিচ্ছন্নতা অভিযানে সক্রিয়ভাবে অংশ নিতে ইচ্ছুক?)',

      'options': ['Yes', 'No'],
    },
  ];

  String _formatDateTime(DateTime dateTime) {
    final d = dateTime.toLocal();

    String two(int n) => n.toString().padLeft(2, '0');

    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  Future<void> _addPoint() async {
    if (_isAddingPoint || _surveyEnded) return;

    setState(() => _isAddingPoint = true);

    try {
      final position = await _locationService.getCurrentLocation();

      final area = await _locationService.getAreaName(
        latitude: position.latitude,

        longitude: position.longitude,
      );

      if (!mounted) return;

      setState(() {
        _points.add(
          _SurveyPoint(
            number: _points.length + 1,

            capturedAt: DateTime.now(),

            latitude: position.latitude,

            longitude: position.longitude,

            area: area,
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingPoint = false);
    }
  }

  Future<void> _addPhoto(_SurveyPoint point) async {
    if (_surveyEnded) return;

    if (point.photos.length >= _maxPhotosPerPoint) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Maximum $_maxPhotosPerPoint photos allowed per point.',
          ),
        ),
      );

      return;
    }

    final image = await Navigator.push<XFile>(
      context,

      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );

    if (!mounted || image == null) return;

    setState(() => point.photos.add(image));
  }

  Future<void> _removePoint(_SurveyPoint point) async {
    if (_surveyEnded) return;

    final confirmed = await showDialog<bool>(
      context: context,

      builder: (ctx) => AlertDialog(
        title: Text('Remove Point ${point.number}?'),

        content: const Text(
          'This removes the point from the current survey session.',
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),

            child: const Text('Cancel'),
          ),

          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),

            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _points.remove(point);

      for (var i = 0; i < _points.length; i++) {
        _points[i].number = i + 1;
      }
    });
  }

  Future<void> _showSurveyorQuestionnaire(_SurveyPoint point) async {
    final result = await Navigator.push<Map<int, String>>(
      context,

      MaterialPageRoute(
        builder: (_) => _QuestionnaireScreen(
          title: 'Point ${point.number} Questionnaire',

          subtitle: 'Surveyor observations',

          questions: _surveyorQuestions,

          initialAnswers: point.answers,
        ),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      point.answers
        ..clear()
        ..addAll(result);
    });
  }

  /// Adds a new interview, or edits the one at [index].
  Future<void> _showCitizenInterview({int? index}) async {
    if (_surveyEnded) return;

    final existing = index == null ? null : _interviews[index];
    final number = (index ?? _interviews.length) + 1;

    final result = await Navigator.push<CitizenInterviewResult>(
      context,

      MaterialPageRoute(
        builder: (_) => _QuestionnaireScreen(
          title: 'Citizen Interview $number',

          subtitle: 'Citizen details and interview questions',

          questions: _citizenQuestions,

          initialAnswers: existing?.answers ?? const <int, String>{},

          showDemographics: true,

          initialOccupation: existing?.occupation ?? '',

          initialGender: existing?.gender ?? '',

          initialAge: existing?.age,

          initialInterview: existing,
        ),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      if (index == null) {
        _interviews.add(result);
      } else {
        _interviews[index] = result;
      }
    });
  }

  Future<void> _removeInterview(int index) async {
    if (_surveyEnded) return;

    final confirmed = await showDialog<bool>(
      context: context,

      builder: (ctx) => AlertDialog(
        title: Text('Remove Interview ${index + 1}?'),

        content: const Text(
          'This removes the interview from the current survey session.',
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),

            child: const Text('Cancel'),
          ),

          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),

            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _interviews.removeAt(index));
  }

  Future<void> _endSurvey() async {
    if (_surveyEnded) return;

    if (_points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one survey point first.')),
      );

      return;
    }

    final incomplete = _points
        .where((p) => p.answers.length != _surveyorQuestions.length)
        .toList();

    if (incomplete.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete the surveyor questionnaire for Point ${incomplete.first.number}.',
          ),
        ),
      );

      return;
    }

    // Each saved interview is complete (the questionnaire enforces it); at
    // least one is required.
    if (_interviews.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one citizen interview before ending.'),
        ),
      );

      await _showCitizenInterview();

      if (!mounted) return;

      if (_interviews.isEmpty) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit survey?'),
        content: Text(
          'Submit ${_points.length} point(s), ${_interviews.length} citizen '
          'interview(s) and all questionnaire answers to Supabase?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continue editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit Survey'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSavingSurvey = true);
    try {
      final pointDocuments = <Map<String, dynamic>>[];

      for (final point in _points) {
        final uploadedPhotos = <Map<String, dynamic>>[];
        for (var i = 0; i < point.photos.length; i++) {
          final photo = point.photos[i];
          final storagePath = await SurveyService.uploadPhoto(
            surveyId: _surveyId,
            pointNumber: point.number,
            photoFile: File(photo.path),
            photoIndex: i + 1,
          );
          uploadedPhotos.add({
            'storage_path': storagePath,
            'photo_number': i + 1,
          });
        }

        pointDocuments.add({
          'point_number': point.number,
          'latitude': point.latitude,
          'longitude': point.longitude,
          'area': point.area,
          'captured_at': point.capturedAt.toUtc().toIso8601String(),
          'photos': uploadedPhotos,
          'surveyor_answers': {
            for (var i = 0; i < _surveyorQuestions.length; i++)
              _surveyorQuestions[i]['question'] as String: point.answers[i],
          },
        });
      }

      final citizenDocuments = <Map<String, dynamic>>[
        for (var n = 0; n < _interviews.length; n++)
          {
            'interview_number': n + 1,
            'occupation': _interviews[n].occupation,
            'gender': _interviews[n].gender,
            'age': _interviews[n].age,
            'latitude': _interviews[n].latitude,
            'longitude': _interviews[n].longitude,
            'area': _interviews[n].area,
            'location_captured_at': _interviews[n].locationCapturedAt
                .toUtc()
                .toIso8601String(),
            'answers': {
              for (var i = 0; i < _citizenQuestions.length; i++)
                _citizenQuestions[i]['question'] as String:
                    _interviews[n].answers[i],
            },
          },
      ];

      await SurveyService.saveSurvey(
        surveyId: _surveyId,
        startedAt: _startedAt,
        endedAt: DateTime.now(),
        surveyData: {
          'points': pointDocuments,
          'citizens': citizenDocuments,
          // Single-interview field read by app versions up to 1.7.4.
          'citizen': citizenDocuments.first,
        },
      );

      if (!mounted) return;
      setState(() => _surveyEnded = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Survey submitted successfully to Supabase.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Survey submission failed: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingSurvey = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Start Survey')),

      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),

                children: [
                  Container(
                    padding: const EdgeInsets.all(18),

                    decoration: BoxDecoration(
                      color: colors.primaryContainer,

                      borderRadius: BorderRadius.circular(18),
                    ),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        Icon(
                          Icons.assignment_outlined,

                          color: colors.primary,

                          size: 32,
                        ),

                        const SizedBox(height: 10),

                        Text(
                          'Survey ID',

                          style: TextStyle(color: colors.onPrimaryContainer),
                        ),

                        SelectableText(
                          _surveyId,

                          style: TextStyle(
                            fontSize: 20,

                            fontWeight: FontWeight.bold,

                            color: colors.onPrimaryContainer,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          'Started: ${_formatDateTime(_startedAt)}',

                          style: TextStyle(color: colors.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Survey Points (${_points.length})',

                          style: const TextStyle(
                            fontSize: 20,

                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      if (!_surveyEnded)
                        FilledButton.icon(
                          onPressed: _isAddingPoint ? null : _addPoint,

                          icon: _isAddingPoint
                              ? const SizedBox(
                                  width: 16,

                                  height: 16,

                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_location_alt_outlined),

                          label: const Text('Add Point'),
                        ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Each point records GPS, timestamp, up to $_maxPhotosPerPoint photos, and a 5-question surveyor questionnaire.',

                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),

                  const SizedBox(height: 12),

                  if (_points.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),

                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outlineVariant),

                        borderRadius: BorderRadius.circular(16),
                      ),

                      child: const Column(
                        children: [
                          Icon(Icons.add_location_alt_outlined, size: 40),

                          SizedBox(height: 8),

                          Text(
                            'No points yet',

                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),

                          Text(
                            'Tap Add Point to record your current GPS location.',

                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                  // Newest point first, so a just-added point appears at the top.
                  ..._points.reversed.map(
                    (point) => Card(
                      margin: const EdgeInsets.only(bottom: 12),

                      elevation: 0,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),

                        side: BorderSide(color: colors.outlineVariant),
                      ),

                      child: Padding(
                        padding: const EdgeInsets.all(14),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Row(
                              children: [
                                CircleAvatar(child: Text('${point.number}')),

                                const SizedBox(width: 10),

                                Expanded(
                                  child: Text(
                                    'Point ${point.number}',

                                    style: const TextStyle(
                                      fontSize: 18,

                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),

                                if (!_surveyEnded)
                                  IconButton(
                                    onPressed: () => _removePoint(point),

                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),

                            Text('Area: ${point.area}'),

                            Text(
                              'Latitude: ${point.latitude.toStringAsFixed(6)}',
                            ),

                            Text(
                              'Longitude: ${point.longitude.toStringAsFixed(6)}',
                            ),

                            Text(
                              'Timestamp: ${_formatDateTime(point.capturedAt)}',
                            ),

                            const SizedBox(height: 8),

                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Photos: ${point.photos.length}/$_maxPhotosPerPoint',
                                  ),
                                ),

                                if (!_surveyEnded)
                                  OutlinedButton.icon(
                                    onPressed:
                                        point.photos.length >=
                                            _maxPhotosPerPoint
                                        ? null
                                        : () => _addPhoto(point),

                                    icon: const Icon(Icons.camera_alt_outlined),

                                    label: const Text('Add Photo'),
                                  ),
                              ],
                            ),

                            if (point.photos.isNotEmpty) ...[
                              const SizedBox(height: 8),

                              SizedBox(
                                height: 82,

                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,

                                  itemCount: point.photos.length,

                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 8),

                                  itemBuilder: (_, i) => ClipRRect(
                                    borderRadius: BorderRadius.circular(8),

                                    child: Image.file(
                                      File(point.photos[i].path),

                                      width: 82,

                                      height: 82,

                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 10),

                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Surveyor answers: ${point.answers.length}/${_surveyorQuestions.length}',

                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,

                                      color:
                                          point.answers.length ==
                                              _surveyorQuestions.length
                                          ? colors.primary
                                          : colors.onSurface,
                                    ),
                                  ),
                                ),

                                OutlinedButton(
                                  onPressed: _surveyEnded
                                      ? null
                                      : () => _showSurveyorQuestionnaire(point),

                                  child: Text(
                                    point.answers.length ==
                                            _surveyorQuestions.length
                                        ? 'Edit Answers'
                                        : 'Questionnaire',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Interviews (${_interviews.length})',

                          style: const TextStyle(
                            fontSize: 20,

                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      if (!_surveyEnded)
                        FilledButton.icon(
                          onPressed: () => _showCitizenInterview(),

                          icon: const Icon(Icons.person_add_alt_1_outlined),

                          label: const Text('Add Interview'),
                        ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Interview as many citizens as you like. Each records occupation, gender, age and ${_citizenQuestions.length} answers.',

                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),

                  const SizedBox(height: 12),

                  if (_interviews.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),

                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outlineVariant),

                        borderRadius: BorderRadius.circular(16),
                      ),

                      child: const Column(
                        children: [
                          Icon(Icons.record_voice_over_outlined, size: 40),

                          SizedBox(height: 8),

                          Text(
                            'No interviews yet',

                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),

                          Text(
                            'Tap Add Interview to interview a citizen.',

                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                  // Newest interview first, like the survey points.
                  for (var i = _interviews.length - 1; i >= 0; i--)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),

                      elevation: 0,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),

                        side: BorderSide(color: colors.outlineVariant),
                      ),

                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),

                        leading: CircleAvatar(
                          backgroundColor: colors.primaryContainer,

                          child: Text('${i + 1}'),
                        ),

                        title: Text(
                          'Interview ${i + 1}',

                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),

                        subtitle: Text(
                          '${_interviews[i].occupation} · ${_interviews[i].gender} · Age\u00A0${_interviews[i].age}\n'
                          '${_interviews[i].area}\n'
                          'Answers: ${_interviews[i].answers.length}/${_citizenQuestions.length}',
                        ),

                        isThreeLine: true,

                        trailing: _surveyEnded
                            ? null
                            : IconButton(
                                tooltip: 'Remove interview',

                                onPressed: () => _removeInterview(i),

                                icon: const Icon(Icons.delete_outline),
                              ),

                        onTap: _surveyEnded
                            ? null
                            : () => _showCitizenInterview(index: i),
                      ),
                    ),

                  const SizedBox(height: 10),

                  Text(
                    'Note: the questions are starter examples. Confirm the exact questions and answer options with your supervisor.',

                    style: TextStyle(
                      fontSize: 12,

                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),

              child: SizedBox(
                width: double.infinity,

                height: 50,

                child: FilledButton.icon(
                  onPressed: (_surveyEnded || _isSavingSurvey)
                      ? null
                      : _endSurvey,

                  icon: Icon(
                    _surveyEnded
                        ? Icons.check_circle_outline
                        : Icons.stop_circle_outlined,
                  ),

                  label: Text(
                    _surveyEnded ? 'Survey Completed' : 'Complete & End Survey',
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

class _QuestionnaireScreen extends StatefulWidget {
  const _QuestionnaireScreen({
    required this.title,

    required this.subtitle,

    required this.questions,

    required this.initialAnswers,

    this.showDemographics = false,

    this.initialOccupation = '',

    this.initialGender = '',

    this.initialAge,

    this.initialInterview,
  });

  final String title;

  final String subtitle;

  final List<Map<String, dynamic>> questions;

  final Map<int, String> initialAnswers;

  final bool showDemographics;

  final String initialOccupation;

  final String initialGender;

  final int? initialAge;

  /// The interview being edited, if any (keeps its original location).
  final CitizenInterviewResult? initialInterview;

  @override
  State<_QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<_QuestionnaireScreen> {
  late final Map<int, String> _answers = Map<int, String>.from(
    widget.initialAnswers,
  );

  late final TextEditingController _occupationController =
      TextEditingController(text: widget.initialOccupation);

  late final TextEditingController _ageController = TextEditingController(
    text: widget.initialAge?.toString() ?? '',
  );

  String? _gender;

  // Citizen interview location (demographics mode only).
  final LocationService _locationService = LocationService();

  double? _latitude;

  double? _longitude;

  String? _area;

  DateTime? _locationCapturedAt;

  bool _isLocating = false;

  String? _locationError;

  @override
  void initState() {
    super.initState();

    _gender = widget.initialGender.isEmpty ? null : widget.initialGender;

    final existing = widget.initialInterview;

    if (existing != null) {
      _latitude = existing.latitude;
      _longitude = existing.longitude;
      _area = existing.area;
      _locationCapturedAt = existing.locationCapturedAt;
    } else if (widget.showDemographics) {
      // setState is not allowed during initState, so start after the first
      // frame; show the spinner until then.
      _isLocating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _captureLocation();
      });
    }
  }

  Future<void> _captureLocation() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
    });

    try {
      final position = await _locationService.getCurrentLocation();

      final area = await _locationService.getAreaName(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _area = area;
        _locationCapturedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;

      setState(
        () => _locationError = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  void dispose() {
    _occupationController.dispose();

    _ageController.dispose();

    super.dispose();
  }

  void _saveAnswers() {
    if (widget.showDemographics) {
      final occupation = _occupationController.text.trim();

      final age = int.tryParse(_ageController.text.trim());

      if (occupation.isEmpty ||
          _gender == null ||
          age == null ||
          age < 1 ||
          age > 120) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter occupation, select gender, and enter a valid age (1–120).',
            ),
          ),
        );

        return;
      }

      if (_latitude == null || _longitude == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isLocating
                  ? 'Getting the current location, please wait…'
                  : 'Current location is required. Tap Try again.',
            ),
          ),
        );

        return;
      }

      if (_answers.length != widget.questions.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please answer all interview questions.'),
          ),
        );

        return;
      }

      Navigator.pop(
        context,

        CitizenInterviewResult(
          occupation: occupation,

          gender: _gender!,

          age: age,

          answers: Map<int, String>.from(_answers),

          latitude: _latitude!,

          longitude: _longitude!,

          area: _area ?? 'Unknown Area',

          locationCapturedAt: _locationCapturedAt ?? DateTime.now(),
        ),
      );

      return;
    }

    if (_answers.length != widget.questions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer all questions.')),
      );

      return;
    }

    Navigator.pop(context, Map<int, String>.from(_answers));
  }

  /// Read-only "Location" box styled like the other fields, with a button to
  /// capture the current position again.
  Widget _locationField(ColorScheme colors) {
    final Widget content;

    if (_isLocating) {
      content = const Row(
        children: [
          SizedBox(
            width: 16,

            height: 16,

            child: CircularProgressIndicator(strokeWidth: 2),
          ),

          SizedBox(width: 10),

          Text('Getting current location…'),
        ],
      );
    } else if (_latitude != null && _longitude != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Text(
            _area ?? 'Unknown Area',

            style: const TextStyle(fontWeight: FontWeight.w600),
          ),

          Text(
            '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',

            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
      );
    } else {
      content = Text(
        _locationError ?? 'Location not captured.',

        style: TextStyle(color: colors.error),
      );
    }

    final hasLocation = _latitude != null && !_isLocating;

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Current location',

        prefixIcon: Icon(Icons.location_on_outlined),

        border: OutlineInputBorder(),
      ),

      child: Row(
        children: [
          Expanded(child: content),

          if (!_isLocating)
            hasLocation
                ? IconButton(
                    tooltip: 'Update location',

                    onPressed: _captureLocation,

                    icon: const Icon(Icons.my_location),
                  )
                : TextButton(
                    onPressed: _captureLocation,

                    child: const Text('Try again'),
                  ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),

      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),

                children: [
                  Text(
                    widget.subtitle,

                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),

                  const SizedBox(height: 12),

                  // Citizen details at the top of the interview.
                  if (widget.showDemographics) ...[
                    Text(
                      'Citizen Details',

                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: _occupationController,

                      textCapitalization: TextCapitalization.words,

                      decoration: const InputDecoration(
                        labelText: 'Occupation',

                        hintText: 'Enter occupation',

                        prefixIcon: Icon(Icons.work_outline),

                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      initialValue: _gender,

                      decoration: const InputDecoration(
                        labelText: 'Gender',

                        hintText: 'Select gender',

                        prefixIcon: Icon(Icons.person_outline),

                        border: OutlineInputBorder(),
                      ),

                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),

                        DropdownMenuItem(
                          value: 'Female',

                          child: Text('Female'),
                        ),

                        DropdownMenuItem(value: 'Other', child: Text('Other')),

                        DropdownMenuItem(
                          value: 'Prefer not to say',

                          child: Text('Prefer not to say'),
                        ),
                      ],

                      onChanged: (value) {
                        setState(() => _gender = value);
                      },
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: _ageController,

                      keyboardType: TextInputType.number,

                      decoration: const InputDecoration(
                        labelText: 'Age',

                        hintText: 'Enter age',

                        prefixIcon: Icon(Icons.cake_outlined),

                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    _locationField(colors),

                    const SizedBox(height: 24),

                    const Divider(),

                    const SizedBox(height: 12),
                  ],

                  Text(
                    '${_answers.length}/${widget.questions.length} answered',

                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  ...List.generate(widget.questions.length, (index) {
                    final question = widget.questions[index];

                    final options = List<String>.from(
                      question['options'] as List,
                    );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),

                      elevation: 0,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),

                        side: BorderSide(color: colors.outlineVariant),
                      ),

                      child: Padding(
                        padding: const EdgeInsets.all(14),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              'Q${index + 1}. ${question['question']}',

                              style: const TextStyle(
                                fontSize: 16,

                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 8),

                            RadioGroup<String>(
                              groupValue: _answers[index],

                              onChanged: (value) {
                                if (value == null) return;

                                setState(() {
                                  _answers[index] = value;
                                });
                              },

                              child: Column(
                                children: options.map((option) {
                                  return RadioListTile<String>(
                                    contentPadding: EdgeInsets.zero,

                                    dense: true,

                                    title: Text(option),

                                    value: option,
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),

              child: SizedBox(
                width: double.infinity,

                height: 50,

                child: FilledButton(
                  onPressed: _saveAnswers,

                  child: const Text('Save Answers'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
