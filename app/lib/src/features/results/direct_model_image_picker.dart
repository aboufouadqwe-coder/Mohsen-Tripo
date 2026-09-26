import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/supabase/reference_image_repository.dart';

final class DirectModelLocalImage {
  const DirectModelLocalImage({
    required this.name,
    required this.sizeBytes,
    required this.readBytes,
  });

  final String name;
  final int sizeBytes;
  final Future<Uint8List> Function() readBytes;
}

typedef DirectModelLocalImagePicker = Future<DirectModelLocalImage?> Function();

final class DirectModelImagePicker extends StatefulWidget {
  const DirectModelImagePicker({
    super.key,
    required this.userId,
    required this.projectId,
    required this.repository,
    required this.onGenerate,
    this.pickImage,
    this.disabled = false,
  });

  static const maxBytes = 20 * 1024 * 1024;

  final String userId;
  final String projectId;
  final DirectModelImageRepository repository;
  final Future<void> Function(String referenceStoragePath) onGenerate;
  final DirectModelLocalImagePicker? pickImage;
  final bool disabled;

  @override
  State<DirectModelImagePicker> createState() => _DirectModelImagePickerState();
}

final class _DirectModelImagePickerState extends State<DirectModelImagePicker> {
  bool _busy = false;
  String? _error;
  String? _uploadedPath;
  String? _selectedName;

  Future<DirectModelLocalImage?> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;

    return DirectModelLocalImage(
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
    if (_busy || widget.disabled) return;
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
      if (image.sizeBytes > DirectModelImagePicker.maxBytes) {
        setState(() => _error = 'حجم الصورة يجب ألا يتجاوز 20 MB.');
        return;
      }

      final bytes = await image.readBytes();
      if (bytes.isEmpty) {
        setState(() => _error = 'الصورة المختارة فارغة أو غير قابلة للقراءة.');
        return;
      }

      final path = await widget.repository.uploadModelInput(
        userId: widget.userId,
        projectId: widget.projectId,
        bytes: bytes,
        extension: extension!,
      );
      if (!mounted) return;
      setState(() {
        _uploadedPath = path;
        _selectedName = image.name;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر تجهيز الصورة لتوليد 3D.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    final path = _uploadedPath;
    if (_busy || widget.disabled || path == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onGenerate(path);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر بدء توليد 3D من الصورة.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تحويل صورة مباشرة إلى 3D',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'اختياري: اختر صورة واضحة من الهاتف. PNG أو JPEG حتى 20 MB، ويفضل أن يكون الجسم ظاهرًا بالكامل والخلفية بسيطة.',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy || widget.disabled ? null : _select,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('اختيار صورة للـ 3D'),
            ),
            if (_selectedName != null) ...[
              const SizedBox(height: 8),
              Text(_selectedName!),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy || widget.disabled ? null : _generate,
                icon: const Icon(Icons.view_in_ar),
                label: const Text('توليد 3D من الصورة'),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
