import 'package:flutter/material.dart';

import '../services/survey_uploader.dart';

String formatMb(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Upload progress of one survey: photo count, MB sent of the total, a
/// progress bar and Pause/Resume.
class UploadProgressView extends StatelessWidget {
  const UploadProgressView({super.key, required this.uploader});

  final SurveyUploader uploader;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: uploader,
      builder: (context, _) {
        final u = uploader;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    u.paused
                        ? 'Paused · ${u.photosDone} of ${u.photosTotal} photos sent'
                        : u.preparing
                        ? 'Preparing photos…'
                        : u.photosDone < u.photosTotal
                        ? 'Uploading photo ${u.photosDone + 1} of ${u.photosTotal}…'
                        : 'Saving survey…',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (u.photosDone < u.photosTotal)
                  TextButton.icon(
                    onPressed: u.togglePause,
                    icon: Icon(
                      u.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    ),
                    label: Text(u.paused ? 'Resume' : 'Pause'),
                  ),
              ],
            ),
            if (u.bytesTotal > 0)
              Text(
                u.preparing
                    ? 'Total size so far: ${formatMb(u.bytesTotal)}'
                    : '${formatMb(u.bytesDone)} of ${formatMb(u.bytesTotal)}',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: (u.preparing || u.bytesTotal == 0)
                    ? null
                    : u.bytesDone / u.bytesTotal,
              ),
            ),
          ],
        );
      },
    );
  }
}
