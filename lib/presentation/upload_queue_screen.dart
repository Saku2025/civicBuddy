import 'package:flutter/material.dart';

import '../services/survey_uploader.dart';
import '../services/upload_queue.dart';
import 'upload_progress_view.dart';

/// Finished surveys waiting to be uploaded: select some to upload or
/// delete, or delete one with its own button.
class UploadQueueScreen extends StatefulWidget {
  const UploadQueueScreen({super.key});

  @override
  State<UploadQueueScreen> createState() => _UploadQueueScreenState();
}

class _UploadQueueScreenState extends State<UploadQueueScreen> {
  List<Map<String, dynamic>>? _queued;

  final Set<String> _selected = {};

  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Reload when a survey is uploaded (also automatically, on Wi-Fi).
    UploadQueue.changes.addListener(_load);
  }

  @override
  void dispose() {
    UploadQueue.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final queued = await UploadQueue.list();
    if (!mounted) return;
    setState(() {
      _queued = queued;
      // Forget selections of surveys that are gone.
      _selected.retainAll(queued.map(_idOf));
    });
  }

  static String _idOf(Map<String, dynamic> entry) =>
      entry['survey_id'].toString();

  static Map<String, dynamic> _submissionOf(Map<String, dynamic> entry) =>
      entry['submission'] is Map
      ? Map<String, dynamic>.from(entry['submission'] as Map)
      : const {};

  String _dateText(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '—';

    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}  '
        '${two(date.hour)}:${two(date.minute)}';
  }

  ({int points, int photos, int interviews}) _counts(
    Map<String, dynamic> entry,
  ) {
    final submission = _submissionOf(entry);
    final points = submission['points'] is List
        ? submission['points'] as List
        : const [];
    final photos = points.fold<int>(
      0,
      (sum, p) =>
          sum +
          (p is Map && p['photo_paths'] is List
              ? (p['photo_paths'] as List).length
              : 0),
    );
    final interviews = submission['citizens'] is List
        ? (submission['citizens'] as List).length
        : 0;
    return (points: points.length, photos: photos, interviews: interviews);
  }

  String _plural(int count, String word) =>
      '$count $word${count == 1 ? '' : 's'}';

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _toggleAll() {
    final ids = (_queued ?? const []).map(_idOf);
    setState(() {
      if (_selected.length == ids.length) {
        _selected.clear();
      } else {
        _selected.addAll(ids);
      }
    });
  }

  Future<void> _uploadSelected() async {
    final ids = (_queued ?? const [])
        .map(_idOf)
        .where(_selected.contains)
        .toList();
    if (ids.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);

    if (await UploadQueue.checkNetwork() == NetworkStatus.offline) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'No internet connection. Try again when you are online.',
          ),
        ),
      );
      return;
    }

    setState(() => _uploading = true);
    final errors = await UploadQueue.upload(ids);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _selected.clear();
    });

    final uploaded = ids.length - errors.length;
    messenger.showSnackBar(
      SnackBar(
        duration: Duration(seconds: errors.isEmpty ? 4 : 8),
        content: Text(
          errors.isEmpty
              ? 'Uploaded ${_plural(uploaded, 'survey')}.'
              : 'Uploaded ${_plural(uploaded, 'survey')}; '
                    '${errors.length} failed and stay in the queue.\n'
                    '${errors.first}',
        ),
      ),
    );
  }

  Future<void> _delete(List<String> ids) async {
    if (ids.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.delete_forever_outlined,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: Text(
          ids.length == 1
              ? 'Delete queued survey?'
              : 'Delete ${ids.length} queued surveys?',
        ),
        content: Text(
          '${ids.length == 1 ? ids.first : _plural(ids.length, 'survey')}'
          '\n\nThis deletes the survey data and photos from this phone. '
          'They were never uploaded, so they cannot be recovered.',
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

    if (confirmed != true) return;

    await UploadQueue.delete(ids);
    if (!mounted) return;
    setState(() => _selected.removeAll(ids));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ids.length == 1
              ? 'Deleted ${ids.first}.'
              : 'Deleted ${_plural(ids.length, 'survey')}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final queued = _queued;
    final allSelected =
        queued != null &&
        queued.isNotEmpty &&
        _selected.length == queued.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload queue'),
        actions: [
          if (queued != null && queued.isNotEmpty)
            TextButton.icon(
              onPressed: _toggleAll,
              icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
              label: Text(allSelected ? 'Select none' : 'Select all'),
            ),
        ],
      ),
      body: queued == null
          ? const Center(child: CircularProgressIndicator())
          : queued.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_done_outlined,
                      size: 56,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Upload queue is empty',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Surveys finished without internet, or saved to the '
                      'queue at submit, wait here and upload automatically '
                      'on Wi-Fi.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ValueListenableBuilder<SurveyUploader?>(
              valueListenable: UploadQueue.current,
              builder: (context, current, _) => ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: queued.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Text(
                      'Uploads automatically when the phone is on Wi-Fi. '
                      'Select surveys to upload now or delete them.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    );
                  }

                  final entry = queued[index - 1];
                  final id = _idOf(entry);
                  final counts = _counts(entry);
                  final uploadingThis = current?.surveyId == id;

                  return Card(
                    elevation: 0,
                    color: _selected.contains(id)
                        ? colors.primaryContainer.withValues(alpha: 0.5)
                        : colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: _selected.contains(id)
                            ? colors.primary
                            : colors.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: uploadingThis ? null : () => _toggle(id),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: _selected.contains(id),
                                  onChanged: uploadingThis
                                      ? null
                                      : (_) => _toggle(id),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        id,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Finished ${_dateText(_submissionOf(entry)['ended_at'])}\n'
                                        '${counts.points} pt · '
                                        '${_plural(counts.photos, 'photo')} · '
                                        '${_plural(counts.interviews, 'interview')}',
                                      ),
                                    ],
                                  ),
                                ),
                                if (uploadingThis)
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    ),
                                  )
                                else
                                  IconButton(
                                    tooltip: 'Delete this survey',
                                    color: colors.error,
                                    onPressed: () => _delete([id]),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                            if (uploadingThis)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  4,
                                  12,
                                  4,
                                ),
                                child: UploadProgressView(uploader: current!),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
      bottomNavigationBar: (queued == null || queued.isEmpty)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.error,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: _selected.isEmpty
                            ? null
                            : () => _delete(_selected.toList()),
                        icon: const Icon(Icons.delete_outline),
                        label: Text('Delete (${_selected.length})'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: (_selected.isEmpty || _uploading)
                            ? null
                            : _uploadSelected,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                          _uploading
                              ? 'Uploading…'
                              : 'Upload (${_selected.length})',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
