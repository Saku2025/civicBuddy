import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/draft_service.dart';
import 'start_survey_screen.dart';

/// Unfinished surveys saved on this phone: continue or delete them.
class DraftsScreen extends StatefulWidget {
  const DraftsScreen({super.key});

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  late Future<List<Map<String, dynamic>>> _draftsFuture = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final userId = AuthService.getCurrentUser()?.id;
    if (userId == null) return Future.value(const []);
    return DraftService.list(userId);
  }

  // Block body: an arrow would return the Future, which setState rejects.
  void _reload() {
    setState(() {
      _draftsFuture = _load();
    });
  }

  String _dateText(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '—';

    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}  '
        '${two(date.hour)}:${two(date.minute)}';
  }

  ({int points, int photos, int interviews}) _counts(
    Map<String, dynamic> draft,
  ) {
    final points = draft['points'] is List ? draft['points'] as List : [];
    final photos = points.fold<int>(
      0,
      (sum, p) =>
          sum +
          (p is Map && p['photos'] is List ? p['photos'].length as int : 0),
    );
    final interviews = draft['interviews'] is List
        ? (draft['interviews'] as List).length
        : 0;
    return (points: points.length, photos: photos, interviews: interviews);
  }

  String _plural(int count, String word) =>
      '$count $word${count == 1 ? '' : 's'}';

  Future<void> _continue(Map<String, dynamic> draft) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StartSurveyScreen(draft: draft)),
    );
    if (mounted) _reload();
  }

  Future<void> _delete(Map<String, dynamic> draft) async {
    final id = draft['survey_id']?.toString() ?? 'this draft';
    final counts = _counts(draft);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.delete_forever_outlined,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: const Text('Delete draft?'),
        content: Text(
          '$id\n\nThis deletes its ${_plural(counts.points, 'point')}, '
          '${_plural(counts.photos, 'photo')} and '
          '${_plural(counts.interviews, 'interview')} from this phone. '
          'It was never submitted, so it cannot be recovered.',
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

    await DraftService.delete(draft['survey_id'].toString());

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Deleted draft $id.')));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Drafts')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _draftsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final drafts = snapshot.data ?? const [];

          if (drafts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_note_outlined,
                      size: 56,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No drafts',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Surveys you leave before submitting are saved here '
                      'automatically.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: drafts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final draft = drafts[index];
              final counts = _counts(draft);

              return Card(
                elevation: 0,
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  leading: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Icon(
                      Icons.edit_note,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    draft['survey_id']?.toString() ?? 'Draft',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Edited ${_dateText(draft['updated_at'])}\n'
                      '${counts.points} pt · ${counts.photos} photo'
                      '${counts.photos == 1 ? '' : 's'} · '
                      '${counts.interviews} interview'
                      '${counts.interviews == 1 ? '' : 's'}',
                    ),
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Delete draft',
                        color: colors.error,
                        onPressed: () => _delete(draft),
                        icon: const Icon(Icons.delete_outline),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _continue(draft),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
