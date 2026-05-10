import 'package:flutter/material.dart';
import 'MainMenu.dart';
import 'LobbyScreen.dart';
import 'WebSocketClient.dart';

void main() {
  runApp(const DuckRoyaleApp());
}

class DuckRoyaleApp extends StatelessWidget {
  const DuckRoyaleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Duck Royale',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const MainMenu(),
      onGenerateRoute: (settings) {
        if (settings.name == '/lobby') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(builder: (_) => LobbyScreen(
            client: args['client'] as GameWebSocketClient,
            playerName: args['playerName'] as String,
          ));
        }
        return null;
      },
    );
  }
}
