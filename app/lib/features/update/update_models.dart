/// One APK of a release, built for one processor type.
class ReleaseFile {
  const ReleaseFile({required this.path, required this.sha256, required this.size});

  final String path;
  final String sha256;
  final int size;

  factory ReleaseFile.fromJson(Map<String, dynamic> json) => ReleaseFile(
        path: json['path'] as String,
        sha256: json['sha256'] as String,
        size: (json['size'] as num).toInt(),
      );

  /// Rounded up, for "the update is 28 MB".
  int get megabytes => (size / (1024 * 1024)).ceil();
}

/// The newest published version, and the oldest build still allowed to run.
class AppRelease {
  const AppRelease({required this.build, required this.version, required this.notes, required this.minBuild, required this.files});

  final int build;
  final String version;
  final String notes;
  final int minBuild;

  /// Keyed by Android ABI name, such as arm64-v8a.
  final Map<String, ReleaseFile> files;

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        build: (json['build'] as num).toInt(),
        version: json['version'] as String,
        notes: json['notes'] as String? ?? '',
        minBuild: (json['min_build'] as num?)?.toInt() ?? 0,
        files: {
          for (final entry in (json['files'] as Map<String, dynamic>).entries)
            entry.key: ReleaseFile.fromJson(entry.value as Map<String, dynamic>),
        },
      );
}

/// A newer version this phone can install.
class AvailableUpdate {
  const AvailableUpdate({required this.release, required this.file, required this.required});

  final AppRelease release;
  final ReleaseFile file;

  /// This build is older than a mandatory release: the app cannot be used until updated.
  final bool required;
}

/// What, if anything, to offer a phone running [currentBuild] on [abi]. Development
/// builds (0) are never offered updates, and a release without a file for this
/// phone's processor is skipped rather than offering one that would not install.
AvailableUpdate? updateFor(AppRelease? release, {required int currentBuild, required String abi}) {
  if (release == null || currentBuild <= 0 || release.build <= currentBuild) return null;
  final file = release.files[abi];
  if (file == null) return null;
  return AvailableUpdate(release: release, file: file, required: currentBuild < release.minBuild);
}

enum UpdateFailure {
  network('تعذّر تنزيل التحديث. تأكد من الإنترنت ثم حاول مرة أخرى.'),
  damaged('وصل ملف التحديث ناقصاً أو تالفاً، فلم نثبّته. حاول مرة أخرى.'),
  installBlocked('اسمح لتطبيق ZAD بتثبيت التحديثات من الإعدادات، ثم اضغط "ثبّت" مرة أخرى.');

  const UpdateFailure(this.message);

  final String message;
}

class UpdateException implements Exception {
  const UpdateException(this.failure);

  final UpdateFailure failure;
}
