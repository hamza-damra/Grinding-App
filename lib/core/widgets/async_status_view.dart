import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../errors/app_failure.dart';
import '../errors/arabic_messages.dart';
import '../errors/connection_failure.dart';
import '../errors/error_mapper.dart';
import '../theme/colors.dart';
import '../theme/dimensions.dart';
import 'app_connection_error_dialog.dart';
import 'connection_recovery_banner.dart';
import 'error_banner.dart';

/// Reusable async-state view (ported from the Operator App, without its
/// SSE-era network-recovery coordinator).
///
/// Recovery policy for a *technical* failure (timeout / no network / server
/// unavailable):
///   * the first settled failure of an episode does NOT show the dialog: a
///     short [AppConfig.connectionErrorGrace] runs ONE silent auto-retry of
///     [onRetry] (a stale socket after a resume usually recovers at once);
///   * cached data stays on screen behind a non-blocking
///     [ConnectionRecoveryBanner] — the worker is never blocked when the app
///     can continue;
///   * the blocking [AppConnectionErrorDialog] appears only when the silent
///     retry failed AND there is no data to show.
///
/// A *business* failure with no previous data renders a compact inline
/// [ErrorBanner] with the Arabic copy.
class AsyncStatusView<T> extends StatefulWidget {
  const AsyncStatusView({
    required this.value,
    required this.onRetry,
    required this.data,
    this.loading,
    super.key,
  });

  final AsyncValue<T> value;

  /// Re-runs the original load and **throws on failure**, e.g.
  /// `() => ref.refresh(provider.future)`.
  final Future<void> Function() onRetry;

  final Widget Function(T data) data;

  /// Defaults to a centered green spinner.
  final Widget Function()? loading;

  @override
  State<AsyncStatusView<T>> createState() => _AsyncStatusViewState<T>();
}

class _AsyncStatusViewState<T> extends State<AsyncStatusView<T>> {
  bool _dialogOpen = false;
  bool _userDismissed = false;
  bool _graceActive = false;
  bool _autoRetried = false;
  Timer? _graceTimer;

  @override
  void dispose() {
    _graceTimer?.cancel();
    super.dispose();
  }

  AppFailure _failureOf(AsyncValue<T> v) {
    final err = v.error ?? const UnknownFailure();
    return err is AppFailure
        ? err
        : ErrorMapper.fromException(err, v.stackTrace);
  }

  /// Mutates guards directly (never `setState`) because it runs from
  /// `build`; the rebuild comes from the timer's `setState` or the
  /// provider's next emission.
  void _startGrace() {
    _graceActive = true;
    _graceTimer?.cancel();
    _graceTimer = Timer(AppConfig.connectionErrorGrace, () async {
      _graceTimer = null;
      if (!mounted) {
        _graceActive = false;
        _autoRetried = true;
        return;
      }
      try {
        await widget.onRetry();
      } catch (_) {
        // The re-emitted AsyncError drives the next decision.
      } finally {
        if (mounted) {
          setState(() {
            _graceActive = false;
            _autoRetried = true;
          });
        } else {
          _graceActive = false;
          _autoRetried = true;
        }
      }
    });
  }

  Future<void> _openDialog() async {
    if (!mounted) {
      _dialogOpen = false;
      return;
    }
    final result = await showConnectionErrorDialog(
      context,
      onRetry: widget.onRetry,
    );
    if (!mounted) {
      _dialogOpen = false;
      return;
    }
    setState(() {
      _dialogOpen = false;
      if (result != true) _userDismissed = true;
    });
  }

  void _resetEpisode() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _graceActive = false;
    _autoRetried = false;
    _userDismissed = false;
  }

  Widget _loading() =>
      widget.loading?.call() ??
      const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );

  Widget _compactBanner(String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ErrorBanner(message: message, onRetry: onRetry),
      ),
    );
  }

  Widget _withRecoveryBanner(Widget child) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ConnectionRecoveryBanner(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final settledError = value.hasError && !value.isLoading;
    final settledSuccess =
        value.hasValue && !value.isLoading && !value.hasError;
    final failure = settledError ? _failureOf(value) : null;
    final isTechnical = failure != null && isConnectionFailure(failure);

    if (settledSuccess) _resetEpisode();

    if (isTechnical && !_dialogOpen && !_userDismissed) {
      if (!_autoRetried && !_graceActive) {
        _startGrace();
      } else if (_autoRetried && !_graceActive && !value.hasValue) {
        _dialogOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _openDialog());
      }
    }

    if (value.hasValue) {
      final body = widget.data(value.requireValue);
      final recovering = _graceActive || isTechnical;
      return recovering ? _withRecoveryBanner(body) : body;
    }
    if (value.isLoading) return _loading();
    if (isTechnical) {
      if (_dialogOpen) return const SizedBox.expand();
      if (_graceActive || !_autoRetried) return _loading();
      return _userDismissed
          ? _compactBanner(
              ArabicMessages.forFailure(failure),
              () => setState(() => _userDismissed = false),
            )
          : const SizedBox.expand();
    }
    return _compactBanner(
      ArabicMessages.forFailure(failure!),
      () => unawaited(widget.onRetry().catchError((_) {})),
    );
  }
}
