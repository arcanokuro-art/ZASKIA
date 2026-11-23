import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AndroidTablet extends StatelessWidget {
  const AndroidTablet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final display = View.of(context).display;
    final shortestSide = display.size.shortestSide / display.devicePixelRatio;
    if (defaultTargetPlatform == TargetPlatform.linux ||
        (defaultTargetPlatform == TargetPlatform.android && shortestSide >= 600)) {
      return child;
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Esta versión de ZASKIA está diseñada para tablets Android.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
