import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rms/core/theme.dart';
import 'package:rms/features/update/app_updater.dart';
import 'package:rms/features/update/update_models.dart';
import 'package:rms/features/update/update_ui.dart';

const _file = ReleaseFile(path: '40/zad-arm64-v8a.apk', sha256: 'abc', size: 28 * 1024 * 1024);

AppRelease _release({int build = 40, int minBuild = 0, Map<String, ReleaseFile> files = const {'arm64-v8a': _file}}) =>
    AppRelease(build: build, version: '1.0.0', notes: 'حجز أسرع من حجوزاتي', minBuild: minBuild, files: files);

class FakeUpdater implements AppUpdater {
  FakeUpdater({this.currentBuild = 30, this.release});

  @override
  final int currentBuild;

  @override
  String get currentVersion => '1.0.0';

  @override
  String get abi => 'arm64-v8a';

  AppRelease? release;
  int downloads = 0;
  final installs = <String>[];

  /// Completed by the test, to look at the screen mid-download.
  Completer<void>? holdDownload;
  UpdateFailure? failDownload;
  UpdateFailure? failInstall;

  @override
  Future<AppRelease?> latest() async => release;

  @override
  Future<String> download(ReleaseFile file, void Function(double progress) onProgress) async {
    downloads++;
    onProgress(0.5);
    await holdDownload?.future;
    final failure = failDownload;
    failDownload = null;
    if (failure != null) throw UpdateException(failure);
    onProgress(1);
    return '/cache/zad-update.apk';
  }

  @override
  Future<void> install(String path) async {
    installs.add(path);
    final failure = failInstall;
    failInstall = null;
    if (failure != null) throw UpdateException(failure);
  }
}

Future<void> _pump(WidgetTester tester, FakeUpdater updater, Widget child) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [appUpdaterProvider.overrideWithValue(updater)],
    child: MaterialApp(
      theme: appTheme(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('what is offered', () {
    test('a newer release with a file for this phone', () {
      final update = updateFor(_release(), currentBuild: 30, abi: 'arm64-v8a');
      expect(update?.file.path, '40/zad-arm64-v8a.apk');
      expect(update?.required, isFalse);
    });

    test('nothing when already up to date, or in a development build', () {
      expect(updateFor(_release(), currentBuild: 40, abi: 'arm64-v8a'), isNull);
      expect(updateFor(_release(), currentBuild: 45, abi: 'arm64-v8a'), isNull);
      expect(updateFor(_release(), currentBuild: 0, abi: 'arm64-v8a'), isNull);
      expect(updateFor(null, currentBuild: 30, abi: 'arm64-v8a'), isNull);
    });

    test('nothing that would not install on this processor', () {
      expect(updateFor(_release(), currentBuild: 30, abi: 'armeabi-v7a'), isNull);
    });

    test('required when older than a mandatory release', () {
      expect(updateFor(_release(minBuild: 35), currentBuild: 30, abi: 'arm64-v8a')?.required, isTrue);
      expect(updateFor(_release(minBuild: 35), currentBuild: 36, abi: 'arm64-v8a')?.required, isFalse);
    });

    test('reads a release as the server sends it', () {
      final release = AppRelease.fromJson({
        'build': 40,
        'version': '1.0.0',
        'notes': 'جديد',
        'min_build': 12,
        'published_at': '2026-11-08T10:00:00Z',
        'files': {
          'arm64-v8a': {'path': '40/zad-arm64-v8a.apk', 'sha256': 'abc', 'size': 1000},
        },
      });
      expect(release.minBuild, 12);
      expect(release.files['arm64-v8a']?.sha256, 'abc');
    });
  });

  group('banner', () {
    testWidgets('appears when a newer version exists and opens the details', (tester) async {
      await _pump(tester, FakeUpdater(release: _release()), const UpdateBanner());
      expect(find.byKey(const Key('update-banner')), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-open')));
      await tester.pumpAndSettle();
      expect(find.text('حجز أسرع من حجوزاتي'), findsOneWidget);
      expect(find.text('حجم التحديث 28 ميغابايت'), findsOneWidget);
    });

    testWidgets('stays away when up to date', (tester) async {
      await _pump(tester, FakeUpdater(currentBuild: 40, release: _release()), const UpdateBanner());
      expect(find.byKey(const Key('update-banner')), findsNothing);
    });
  });

  group('download and install', () {
    final update = updateFor(_release(), currentBuild: 30, abi: 'arm64-v8a')!;

    testWidgets('shows progress, then opens the installer', (tester) async {
      final updater = FakeUpdater()..holdDownload = Completer<void>();
      await _pump(tester, updater, UpdatePanel(update: update, closable: true));
      await tester.tap(find.byKey(const Key('update-start')));
      await tester.pump();
      expect(find.byKey(const Key('update-progress')), findsOneWidget);
      expect(find.text('جارٍ التنزيل 50٪'), findsOneWidget);

      updater.holdDownload!.complete();
      await tester.pumpAndSettle();
      expect(updater.installs, ['/cache/zad-update.apk']);
      expect(find.byKey(const Key('update-opened')), findsOneWidget);
    });

    testWidgets('a damaged file is never installed, and can be fetched again', (tester) async {
      final updater = FakeUpdater()..failDownload = UpdateFailure.damaged;
      await _pump(tester, updater, UpdatePanel(update: update, closable: true));
      await tester.tap(find.byKey(const Key('update-start')));
      await tester.pumpAndSettle();
      expect(find.text(UpdateFailure.damaged.message), findsOneWidget);
      expect(updater.installs, isEmpty);

      await tester.tap(find.byKey(const Key('update-start')));
      await tester.pumpAndSettle();
      expect(updater.downloads, 2);
      expect(updater.installs, hasLength(1));
    });

    testWidgets('after allowing installs in settings it installs without downloading again', (tester) async {
      final updater = FakeUpdater()..failInstall = UpdateFailure.installBlocked;
      await _pump(tester, updater, UpdatePanel(update: update, closable: true));
      await tester.tap(find.byKey(const Key('update-start')));
      await tester.pumpAndSettle();
      expect(find.text(UpdateFailure.installBlocked.message), findsOneWidget);
      expect(find.text('ثبّت'), findsOneWidget);

      await tester.tap(find.byKey(const Key('update-start')));
      await tester.pumpAndSettle();
      expect(updater.downloads, 1);
      expect(updater.installs, hasLength(2));
    });

    testWidgets('a required update cannot be put off', (tester) async {
      final required = updateFor(_release(minBuild: 35), currentBuild: 30, abi: 'arm64-v8a')!;
      await _pump(tester, FakeUpdater(), SizedBox(height: 2000, child: UpdateRequiredScreen(update: required)));
      expect(find.text('يجب تحديث التطبيق'), findsOneWidget);
      expect(find.byKey(const Key('update-start')), findsOneWidget);
      expect(find.byKey(const Key('update-later')), findsNothing);
    });
  });

  group('version row', () {
    testWidgets('shows this version and says when it is the newest', (tester) async {
      await _pump(tester, FakeUpdater(currentBuild: 40, release: _release()), const AppVersionRow());
      expect(find.text('الإصدار 1.0.0 (40)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update-check')));
      await tester.pumpAndSettle();
      expect(find.text('لديك أحدث إصدار.'), findsOneWidget);
    });

    testWidgets('opens the update when one is found', (tester) async {
      await _pump(tester, FakeUpdater(release: _release()), const AppVersionRow());
      await tester.tap(find.byKey(const Key('update-check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('update-start')), findsOneWidget);
    });
  });
}
