import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import 'update_models.dart';

/// Finds, downloads and hands new versions to Android's installer. The app is not
/// on the Play Store, so it updates itself from the releases the team publishes.
abstract class AppUpdater {
  int get currentBuild;
  String get currentVersion;

  /// The Android ABI this copy of the app runs as, which picks the file to download.
  String get abi;

  Future<AppRelease?> latest();

  /// Saves the file and checks its fingerprint; reports progress from 0 to 1.
  Future<String> download(ReleaseFile file, void Function(double progress) onProgress);

  /// Opens Android's install screen; the person confirms there.
  Future<void> install(String path);
}

final appUpdaterProvider = Provider<AppUpdater>((ref) => SupabaseAppUpdater());

class SupabaseAppUpdater implements AppUpdater {
  // Reached only when checking or downloading, so showing the version never needs a
  // connected client.
  SupabaseClient get _client => Supabase.instance.client;

  @override
  int get currentBuild => AppConfig.appBuild;

  @override
  String get currentVersion => AppConfig.appVersion;

  @override
  String get abi => switch (Abi.current()) {
        Abi.androidArm64 => 'arm64-v8a',
        Abi.androidArm => 'armeabi-v7a',
        Abi.androidX64 => 'x86_64',
        _ => 'unknown',
      };

  @override
  Future<AppRelease?> latest() async {
    final json = await _client.rpc('latest_app_release');
    return json == null ? null : AppRelease.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<String> download(ReleaseFile file, void Function(double progress) onProgress) async {
    final url = _client.storage.from('app-releases').getPublicUrl(file.path);
    final target = File('${(await getTemporaryDirectory()).path}/zad-update.apk');
    final http = HttpClient();
    try {
      final response = await (await http.getUrl(Uri.parse(url))).close();
      if (response.statusCode != 200) throw const UpdateException(UpdateFailure.network);
      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(file.size == 0 ? 0 : (received / file.size).clamp(0.0, 1.0).toDouble());
        }
      } finally {
        await sink.close();
      }
    } on UpdateException {
      rethrow;
    } on IOException {
      throw const UpdateException(UpdateFailure.network);
    } finally {
      http.close();
    }
    // A cut connection or a tampered file must never reach the installer.
    final digest = await sha256.bind(target.openRead()).first;
    if (digest.toString() != file.sha256) {
      await target.delete();
      throw const UpdateException(UpdateFailure.damaged);
    }
    return target.path;
  }

  @override
  Future<void> install(String path) async {
    final result = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
    if (result.type == ResultType.permissionDenied) throw const UpdateException(UpdateFailure.installBlocked);
    if (result.type != ResultType.done) throw const UpdateException(UpdateFailure.damaged);
  }
}
