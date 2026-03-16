import 'package:flutter/material.dart';

void main() {
  runApp(const EvernightSealApp());
}

class EvernightSealApp extends StatelessWidget {
  const EvernightSealApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(),
    );
  }
}
