import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/survey_service.dart';

class PreviousSurveysScreen extends StatefulWidget {
  const PreviousSurveysScreen({super.key});

  @override
  State<PreviousSurveysScreen> createState() => _PreviousSurveysScreenState();
}

class _PreviousSurveysScreenState extends State<PreviousSurveysScreen> {
  late Future<List<Map<String, dynamic>>> _surveysFuture;

  @override
  void initState() {
    super.initState();

    _loadSurveys();
  }

  void _loadSurveys() {
    _surveysFuture = SurveyService.getPreviousSurveys();
  }

  Future<void> _refresh() async {
    setState(_loadSurveys);

    await _surveysFuture;
  }

  // Row ids being deleted (show a spinner) or already deleted (hidden
  // without reloading the whole list).
  final Set<Object?> _deletingIds = {};

  final Set<Object?> _deletedIds = {};

  int _interviewCount(Map<String, dynamic> survey) {
    final data = survey['survey_data'];

    if (data is! Map) return 0;

    if (data['citizens'] is List) return (data['citizens'] as List).length;

    return data['citizen'] is Map ? 1 : 0;
  }

  Future<void> _deleteSurvey(Map<String, dynamic> survey) async {
    final id = survey['survey_id']?.toString() ?? 'this survey';
    final points = _pointCount(survey);
    final photos = _photoCount(survey);
    final interviews = _interviewCount(survey);

    final confirmed = await showDialog<bool>(
      context: context,

      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.delete_forever_outlined,
          color: Theme.of(ctx).colorScheme.error,
        ),

        title: const Text('Delete survey?'),

        content: Text(
          '$id\n\nThis permanently deletes its $points point(s), '
          '$photos photo(s) and $interviews citizen interview(s). '
          'This cannot be undone.',
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),

            child: const Text('Cancel'),
          ),

          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),

            onPressed: () => Navigator.pop(ctx, true),

            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingIds.add(survey['id']));

    try {
      await SurveyService.deleteSurvey(survey);

      if (!mounted) return;

      setState(() => _deletedIds.add(survey['id']));

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Deleted $id.')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingIds.remove(survey['id']));
    }
  }

  String _dateText(dynamic value) {
    if (value == null) return 'Date unavailable';

    final parsed = DateTime.tryParse(value.toString())?.toLocal();

    if (parsed == null) return value.toString();

    final d = parsed.day.toString().padLeft(2, '0');

    final m = parsed.month.toString().padLeft(2, '0');

    return '$d/$m/${parsed.year}  ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  int _pointCount(Map<String, dynamic> survey) {
    final data = survey['survey_data'];

    if (data is! Map) return 0;

    final points = data['points'];

    return points is List ? points.length : 0;
  }

  int _photoCount(Map<String, dynamic> survey) {
    final data = survey['survey_data'];

    if (data is! Map || data['points'] is! List) return 0;

    var count = 0;

    for (final point in data['points'] as List) {
      if (point is Map && point['photos'] is List) {
        count += (point['photos'] as List).length;
      }
    }

    return count;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Previous Surveys'),

        actions: [
          IconButton(
            tooltip: 'Refresh',

            onPressed: () => _refresh(),

            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _surveysFuture,

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _MessageState(
              icon: Icons.cloud_off_outlined,

              title: 'Could not load surveys',

              message: snapshot.error.toString(),

              buttonText: 'Try again',

              onPressed: () => setState(_loadSurveys),
            );
          }

          final surveys = (snapshot.data ?? [])
              .where((s) => !_deletedIds.contains(s['id']))
              .toList();

          if (surveys.isEmpty) {
            return const _MessageState(
              icon: Icons.assignment_outlined,

              title: 'No previous surveys',

              message: 'Completed surveys you submit will appear here.',
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,

            child: ListView.separated(
              padding: const EdgeInsets.all(16),

              itemCount: surveys.length,

              separatorBuilder: (_, _) => const SizedBox(height: 10),

              itemBuilder: (context, index) {
                final survey = surveys[index];

                final pointCount = _pointCount(survey);

                final photoCount = _photoCount(survey);

                final id = survey['survey_id']?.toString() ?? 'Unknown survey';

                return Card(
                  elevation: 0,

                  color: colors.surface,

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),

                    side: BorderSide(color: colors.outlineVariant),
                  ),

                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),

                    leading: CircleAvatar(
                      backgroundColor: colors.primaryContainer,

                      child: Icon(
                        Icons.assignment_turned_in_outlined,

                        color: colors.onPrimaryContainer,
                      ),
                    ),

                    title: Text(
                      id,

                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),

                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),

                      child: Text(
                        '${_dateText(survey['started_at'])}\n'
                        '$pointCount location point${pointCount == 1 ? '' : 's'} · '
                        '$photoCount photo${photoCount == 1 ? '' : 's'}',
                      ),
                    ),

                    isThreeLine: true,

                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        _deletingIds.contains(survey['id'])
                            ? const Padding(
                                padding: EdgeInsets.all(12),

                                child: SizedBox(
                                  width: 22,

                                  height: 22,

                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Delete survey',

                                color: colors.error,

                                onPressed: () => _deleteSurvey(survey),

                                icon: const Icon(Icons.delete_outline),
                              ),

                        const Icon(Icons.chevron_right),
                      ],
                    ),

                    onTap: () => Navigator.push(
                      context,

                      MaterialPageRoute(
                        builder: (_) => SurveyDetailsScreen(survey: survey),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class SurveyDetailsScreen extends StatelessWidget {
  const SurveyDetailsScreen({super.key, required this.survey});

  final Map<String, dynamic> survey;

  String _dateText(dynamic value) {
    if (value == null) return 'Not available';

    final date = DateTime.tryParse(value.toString())?.toLocal();

    return date == null ? value.toString() : date.toString().split('.').first;
  }

  Map<String, dynamic> get _data {
    final value = survey['survey_data'];

    return value is Map<String, dynamic>
        ? value
        : value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final rawPoints = _data['points'];

    final points = rawPoints is List
        ? rawPoints
              .whereType<Map>()
              .map((p) => Map<String, dynamic>.from(p))
              .toList()
        : <Map<String, dynamic>>[];

    // Surveys from v1.7.5 store a "citizens" list; older ones a single
    // "citizen" map.
    final citizensRaw = _data['citizens'];
    final citizenRaw = _data['citizen'];

    final citizens = citizensRaw is List
        ? citizensRaw
              .whereType<Map>()
              .map((c) => Map<String, dynamic>.from(c))
              .toList()
        : citizenRaw is Map
        ? [Map<String, dynamic>.from(citizenRaw)]
        : <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Survey Details')),

      body: ListView(
        padding: const EdgeInsets.all(16),

        children: [
          Card(
            elevation: 0,

            color: colors.primaryContainer,

            child: Padding(
              padding: const EdgeInsets.all(16),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    survey['survey_id']?.toString() ?? 'Survey',

                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colors.onPrimaryContainer,

                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Status: ${survey['status'] ?? 'unknown'}',

                    style: TextStyle(color: colors.onPrimaryContainer),
                  ),

                  Text(
                    'Started: ${_dateText(survey['started_at'])}',

                    style: TextStyle(color: colors.onPrimaryContainer),
                  ),

                  Text(
                    'Ended: ${_dateText(survey['ended_at'])}',

                    style: TextStyle(color: colors.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'Survey points (${points.length})',

            style: Theme.of(context).textTheme.titleLarge,
          ),

          const SizedBox(height: 8),

          if (points.isEmpty) const Text('No survey points were saved.'),

          ...points.map((point) => _PointCard(point: point)),

          const SizedBox(height: 16),

          Text(
            'Citizen interviews (${citizens.length})',

            style: Theme.of(context).textTheme.titleLarge,
          ),

          const SizedBox(height: 8),

          if (citizens.isEmpty) const Text('No citizen interview was saved.'),

          for (var i = 0; i < citizens.length; i++)
            _citizenCard(context, i + 1, citizens[i]),
        ],
      ),
    );
  }

  Widget _citizenCard(
    BuildContext context,
    int number,
    Map<String, dynamic> citizen,
  ) {
    final colors = Theme.of(context).colorScheme;

    final answers = citizen['answers'] is Map
        ? Map<String, dynamic>.from(citizen['answers'] as Map)
        : <String, dynamic>{};

    return Card(
      margin: const EdgeInsets.only(bottom: 10),

      elevation: 0,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),

        side: BorderSide(color: colors.outlineVariant),
      ),

      child: Padding(
        padding: const EdgeInsets.all(14),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              'Interview $number',

              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            _detail('Occupation', citizen['occupation']),

            _detail('Gender', citizen['gender']),

            _detail('Age', citizen['age']),

            // Saved from v1.7.8; older interviews have no location.
            _detail(
              'Location',
              citizen['latitude'] == null
                  ? null
                  : '${citizen['area'] ?? 'Unknown Area'} '
                        '(${citizen['latitude']}, ${citizen['longitude']})',
            ),

            const Divider(),

            if (answers.isEmpty) const Text('No citizen answers saved.'),

            ...answers.entries.map((e) => _answer(e.key, e.value)),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),

    child: Text('$label: ${value ?? 'Not provided'}'),
  );

  Widget _answer(String question, dynamic answer) => Padding(
    padding: const EdgeInsets.only(top: 8),

    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(question, style: const TextStyle(fontWeight: FontWeight.w600)),

        const SizedBox(height: 3),

        Text(answer?.toString() ?? 'Not answered'),
      ],
    ),
  );
}

class _PointCard extends StatelessWidget {
  const _PointCard({required this.point});

  final Map<String, dynamic> point;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final photosRaw = point['photos'];

    final photos = photosRaw is List
        ? photosRaw
              .whereType<Map>()
              .map((p) => Map<String, dynamic>.from(p))
              .toList()
        : <Map<String, dynamic>>[];

    final answersRaw = point['surveyor_answers'];

    final answers = answersRaw is Map
        ? Map<String, dynamic>.from(answersRaw)
        : <String, dynamic>{};

    return Card(
      margin: const EdgeInsets.only(bottom: 10),

      elevation: 0,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),

        side: BorderSide(color: colors.outlineVariant),
      ),

      child: Padding(
        padding: const EdgeInsets.all(14),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              'Point ${point['point_number'] ?? ''}',

              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Text('Area: ${point['area'] ?? 'Unknown'}'),

            Text('Latitude: ${point['latitude'] ?? 'N/A'}'),

            Text('Longitude: ${point['longitude'] ?? 'N/A'}'),

            Text('Captured: ${point['captured_at'] ?? 'N/A'}'),

            if (photos.isNotEmpty) ...[
              const SizedBox(height: 12),

              SizedBox(
                height: 110,

                child: ListView.separated(
                  scrollDirection: Axis.horizontal,

                  itemCount: photos.length,

                  separatorBuilder: (_, _) => const SizedBox(width: 8),

                  itemBuilder: (context, index) => _PrivateSurveyPhoto(
                    photo: photos[index],
                    allPaths: [
                      for (final photo in photos)
                        photo['storage_path']?.toString() ?? '',
                    ],
                    index: index,
                    title: 'Point ${point['point_number'] ?? ''}',
                  ),
                ),
              ),
            ],

            const Divider(height: 24),

            Text(
              'Surveyor answers',

              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            if (answers.isEmpty) const Text('No answers saved.'),

            ...answers.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      e.key,

                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),

                    Text(e.value?.toString() ?? 'Not answered'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivateSurveyPhoto extends StatefulWidget {
  const _PrivateSurveyPhoto({
    required this.photo,
    required this.allPaths,
    required this.index,
    required this.title,
  });

  final Map<String, dynamic> photo;

  // Every photo of the point, so the viewer can move between them.
  final List<String> allPaths;

  final int index;

  final String title;

  @override
  State<_PrivateSurveyPhoto> createState() => _PrivateSurveyPhotoState();
}

class _PrivateSurveyPhotoState extends State<_PrivateSurveyPhoto> {
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();

    _urlFuture = _createUrl();
  }

  Future<String> _createUrl() async {
    final path = widget.photo['storage_path']?.toString();

    if (path == null || path.isEmpty) {
      throw Exception('Photo path missing');
    }

    return Supabase.instance.client.storage
        .from(SurveyService.photoBucket)
        .createSignedUrl(path, 3600);
  }

  void _openPhoto() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SurveyPhotoViewer(
          paths: widget.allPaths,
          initialIndex: widget.index,
          title: widget.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,

      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 110,

            height: 110,

            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            width: 110,

            height: 110,

            color: Theme.of(context).colorScheme.surfaceContainerHighest,

            child: const Icon(Icons.broken_image_outlined),
          );
        }

        final url = snapshot.data!;

        return Material(
          color: Colors.transparent,

          child: InkWell(
            onTap: _openPhoto,

            borderRadius: BorderRadius.circular(10),

            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),

              child: Image.network(
                url,

                width: 110,

                height: 110,

                fit: BoxFit.cover,

                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 110,

                    height: 110,

                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,

                    child: const Icon(Icons.broken_image_outlined),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen viewer for one point's photos: swipe or use the arrows to move
/// between them, pinch to zoom.
class _SurveyPhotoViewer extends StatefulWidget {
  const _SurveyPhotoViewer({
    required this.paths,
    required this.initialIndex,
    required this.title,
  });

  final List<String> paths;

  final int initialIndex;

  final String title;

  @override
  State<_SurveyPhotoViewer> createState() => _SurveyPhotoViewerState();
}

class _SurveyPhotoViewerState extends State<_SurveyPhotoViewer> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );

  late int _index = widget.initialIndex;

  // While a photo is zoomed in, one-finger drags pan it instead of paging.
  bool _zoomed = false;

  // One request signs every photo of the point.
  late final Future<Map<String, String>> _urlsFuture = _loadUrls();

  Future<Map<String, String>> _loadUrls() async {
    final results = await Supabase.instance.client.storage
        .from(SurveyService.photoBucket)
        .createSignedUrlsResult(
          widget.paths.where((p) => p.isNotEmpty).toSet().toList(),
          3600,
        );

    // Missing files are left out and show "Could not load this photo".
    return {
      for (final result in results)
        if (result case SignedUrlSuccess(:final path, :final signedUrl))
          path: signedUrl,
    };
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.paths.length;

    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,

        foregroundColor: Colors.white,

        title: Text(
          count > 1 ? '${widget.title} · ${_index + 1} / $count' : widget.title,
        ),
      ),

      body: FutureBuilder<Map<String, String>>(
        future: _urlsFuture,

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          final urls = snapshot.data ?? const <String, String>{};

          return Stack(
            children: [
              PageView.builder(
                controller: _pageController,

                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),

                itemCount: count,

                onPageChanged: (index) => setState(() {
                  _index = index;
                  _zoomed = false;
                }),

                itemBuilder: (context, index) => _ZoomablePhoto(
                  url: urls[widget.paths[index]],
                  onZoomChanged: (zoomed) {
                    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                  },
                ),
              ),

              if (count > 1 && _index > 0)
                _arrow(
                  Alignment.centerLeft,
                  Icons.chevron_left,
                  () => _goTo(_index - 1),
                ),

              if (count > 1 && _index < count - 1)
                _arrow(
                  Alignment.centerRight,
                  Icons.chevron_right,
                  () => _goTo(_index + 1),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _arrow(Alignment alignment, IconData icon, VoidCallback onPressed) {
    return Align(
      alignment: alignment,

      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),

        child: IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.5),
            foregroundColor: Colors.white,
          ),

          onPressed: onPressed,

          icon: Icon(icon, size: 30),
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.url, required this.onZoomChanged});

  final String? url;

  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final TransformationController _controller = TransformationController();

  bool get _isZoomed => _controller.value.getMaxScaleOnAxis() > 1.01;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;

    if (url == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),

          child: Text(
            'Could not load this photo.',

            style: TextStyle(color: Colors.white),

            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return GestureDetector(
      // Double-tap resets the zoom.
      onDoubleTap: () {
        _controller.value = Matrix4.identity();
        widget.onZoomChanged(false);
      },

      child: InteractiveViewer(
        transformationController: _controller,

        minScale: 1,

        maxScale: 5,

        // Panning only when zoomed, so swipes reach the PageView otherwise.
        panEnabled: _isZoomed,

        onInteractionEnd: (_) {
          setState(() {});
          widget.onZoomChanged(_isZoomed);
        },

        child: Center(
          child: Image.network(
            url,

            fit: BoxFit.contain,

            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;

              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },

            errorBuilder: (context, error, stackTrace) {
              return const Padding(
                padding: EdgeInsets.all(24),

                child: Text(
                  'Could not load this photo.',

                  style: TextStyle(color: Colors.white),

                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,

    required this.title,

    required this.message,

    this.buttonText,

    this.onPressed,
  });

  final IconData icon;

  final String title;

  final String message;

  final String? buttonText;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),

            const SizedBox(height: 16),

            Text(
              title,

              style: Theme.of(context).textTheme.titleLarge,

              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(message, textAlign: TextAlign.center),

            if (buttonText != null && onPressed != null) ...[
              const SizedBox(height: 16),

              FilledButton(onPressed: onPressed, child: Text(buttonText!)),
            ],
          ],
        ),
      ),
    );
  }
}
