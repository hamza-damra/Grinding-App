import 'package:flutter/material.dart';

/// Minimal splash that holds the screen while the auth controller resolves
/// its initial state. The real redirect happens in `router.dart`.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset('assets/images/icon.jpg', width: 200, height: 200),
      ),
    );
  }
}
