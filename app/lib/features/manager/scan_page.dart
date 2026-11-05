import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme.dart';
import 'manager_models.dart';
import 'manager_repository.dart';

/// Builds the live camera view. Tests replace it, since they have no camera.
typedef CameraBuilder = Widget Function(BuildContext context, ValueChanged<String> onCode);

final scanCameraProvider = Provider<CameraBuilder>((ref) => (context, onCode) => _LiveCamera(onCode: onCode));

class _LiveCamera extends StatefulWidget {
  const _LiveCamera({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_LiveCamera> createState() => _LiveCameraState();
}

class _LiveCameraState extends State<_LiveCamera> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (value != null) widget.onCode(value);
      },
      errorBuilder: (context, error) => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'تعذّر فتح الكاميرا. اسمح للتطبيق باستخدامها من إعدادات الهاتف، أو استخدم الرمز الاحتياطي.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: AppColors.surface),
          ),
        ),
      ),
    );
  }
}

const _deliverColor = Color(0xFF0B6B4F);
const _refuseColor = Color(0xFFA61B12);
const _waitColor = Color(0xFFA15C00);
const _scanGround = Color(0xFF0B1F1C);

class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  final _code = TextEditingController();
  ScanResult? _result;
  bool _busy = false;
  bool _failed = false;
  int _delivered = 0;

  // Repeats a request that lost its connection, with the same key so it cannot count twice.
  Future<ScanResult> Function(String key)? _pending;
  String _key = const Uuid().v4();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Every new scan gets a new key: seeing the same code again must answer "already
  /// collected", and never repeat a stored "deliver".
  Future<void> _begin(Future<ScanResult> Function(String key) request) async {
    if (_busy || _result != null || _failed) return;
    _key = const Uuid().v4();
    _pending = request;
    await _run();
  }

  Future<void> _run() async {
    final request = _pending;
    if (request == null) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await request(_key);
      if (!mounted) return;
      if (result.ok) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.heavyImpact();
      }
      setState(() {
        _result = result;
        if (result.ok) _delivered++;
        _busy = false;
      });
    } on ManagerFailure {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _failed = true;
        _busy = false;
      });
    }
  }

  void _next() {
    _code.clear();
    setState(() {
      _result = null;
      _failed = false;
      _pending = null;
    });
  }

  void _submitCode() {
    final code = _code.text.trim();
    if (code.length != 6) return;
    final repository = ref.read(managerRepositoryProvider);
    FocusScope.of(context).unfocus();
    _begin((key) => repository.redeemCode(code, key));
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(managerRepositoryProvider);
    final result = _result;
    return Scaffold(
      backgroundColor: _scanGround,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'سلّمت: $_delivered',
                          key: const Key('scan-count'),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.surface),
                        ),
                      ),
                      TextButton(
                        key: const Key('scan-close'),
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(backgroundColor: AppColors.surface, foregroundColor: AppColors.ink),
                        child: const Text('إنهاء'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: ref.read(scanCameraProvider)(context, (token) => _begin((key) => repository.redeemToken(token, key))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('وجّه الكاميرا إلى الباركود، أو اكتب الرمز الاحتياطي:', style: TextStyle(fontSize: 17, color: AppColors.surface)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('scan-code'),
                          controller: _code,
                          textDirection: TextDirection.ltr,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                          style: const TextStyle(fontSize: 22, color: AppColors.ink),
                          onSubmitted: (_) => _submitCode(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 92,
                        child: FilledButton(
                          key: const Key('scan-code-submit'),
                          onPressed: _submitCode,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(60),
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.ink,
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          child: const Text('تأكيد'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_busy) const ColoredBox(color: Color(0x88000000), child: Center(child: CircularProgressIndicator())),
            if (result != null)
              _ResultCover(
                color: switch (result.tone) {
                  ScanTone.deliver => _deliverColor,
                  ScanTone.refuse => _refuseColor,
                  ScanTone.wait => _waitColor,
                },
                title: result.title,
                line1: result.line1,
                line2: result.line2,
                button: 'المسح التالي',
                onPressed: _next,
              ),
            if (_failed)
              _ResultCover(
                color: _waitColor,
                title: 'لا تسلّم بعد',
                line1: 'تعذّر الاتصال',
                line2: 'تأكد من الإنترنت ثم أعد المحاولة',
                button: 'أعد المحاولة',
                onPressed: _run,
                secondary: _next,
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultCover extends StatelessWidget {
  const _ResultCover({required this.color, required this.title, required this.line1, required this.line2, required this.button, required this.onPressed, this.secondary});

  final Color color;
  final String title;
  final String line1;
  final String line2;
  final String button;
  final VoidCallback onPressed;
  final VoidCallback? secondary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, key: const Key('scan-title'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, height: 1.2, color: AppColors.surface)),
            const SizedBox(height: 14),
            Text(line1, key: const Key('scan-line1'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.surface)),
            const SizedBox(height: 8),
            Text(line2, key: const Key('scan-line2'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, color: AppColors.surface)),
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('scan-next'),
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(72),
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.ink,
                textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              child: Text(button),
            ),
            if (secondary != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: secondary,
                style: TextButton.styleFrom(foregroundColor: AppColors.surface, minimumSize: const Size.fromHeight(56)),
                child: const Text('تجاهل والمسح من جديد'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
