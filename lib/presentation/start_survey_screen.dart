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

  const CitizenInterviewResult({
    required this.occupation,

    required this.gender,

    required this.age,

    required this.answers,
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

  final List<_SurveyPoint> _points = [];

  final Map<int, String> _citizenAnswers = {};

  late final DateTime _startedAt = DateTime.now();

  late final String _surveyId = 'SUR-${_startedAt.microsecondsSinceEpoch}';

  bool _isAddingPoint = false;

  bool _isSavingSurvey = false;

  bool _surveyEnded = false;

  String _citizenOccupation = '';

  String _citizenGender = '';

  int? _citizenAge;

  static const List<Map<String, dynamic>> _surveyorQuestions = [
    {
      'question': ' Visual Cleanliness: Based on the captured photo, how would you rate the cleanliness of this specific spot? Are there visible garbage heaps or betel leaf (paan) stains?',

      'options': ['Very Clean', 'Mildly Dirty', 'Very Dirty'],
    },

    {
      'question':
          ' Type of Waste: What is the primary type of garbage dumped here?',

      'options': ['Plastic waste', 'Organic/Food', 'Construction/Mixed'],
    },

    {
      'question': ' Odor Intensity: How strong is the foul smell in this immediate area?',

      'options': ['Mild', 'Unbearable', 'No Smell'],
    },

    {
      'question': ' Road Blockage: Is the dumped garbage spilling over onto the main road or walking path?',

      'options': ['Yes', 'No'],
    },

    {
      'question': ' Dustbin Status: Is there a designated public dustbin available, and what is its condition?',

      'options': [
        'Not Available',

        'Available & Clean',

        'Available but Overflowing/Broken',
      ],
    },
  ];

  static const List<Map<String, dynamic>> _citizenQuestions = [
    {
      'question': 'Timing Patterns: At what time of the day does this spot usually get the dirtiest, and when do the sweepers usually clean it?',

      'options': ['Daily', 'Several times a week', 'Weekly', 'Rarely'],
    },

    {
      'question': 'Sweeper Regularity: Do the municipal sweepers come to collect the garbage regularly?',

      'options': ['Yes', 'No'],
    },

    {
      'question': 'Source of Garbage: In your observation, where does most of this garbage come from?',

      'options': ['Households', 'Local Market', 'Shops', 'Outsiders'],
    },

    {
      'question': 'Complaint Resolution: If residents report an open garbage dump to the local authorities, do they take action to clear it?',

      'options': ['Always', 'Sometimes', 'Never', 'Unaware'],
    },

    {
      'question': 'CCTV Intervention: Do you think installing CCTV cameras would stop people from littering in this spot?',

      'options': ['Yes', 'No'],
    },

    {
      'question': 'Municipal Rating: How would you rate the local municipality`s overall efficiency in handling public hygiene?',

      'options': ['Good', 'Average', 'Poor'],
    },

    {
      'question': 'Community Participation: Would you be willing to actively participate in a community cleanliness drive for your neighborhood?',

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

    if (point.photos.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 photos allowed per point.')),
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

  Future<void> _showCitizenInterview() async {
    final result = await Navigator.push<CitizenInterviewResult>(
      context,

      MaterialPageRoute(
        builder: (_) => _QuestionnaireScreen(
          title: 'Citizen Interview',

          subtitle: 'Citizen details and interview questions',

          questions: _citizenQuestions,

          initialAnswers: _citizenAnswers,

          showDemographics: true,

          initialOccupation: _citizenOccupation,

          initialGender: _citizenGender,

          initialAge: _citizenAge,
        ),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      _citizenOccupation = result.occupation;

      _citizenGender = result.gender;

      _citizenAge = result.age;

      _citizenAnswers
        ..clear()
        ..addAll(result.answers);
    });
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

    if (_citizenAnswers.length != _citizenQuestions.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete all citizen interview questions before ending.',
          ),
        ),
      );

      await _showCitizenInterview();

      if (!mounted) return;

      if (_citizenAnswers.length != _citizenQuestions.length) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit survey?'),
        content: Text(
          'Submit ${_points.length} point(s) and all questionnaire answers to Supabase?',
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

      final citizenDocument = <String, dynamic>{
        'occupation': _citizenOccupation,
        'gender': _citizenGender,
        'age': _citizenAge,
        'answers': {
          for (var i = 0; i < _citizenQuestions.length; i++)
            _citizenQuestions[i]['question'] as String: _citizenAnswers[i],
        },
      };

      await SurveyService.saveSurvey(
        surveyId: _surveyId,
        startedAt: _startedAt,
        endedAt: DateTime.now(),
        surveyData: {'points': pointDocuments, 'citizen': citizenDocument},
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
                    'Each point records GPS, timestamp, up to 5 photos, and a 5-question surveyor questionnaire.',

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

                  ..._points.map(
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
                                    'Photos: ${point.photos.length}/5',
                                  ),
                                ),

                                if (!_surveyEnded)
                                  OutlinedButton.icon(
                                    onPressed: point.photos.length == 5
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

                  const SizedBox(height: 8),

                  Card(
                    elevation: 0,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),

                      side: BorderSide(color: colors.outlineVariant),
                    ),

                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colors.primaryContainer,

                        child: Icon(
                          Icons.record_voice_over_outlined,

                          color: colors.primary,
                        ),
                      ),

                      title: const Text(
                        'Citizen Interview',

                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),

                      subtitle: Text(
                        'Answers: ${_citizenAnswers.length}/${_citizenQuestions.length}',
                      ),

                      trailing: const Icon(Icons.chevron_right),

                      onTap: _surveyEnded ? null : _showCitizenInterview,
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
  });

  final String title;

  final String subtitle;

  final List<Map<String, dynamic>> questions;

  final Map<int, String> initialAnswers;

  final bool showDemographics;

  final String initialOccupation;

  final String initialGender;

  final int? initialAge;

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

  @override
  void initState() {
    super.initState();

    _gender = widget.initialGender.isEmpty ? null : widget.initialGender;
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
