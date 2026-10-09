// Generate SDK-matched Android scaffolding without overwriting app source.
// Run: dart run tool/bootstrap.dart
import 'dart:io';

Future<void> main() async {
  final root = Directory.current;
  if (!File('pubspec.yaml').existsSync() || !File('lib/main.dart').existsSync()) {
    stderr.writeln('Run this from the android-app directory.'); exitCode = 1; return;
  }
  if (Directory('android').existsSync()) {
    stdout.writeln('Android scaffolding already exists. App source preserved.'); return;
  }
  final temporary = await Directory.systemTemp.createTemp('silong-android-');
  try {
    final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
    final result = await Process.run(executable, ['create', '--platforms=android', '--org=edu.silong', '--project-name=silong_hamuros', '--no-pub', '${temporary.path}/generated'], runInShell: Platform.isWindows);
    stdout.write(result.stdout); stderr.write(result.stderr);
    if (result.exitCode != 0) {exitCode = result.exitCode; return;}
    final source = Directory('${temporary.path}/generated/android');
    for (final entity in source.listSync(recursive: true, followLinks: false)) {
      final relative = entity.path.substring(source.path.length + 1);
      final target = '${root.path}/android/$relative';
      if (entity is Directory) { await Directory(target).create(recursive: true); }
      if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
    // Native launcher display name. Generated identifiers match project name.
    final manifest = File('${root.path}/android/app/src/main/AndroidManifest.xml');
    final xml = await manifest.readAsString();
    await manifest.writeAsString(xml.replaceAll('android:label="silong_hamuros"', 'android:label="Silong Hamuros"'));
    await File('${temporary.path}/generated/.metadata').copy('${root.path}/.metadata');
    if (!Platform.isWindows) await Process.run('chmod', ['+x', '${root.path}/android/gradlew']);
    stdout.writeln('Android project generated. Run flutter pub get, flutter analyze, flutter test, then flutter run.');
  } on ProcessException catch (e) {
    stderr.writeln('Flutter could not run: $e. Install Flutter and add its bin directory to PATH.'); exitCode = 1;
  } finally { await temporary.delete(recursive: true); }
}
