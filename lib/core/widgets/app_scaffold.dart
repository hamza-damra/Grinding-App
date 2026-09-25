import 'package:flutter/material.dart';

import '../theme/colors.dart';
import 'connectivity_banner.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.body,
    this.appBar,
    this.bottomBar,
    this.padding,
    this.showConnectivityBanner = true,
    this.backgroundColor,
    super.key,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomBar;
  final EdgeInsetsGeometry? padding;
  final bool showConnectivityBanner;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.scaffoldBg,
      appBar: appBar,
      bottomNavigationBar: bottomBar,
      body: SafeArea(
        child: Column(
          children: [
            if (showConnectivityBanner) const ConnectivityBanner(),
            Expanded(
              child: padding != null
                  ? Padding(padding: padding!, child: body)
                  : body,
            ),
          ],
        ),
      ),
    );
  }
}
