import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:client_flutter/app_data.dart';
import 'package:client_flutter/network_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppData receives local multiplayer updates', () async {
    final AppData appData = AppData(
      initialConfig: const NetworkConfig(
        serverOption: ServerOption.local,
        playerName: 'TestProbe',
      ),
    );

    final Completer<void> completer = Completer<void>();
    late final void Function() listener;
    listener = () {
      if (appData.players.isNotEmpty) {
        completer.complete();
        appData.removeListener(listener);
      }
    };
    appData.addListener(listener);

    await completer.future.timeout(const Duration(seconds: 5));
    expect(appData.players, isNotEmpty);
    expect(appData.countdownSeconds, greaterThanOrEqualTo(0));

    appData.dispose();
  });
}
