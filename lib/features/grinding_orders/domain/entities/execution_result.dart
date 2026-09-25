import 'grinding_order.dart';

/// `POST /orders/{id}/start|complete` success (contract §4.2).
class ExecutionResult {
  const ExecutionResult({required this.order, required this.replayed});

  /// The server's updated order. `null` only when a 2xx `success:true`
  /// response carried an unreadable `data` — the server committed the
  /// command, so the app treats it as done and re-checks for the truth
  /// (it never fabricates an order).
  final GrindingOrder? order;

  /// `true` when this exact request had already succeeded (a retry). Shown
  /// exactly like a first success.
  final bool replayed;
}
