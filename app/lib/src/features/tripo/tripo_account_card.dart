import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tripo_account_controller.dart';

final class TripoAccountCard extends StatefulWidget {
  const TripoAccountCard({
    super.key,
    required this.controller,
  });

  final TripoAccountController controller;

  @override
  State<TripoAccountCard> createState() => _TripoAccountCardState();
}

final class _TripoAccountCardState extends State<TripoAccountCard>
    with WidgetsBindingObserver {
  static final Uri _consoleUri = Uri.parse('https://platform.tripo3d.ai');

  static Future<String?> readClipboardText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  static Future<bool> openConsoleInChrome() =>
      launchUrl(_consoleUri, mode: LaunchMode.externalApplication);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    widget.controller.load().then((_) {
      if (widget.controller.active != null) {
        widget.controller.refreshBalance();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TripoAccountCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.scanClipboard();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _creditText(double? value) {
    if (value == null) return '—';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final active = controller.active;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.key_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active == null ? 'ربط حساب Tripo' : active.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (controller.busy)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (active == null)
              const Text(
                'افتح Tripo في Chrome، سجّل الدخول يدويًا، أنشئ API Key واضغط Copy، ثم ارجع للتطبيق.',
              )
            else ...[
              Text('المفتاح: ${active.maskedKey}'),
              Text(
                'الرصيد: ${_creditText(active.balance)}  •  المحجوز: ${_creditText(active.frozen)}',
              ),
            ],
            if (controller.candidateKey != null) ...[
              const SizedBox(height: 10),
              const Text(
                'تم العثور على مفتاح Tripo منسوخ. هل تريد فحصه وتفعيله؟',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.confirmCandidate(),
                      child: const Text('فحص وتفعيل'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: controller.dismissCandidate,
                    child: const Text('تجاهل'),
                  ),
                ],
              ),
            ],
            if (controller.errorCode != null) ...[
              const SizedBox(height: 8),
              Text(
                switch (controller.errorCode) {
                  'invalid_key' => 'المفتاح غير صالح أو تعذر التحقق منه.',
                  'balance_failed' => 'تعذر تحديث رصيد Tripo.',
                  'browser_open_failed' => 'تعذر فتح Tripo في Chrome.',
                  _ => 'تعذر إكمال عملية حساب Tripo.',
                },
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: controller.busy
                      ? null
                      : controller.openTripoConsole,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('فتح Tripo في Chrome'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.busy
                      ? null
                      : controller.scanClipboard,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('استيراد المفتاح المنسوخ'),
                ),
                if (active != null)
                  IconButton(
                    tooltip: 'تحديث الرصيد',
                    onPressed:
                        controller.busy ? null : controller.refreshBalance,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            if (controller.saved.length > 1) ...[
              const Divider(),
              Text(
                'الحسابات المحفوظة',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              ...controller.saved.map(
                (credential) => RadioListTile<String>(
                  value: credential.fingerprint,
                  groupValue: active?.fingerprint,
                  title: Text(credential.name),
                  subtitle: Text(credential.maskedKey),
                  onChanged: controller.busy
                      ? null
                      : (value) {
                          if (value != null) controller.activate(value);
                        },
                  secondary: IconButton(
                    tooltip: 'حذف من هذا الجهاز',
                    onPressed: controller.busy
                        ? null
                        : () => controller.deleteCredential(
                              credential.fingerprint,
                            ),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
