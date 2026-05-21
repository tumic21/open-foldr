import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/core/client_identity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final testFile = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}open_foldr_test${Platform.pathSeparator}client_identity.json',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    if (await testFile.exists()) {
      await testFile.delete();
    }
  });

  test('load returns a stable identity across calls', () async {
    final first = await ClientIdentityStore.load();
    final second = await ClientIdentityStore.load();

    expect(first.id, isNotEmpty);
    expect(first.name, isNotEmpty);
    expect(second.id, first.id);
    expect(second.name, first.name);
  });

  test('load restores identity from legacy shared preferences fallback', () async {
    SharedPreferences.setMockInitialValues({
      'client_identity': '{"id":"device-123","name":"Android Phone"}',
    });

    final identity = await ClientIdentityStore.load();

    expect(identity.id, 'device-123');
    expect(identity.name, 'Android Phone');
  });
}
