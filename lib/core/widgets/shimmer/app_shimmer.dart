import 'package:flutter/material.dart';
import '../../theme/colors.dart';

/// A wrapper that applies a sweeping gradient animation across all its children.
/// Used to create the skeleton loading "shimmer" effect.
///
/// Uses an [InheritedWidget] to share a single [AnimationController] with its
/// [SkeletonBone] descendants, avoiding expensive per-bone animations.
/// The animation is driven by a right-to-left [LinearGradient] to match
/// the RTL Arabic UI layout.
class AppShimmer extends StatefulWidget {
  const AppShimmer({
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
    super.key,
  });

  final Widget child;
  final Duration duration;

  @override
  State<AppShimmer> createState() => AppShimmerState();

  static AppShimmerState? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.state;
  }
}

class AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ExcludeSemantics so screen readers don't try to read the placeholder
    // structures (which often use text nodes with invisible content for sizing).
    return ExcludeSemantics(
      child: _ShimmerScope(
        state: this,
        animationValue: _controller.value,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) {
                return _buildGradient().createShader(bounds);
              },
              child: child,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }

  LinearGradient _buildGradient() {
    final value = _controller.value;
    // Right to left animation for RTL layout
    return LinearGradient(
      colors: const [
        AppColors.disabledBg,
        AppColors.divider, // Highlight
        AppColors.disabledBg,
      ],
      stops: const [0.1, 0.5, 0.9],
      begin: const Alignment(1.0, 0.0),
      end: const Alignment(-1.0, 0.0),
      // Move the gradient from far right to far left
      transform: _SlidingGradientTransform(slidePercent: 1.0 - value),
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({
    required this.state,
    required this.animationValue,
    required super.child,
  });

  final AppShimmerState state;
  final double animationValue;

  @override
  bool updateShouldNotify(_ShimmerScope oldWidget) {
    return animationValue != oldWidget.animationValue;
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    // The slidePercent goes from 1.0 (start) down to 0.0 (end) since we sweep RTL.
    // We map 1.0 -> width, 0.0 -> -width
    final w = bounds.width;
    final translate = (slidePercent * 2 - 1) * w;
    return Matrix4.translationValues(translate, 0.0, 0.0);
  }
}
