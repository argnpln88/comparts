import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/data/auth_repository.dart';

final reviewPhotoPickerProvider = Provider((ref) => ImagePicker());

String? reviewPhotoExtension(Uint8List bytes) {
  if (bytes.length < 12 || bytes.length > 3 * 1024 * 1024) return null;
  if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) return 'jpg';
  if (bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') return 'png';
  if (String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return 'webp';
  }
  return null;
}

class ReviewDraftPhoto {
  ReviewDraftPhoto(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
  String? uploadedPath;
}

class ReviewPhotos extends ConsumerWidget {
  const ReviewPhotos({super.key, required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref
        .watch(supabaseClientProvider)
        ?.storage
        .from('review-photos');
    if (paths.isEmpty || storage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final path in paths)
            Semantics(
              label: 'Buyer item photo',
              button: true,
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => Dialog(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: 'Close photo',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                        Flexible(
                          child: InteractiveViewer(
                            child: Image.network(
                              storage.getPublicUrl(path),
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('Photo unavailable'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    storage.getPublicUrl(path),
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 88,
                      height: 88,
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
