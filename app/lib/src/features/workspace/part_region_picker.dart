import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../domain/smart_parts/smart_part.dart';

final class PartRegionPickerDialog extends StatefulWidget {
  const PartRegionPickerDialog({
    super.key,
    required this.imageBytes,
    this.initialRegion,
  });

  final Uint8List imageBytes;
  final NormalizedRegion? initialRegion;

  @override
  State<PartRegionPickerDialog> createState() =>
      _PartRegionPickerDialogState();
}

final class _PartRegionPickerDialogState
    extends State<PartRegionPickerDialog> {
  late final double _aspectRatio;
  Offset? _start;
  Offset? _end;
  NormalizedRegion? _region;

  @override
  void initState() {
    super.initState();
    final decoded = img.decodeImage(widget.imageBytes);
    _aspectRatio = decoded == null || decoded.height == 0
        ? 1
        : decoded.width / decoded.height;
    _region = widget.initialRegion;
  }

  Offset _normalized(Offset local, Size size) {
    return Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
  }

  void _commitDrag() {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return;
    final left = start.dx < end.dx ? start.dx : end.dx;
    final right = start.dx > end.dx ? start.dx : end.dx;
    final top = start.dy < end.dy ? start.dy : end.dy;
    final bottom = start.dy > end.dy ? start.dy : end.dy;
    if ((right - left) < 0.03 || (bottom - top) < 0.03) return;
    setState(() {
      _region = NormalizedRegion(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      ).clamp();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('حدد مكان الجزء'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'اسحب مستطيلًا حول الجزء المطلوب. سيستخدم التطبيق هذا القص كمرجع لهذا الجزء فقط.',
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: _aspectRatio,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      setState(() {
                        _start = _normalized(details.localPosition, size);
                        _end = _start;
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _end = _normalized(details.localPosition, size);
                      });
                    },
                    onPanEnd: (_) => _commitDrag(),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                        CustomPaint(
                          painter: _RegionPainter(
                            region: _region,
                            dragStart: _start,
                            dragEnd: _end,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop<NormalizedRegion>(),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _region = const NormalizedRegion(
                left: 0,
                top: 0,
                right: 1,
                bottom: 1,
              );
            });
          },
          child: const Text('كل الصورة'),
        ),
        FilledButton(
          onPressed: _region == null
              ? null
              : () => Navigator.of(context).pop(_region),
          child: const Text('استخدام المنطقة'),
        ),
      ],
    );
  }
}

final class _RegionPainter extends CustomPainter {
  const _RegionPainter({
    required this.region,
    required this.dragStart,
    required this.dragEnd,
  });

  final NormalizedRegion? region;
  final Offset? dragStart;
  final Offset? dragEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.amberAccent;

    Rect? rect;
    final start = dragStart;
    final end = dragEnd;
    if (start != null && end != null) {
      rect = Rect.fromPoints(
        Offset(start.dx * size.width, start.dy * size.height),
        Offset(end.dx * size.width, end.dy * size.height),
      );
    } else if (region != null) {
      rect = Rect.fromLTRB(
        region!.left * size.width,
        region!.top * size.height,
        region!.right * size.width,
        region!.bottom * size.height,
      );
    }

    if (rect != null) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RegionPainter oldDelegate) {
    return oldDelegate.region != region ||
        oldDelegate.dragStart != dragStart ||
        oldDelegate.dragEnd != dragEnd;
  }
}
