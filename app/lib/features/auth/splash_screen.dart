import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'auth_models.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unavailable = ref.watch(authControllerProvider) is AuthUnavailable;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: unavailable
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'تعذّر الاتصال. تأكد من الإنترنت ثم حاول مرة أخرى.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => ref.read(authControllerProvider.notifier).retry(),
                      child: const Text('حاول مرة أخرى'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(semanticsLabel: 'جارٍ التحميل'),
        ),
      ),
    );
  }
}
