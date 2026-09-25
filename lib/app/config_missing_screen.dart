import 'package:flutter/material.dart';

import '../core/errors/arabic_messages.dart';
import '../core/theme/colors.dart';
import '../core/widgets/empty_state.dart';

/// Shown when the build has no usable backend configuration (missing or
/// non-HTTPS `API_BASE_URL`, missing `DEVICE_KEY`). Nothing is sent to any
/// server from this state — in particular no PIN and no device key.
class ConfigMissingScreen extends StatelessWidget {
  const ConfigMissingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: EmptyState(
          icon: Icons.settings_outlined,
          title: ArabicMessages.appTitle,
          body: ArabicMessages.appNotConfigured,
        ),
      ),
    );
  }
}
