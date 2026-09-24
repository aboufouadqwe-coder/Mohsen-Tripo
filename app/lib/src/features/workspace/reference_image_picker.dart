import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/supabase/reference_image_repository.dart';

final class LocalReferenceImage {
  const LocalReferenceImage({
    required this.name,
    required this.sizeBytes,
    required this.readBytes,
  });

  final String name;
  final int sizeBytes;
  final Future<Uint8List> Function() readBytes;
}

typedef LocalReferenceImagePicker = Future<LocalReferenceImage?> Function();

final class ReferenceImagePicker extends StatefulWidget {
  const ReferenceImagePicker({
    super.key,
    required this.userId,
    required this.projectId,
    required this.repository,
    required this.onUploaded,
    this.pickImage,
  });

  static const maxBytes = 20 * 1024 * 1024;

  final String userId;
  final String projectId;
  final ReferenceImageRepository repository;
  final ValueChanged<String> onUploaded;
  final LocalReferenceImagePicker? pickImage;

  @override
  State<ReferenceImagePicker> createState() => _ReferenceImagePickerState();
}

final class _ReferenceImagePickerState extends State<ReferenceImagePicker> {
  bool _busy = false;
  String? _error;

  Future<LocalReferenceImage?> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;

    return LocalReferenceImage(
      name: file.name,
      sizeBytes: await file.length(),
      readBytes: file.readAsBytes,
    );
  }

  String? _extension(String name) {
    final index = name.lastIndexOf('.');
    if (index < 0 || index == name.length - 1) return null;
    return name.substring(index + 1).toLowerCase();
  }

  Future<void> _select() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final image = await (widget.pickImage ?? _pickFromGallery)();
      if (image == null) return;

      final extension = _extension(image.name);
      if (!{'png', 'jpg', 'jpeg'}.contains(extension)) {
        setState(() => _error = 'اختر صورة PNG أو JPEG فقط.');
        return;
      }
      if (image.sizeBytes > ReferenceImagePicker.maxBytes) {
        setState(() => _error = 'حجم الصورة يجب ألا يتجاوز 20 MB.');
        return;
      }

      final path = await widget.repository.uploadReference(
        userId: widget.userId,
        projectId: widget.projectId,
        bytes: await image.readBytes(),
        extension: extension!,
      );
      if (!mounted) return;
      widget.onUploaded(path);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر رفع الصورة المرجعية.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _select,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('رفع صورة'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
