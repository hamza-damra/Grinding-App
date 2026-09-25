import '../entities/pending_command.dart';
import '../value_objects/grinding_command.dart';

/// Durable storage of pending START / COMPLETE idempotency records
/// (contract §4.4 — "Persist it before sending … app killed and restarted").
abstract class PendingCommandStore {
  /// Every readable record.
  Future<List<PendingCommand>> loadAll();

  /// Durably persists [command]. Completes only once the record would survive
  /// a process kill; throws otherwise — the caller must then NOT send.
  Future<void> save(PendingCommand command);

  /// Removes the record for [orderId] + [command] (missing is fine).
  Future<void> remove(int orderId, GrindingCommand command);
}
