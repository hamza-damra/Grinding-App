import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// In-process fake of the Grinding App backend (contract §4), plugged in as
/// the Dio [HttpClientAdapter] behind the REAL interceptor chain
/// (`ApiClient.buildDio`). It implements the contract's state machine:
///
/// * device-key check (401 without an envelope);
/// * PIN login, `/sessions/me`, tolerant logout, session codes (§4.3);
/// * `/check` incl. the smart Roll/Pallet resolution (auto-resolve, the
///   409 selection when both items are actionable), NOT_ELIGIBLE, 12-digit
///   validation;
/// * queues;
/// * START / COMPLETE with the idempotency table (§4.4): the same
///   `clientRequestId` for the same order + command → `replayed:true`; for a
///   different order / command → `GRINDING_IDEMPOTENCY_KEY_REUSED`;
/// * the biometric login gate (biometric handoff §4): `BIOMETRIC_*` 403s on
///   login with attempt tokens, and the attempt-status long-poll (held while
///   nothing changes, answered as soon as a scan / admin / terminal change
///   arrives, 410 once the attempt expired). OFF by default, like the real
///   backend, so every other test sees the login unchanged.
///
/// Every request is recorded ([requests]); [faults] inject transport-level
/// failures (lost response after commit, timeouts, 5xx, captive portal,
/// device rejection, hang).
class FakeGrindingBackend implements HttpClientAdapter {
  FakeGrindingBackend({
    this.deviceKey = testDeviceKey,
    this.now = '2026-09-22T09:41:07.312Z',
    this.sessionExpiresAt = '2026-09-22T21:41:07.312Z',
  });

  static const String testDeviceKey = 'test-device-key';
  static const String base = '/api/v1/grinding-app';

  final String deviceKey;
  String now;
  String sessionExpiresAt;

  final Map<String, FakeWorker> _workersByPin = <String, FakeWorker>{};
  final Map<String, FakeSession> sessions = <String, FakeSession>{};
  final Map<int, FakeOrder> orders = <int, FakeOrder>{};
  final Map<String, List<FakeSource>> _sources = <String, List<FakeSource>>{};
  final Map<String, FakeIdempotencyEntry> idempotency =
      <String, FakeIdempotencyEntry>{};
  final Map<int, int> _transitions = <int, int>{};

  final List<RecordedRequest> requests = <RecordedRequest>[];
  final List<FakeFault> faults = <FakeFault>[];

  /// Runs for every request after it was recorded, before it is handled.
  Future<void> Function(RecordedRequest request)? onRequest;

  /// Runs after a START / COMPLETE was committed, before the response is
  /// returned (process-kill tests kill the app here).
  Future<void> Function(RecordedRequest request)? onCommitted;

  int _tokenSeq = 0;
  int _sessionSeq = 300;

  // ── Biometric login gate ──────────────────────────────────────────────

  static const String biometricStatusPath =
      '/api/v1/auth/biometric/login-attempts/status';

  bool _biometricEnforced = false;
  bool _biometricAgentOnline = true;
  bool _biometricTerminalOnline = true;

  /// `false` → refusals carry no attempt (`attemptAvailable:false`).
  bool biometricAttemptsAvailable = true;

  final Map<String, FakeBiometricAttempt> biometricAttempts =
      <String, FakeBiometricAttempt>{};

  /// Held long-polls the client aborted (cancel / close / resume).
  int biometricPollsAborted = 0;
  int _attemptSeq = 0;
  Completer<void> _biometricChange = Completer<void>();

  // ── Seeding ───────────────────────────────────────────────────────────

  FakeWorker addWorker({
    required String pin,
    required int operatorId,
    required String name,
    bool allowed = true,
  }) {
    final worker = FakeWorker(
      pin: pin,
      operatorId: operatorId,
      name: name,
      allowed: allowed,
    );
    _workersByPin[pin] = worker;
    return worker;
  }

  FakeWorker? workerById(int operatorId) {
    for (final worker in _workersByPin.values) {
      if (worker.operatorId == operatorId) return worker;
    }
    return null;
  }

  FakeOrder addOrder({
    required int id,
    required String identifier,
    String sourceType = 'ROLL',
    String status = 'READY_FOR_GRINDING',
    String? orderNumber,
    String sourceOrigin = 'ROLL_PRODUCTION_SCRAP',
    String? materialName = 'رول أبيض 0.8',
    Object? expectedWeightKg = 40.0,
    Object? sourceQuantity,
    String? lineName,
    bool directScrap = true,
    bool legacy = false,
    String? startedByName,
    String? startedAt,
    String? completedByName,
    String? completedAt,
  }) {
    final order = FakeOrder(
      id: id,
      orderNumber: orderNumber ?? 'GR-${id.toString().padLeft(6, '0')}',
      status: status,
      sourceType: sourceType,
      sourceOrigin: sourceOrigin,
      sourceIdentifier: identifier,
      materialName: materialName,
      expectedWeightKg: expectedWeightKg,
      sourceQuantity: sourceQuantity,
      lineName: lineName,
      directScrap: directScrap,
      legacy: legacy,
      startedByName: startedByName,
      startedAt: startedAt,
      completedByName: completedByName,
      completedAt: completedAt,
      createdAt: '2026-09-22T08:12:44.019Z',
    );
    orders[id] = order;
    _sources
        .putIfAbsent(identifier, () => <FakeSource>[])
        .add(FakeSource(identifier, sourceType, orderId: id));
    return order;
  }

  /// A roll / pallet without a grinding order (`NOT_ELIGIBLE`).
  void addNotEligible({
    required String identifier,
    String sourceType = 'PALLET',
    Map<String, dynamic>? details,
  }) {
    _sources
        .putIfAbsent(identifier, () => <FakeSource>[])
        .add(FakeSource(identifier, sourceType, details: details));
  }

  /// Seeds an active session (as if the worker logged in earlier).
  String issueSession(int operatorId) {
    final token = 'tok-$operatorId-${++_tokenSeq}';
    sessions[token] = FakeSession(
      token: token,
      operatorId: operatorId,
      sessionId: ++_sessionSeq,
    );
    return token;
  }

  /// Marks [clientRequestId] as already committed for [orderId] + [command]
  /// (e.g. the previous process committed it right before it was killed).
  void seedIdempotency(String clientRequestId, int orderId, String command) {
    idempotency[clientRequestId] = FakeIdempotencyEntry(orderId, command);
  }

  void expireSession(String token) => sessions[token]?.expired = true;

  void endSession(String token) => sessions[token]?.ended = true;

  void revokeWorker(int operatorId) => workerById(operatorId)?.allowed = false;

  /// The PIN was changed elsewhere: the old one no longer logs in.
  void changePin(int operatorId, String newPin) {
    final worker = workerById(operatorId)!;
    _workersByPin
      ..remove(worker.pin)
      ..[newPin] = worker;
  }

  // Biometric gate — each change wakes the held status polls, as the real
  // long-poll answers "as soon as something changes".

  void setBiometricEnforced(bool enforced) {
    _biometricEnforced = enforced;
    _notifyBiometric();
  }

  /// The factory agent went offline → the check is suspended factory-wide.
  void setBiometricAgentOnline(bool online) {
    _biometricAgentOnline = online;
    _notifyBiometric();
  }

  /// The terminal went offline while the agent is up.
  void setBiometricTerminalOnline(bool online) {
    _biometricTerminalOnline = online;
    _notifyBiometric();
  }

  void scanFingerprint(int operatorId) =>
      _setPunch(operatorId, FakePunch.fresh);

  /// The last punch is older than the validity window.
  void ageFingerprint(int operatorId) =>
      _setPunch(operatorId, FakePunch.expired);

  void setBiometricMapping(int operatorId, FakeBiometricMapping mapping) {
    workerById(operatorId)!.mapping = mapping;
    _notifyBiometric();
  }

  void exemptFromBiometric(int operatorId) {
    workerById(operatorId)!.biometricExempt = true;
    _notifyBiometric();
  }

  /// Every open attempt is past its time: status answers 410.
  void expireBiometricAttempts() {
    for (final attempt in biometricAttempts.values) {
      attempt.expired = true;
    }
    _notifyBiometric();
  }

  List<RecordedRequest> get biometricStatusRequests =>
      requestsTo(biometricStatusPath);

  void _setPunch(int operatorId, FakePunch punch) {
    workerById(operatorId)!.punch = punch;
    _notifyBiometric();
  }

  void _notifyBiometric() {
    final change = _biometricChange;
    _biometricChange = Completer<void>();
    change.complete();
  }

  // ── Inspection ────────────────────────────────────────────────────────

  List<RecordedRequest> requestsTo(String pathSuffix, {String? method}) =>
      requests
          .where(
            (r) =>
                r.path.endsWith(pathSuffix) &&
                (method == null || r.method == method),
          )
          .toList();

  List<RecordedRequest> get commandRequests => requests
      .where((r) => r.path.endsWith('/start') || r.path.endsWith('/complete'))
      .toList();

  /// Number of real state transitions applied to [orderId].
  int transitionsFor(int orderId) => _transitions[orderId] ?? 0;

  String? activeTokenFor(int operatorId) {
    for (final session in sessions.values) {
      if (session.operatorId == operatorId && session.usable) {
        return session.token;
      }
    }
    return null;
  }

  // ── HttpClientAdapter ─────────────────────────────────────────────────

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = RecordedRequest(
      method: options.method.toUpperCase(),
      uri: options.uri,
      headers: Map<String, dynamic>.of(options.headers),
      body: options.data is Map
          ? Map<String, dynamic>.from(options.data as Map)
          : null,
      contentType: options.contentType,
      receiveTimeout: options.receiveTimeout,
    );
    requests.add(request);
    await onRequest?.call(request);

    final fault = _takeFault(request);
    if (fault != null) {
      switch (fault.kind) {
        case FaultKind.connectionError:
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'fake: connection refused',
          );
        case FaultKind.receiveTimeout:
          throw DioException.receiveTimeout(
            timeout: const Duration(seconds: 30),
            requestOptions: options,
          );
        case FaultKind.lostResponseAfterCommit:
          await _handle(request);
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'fake: response lost after commit',
          );
        case FaultKind.serverError:
          return _text(503, '<html>Service Unavailable</html>');
        case FaultKind.captivePortal:
          return _text(200, '<html>Wi-Fi login</html>');
        case FaultKind.deviceUnauthorized:
          return _text(401, 'Unauthorized');
        case FaultKind.hang:
          final release = fault.release ?? Completer<void>();
          await Future.any<void>(<Future<void>>[release.future, ?cancelFuture]);
          if (fault.thenCommit) return _handle(request);
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'fake: hang released',
          );
        case FaultKind.custom:
          return fault.response!;
      }
    }
    // Shared auth endpoint, outside the app base; needs no device key.
    if (request.path == biometricStatusPath && request.method == 'GET') {
      return _biometricStatus(request, options, cancelFuture);
    }
    return _handle(request);
  }

  @override
  void close({bool force = false}) {}

  FakeFault? _takeFault(RecordedRequest request) {
    for (final fault in faults) {
      if (fault.matches(request)) {
        fault.remaining--;
        if (fault.remaining <= 0) faults.remove(fault);
        return fault;
      }
    }
    return null;
  }

  // ── Routing ───────────────────────────────────────────────────────────

  Future<ResponseBody> _handle(RecordedRequest r) async {
    if (r.headers['X-Device-Key'] != deviceKey) {
      return _text(401, 'Unauthorized');
    }
    final path = r.path;
    if (!path.startsWith(base)) return _text(404, 'Not Found');
    final rest = path.substring(base.length);

    if (rest == '/auth/pin' && r.method == 'POST') return _login(r);
    if (rest == '/auth/logout' && r.method == 'POST') return _logout(r);

    final sessionError = _checkSession(r);
    if (sessionError != null) return sessionError;
    final worker = workerById(sessions[r.sessionToken]!.operatorId)!;

    if (rest == '/sessions/me' && r.method == 'GET') return _me(r);
    if (rest == '/check' && r.method == 'POST') return _check(r);
    if (rest == '/orders' && r.method == 'GET') return _queue(r);
    final match = RegExp(r'^/orders/(\d+)/(start|complete)$').firstMatch(rest);
    if (match != null && r.method == 'POST') {
      return _execute(
        r,
        worker,
        int.parse(match.group(1)!),
        match.group(2) == 'start' ? 'START' : 'COMPLETE',
      );
    }
    return _text(404, 'Not Found');
  }

  ResponseBody? _checkSession(RecordedRequest r) {
    final token = r.sessionToken;
    if (token == null || token.isEmpty) {
      return _error(401, 'GRINDING_WORKER_SESSION_REQUIRED');
    }
    final session = sessions[token];
    if (session == null || session.ended) {
      return _error(401, 'GRINDING_WORKER_SESSION_INVALID');
    }
    if (session.expired) {
      return _error(401, 'GRINDING_WORKER_SESSION_EXPIRED');
    }
    final worker = workerById(session.operatorId);
    if (worker == null || !worker.allowed) {
      session.ended = true;
      return _error(403, 'GRINDING_WORKER_NOT_ALLOWED');
    }
    return null;
  }

  ResponseBody _login(RecordedRequest r) {
    final pin = r.body?['pin'];
    if (pin is! String || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      return _error(400, 'VALIDATION_ERROR');
    }
    final worker = _workersByPin[pin];
    if (worker == null) return _error(401, 'OPERATOR_PIN_INVALID');
    if (!worker.allowed) return _error(403, 'GRINDING_WORKER_NOT_ALLOWED');
    // The gate runs after the PIN and the permission, before the session.
    final gate = _biometricGate(worker);
    if (gate != null) return gate;
    // A new login ends the worker's previous session.
    for (final session in sessions.values) {
      if (session.operatorId == worker.operatorId) session.ended = true;
    }
    final token = issueSession(worker.operatorId);
    return _ok(<String, dynamic>{
      'sessionToken': token,
      'expiresAt': sessionExpiresAt,
      'worker': worker.toJson(),
    });
  }

  ResponseBody _logout(RecordedRequest r) {
    final session = sessions[r.sessionToken];
    final ended = session != null && session.usable;
    session?.ended = true;
    return _ok(<String, dynamic>{'ended': ended});
  }

  ResponseBody _me(RecordedRequest r) {
    final session = sessions[r.sessionToken]!;
    return _ok(<String, dynamic>{
      'sessionId': session.sessionId,
      'createdAt': now,
      'expiresAt': sessionExpiresAt,
      'worker': workerById(session.operatorId)!.toJson(),
    });
  }

  /// Mirrors the backend's smart Roll/Pallet resolution (contract §4.2): a
  /// candidate is actionable when its order is READY_FOR_GRINDING or
  /// IN_GRINDING; a CANCELLED / REJECTED order holds nothing.
  ResponseBody _check(RecordedRequest r) {
    final raw = r.body?['identifier'];
    final identifier = raw is String ? raw.trim() : '';
    if (!RegExp(r'^\d{12}$').hasMatch(identifier)) {
      return _error(400, 'GRINDING_IDENTIFIER_INVALID');
    }
    final sources = _sources[identifier] ?? const <FakeSource>[];
    if (sources.isEmpty) return _error(404, 'GRINDING_SOURCE_NOT_FOUND');
    final sourceType = r.body?['sourceType'];
    if (sourceType != null) {
      final matching = sources.where((c) => c.sourceType == sourceType);
      if (matching.isEmpty) return _error(404, 'GRINDING_SOURCE_NOT_FOUND');
      return _answer(identifier, matching.first, 'SOURCE_TYPE_SELECTED');
    }
    final roll = _firstOfType(sources, 'ROLL');
    final pallet = _firstOfType(sources, 'PALLET');
    if (roll == null || pallet == null) {
      return _answer(identifier, (roll ?? pallet)!, 'SINGLE_MATCH');
    }
    final both = <FakeSource>[roll, pallet];
    final views = <Map<String, dynamic>>[for (final s in both) _candidate(s)];
    final actionable = both.where(_actionable).toList();
    if (actionable.length == 2) {
      return _error(
        409,
        'GRINDING_IDENTIFIER_AMBIGUOUS',
        message:
            'The number $identifier names both a roll and a pallet that can '
            'be acted on; resend with sourceType.',
        details: <String, dynamic>{
          'identifier': identifier,
          'resolution': 'REQUIRES_SELECTION',
          'candidates': views,
          'message': 'الرقم موجود لرول وطبلية، أي واحدة تريد جرشها؟',
        },
      );
    }
    if (actionable.length == 1) {
      return _answer(identifier, actionable.single, 'AUTO_RESOLVED', views);
    }
    final withOrder = both.where((s) => _liveOrder(s) != null).toList();
    if (withOrder.length == 1) {
      return _answer(identifier, withOrder.single, 'AUTO_RESOLVED', views);
    }
    return _ok(<String, dynamic>{
      'identifier': identifier,
      'status': 'NOT_ELIGIBLE',
      'statusLabel': 'غير مؤهل للجرش',
      'message': withOrder.isEmpty
          ? 'الرقم موجود لرول وطبلية، ولا يوجد أمر جرش لأيٍّ منهما.'
          : 'الرقم موجود لرول وطبلية، ولا يمكن جرش أيٍّ منهما الآن.',
      'allowedToStartGrinding': false,
      'allowedToCompleteGrinding': false,
      'resolution': 'NONE_ACTIONABLE',
      'candidates': views,
    });
  }

  static FakeSource? _firstOfType(List<FakeSource> sources, String type) {
    for (final source in sources) {
      if (source.sourceType == type) return source;
    }
    return null;
  }

  FakeOrder? _liveOrder(FakeSource source) {
    final orderId = source.orderId;
    final order = orderId == null ? null : orders[orderId];
    if (order == null ||
        order.status == 'CANCELLED' ||
        order.status == 'REJECTED') {
      return null;
    }
    return order;
  }

  bool _actionable(FakeSource source) {
    final status = _liveOrder(source)?.status;
    return status == 'READY_FOR_GRINDING' || status == 'IN_GRINDING';
  }

  Map<String, dynamic> _candidate(FakeSource source) {
    final order = _liveOrder(source);
    return <String, dynamic>{
      'sourceType': source.sourceType,
      'label': source.sourceType == 'PALLET' ? 'طبلية' : 'رول',
      'status': order?.status ?? 'NOT_ELIGIBLE',
      'statusLabel': order == null
          ? 'غير مؤهل للجرش'
          : FakeOrder.labelFor(order.status),
      'allowedToStartGrinding': order?.status == 'READY_FOR_GRINDING',
      'allowedToCompleteGrinding': order?.status == 'IN_GRINDING',
      'orderNumber': ?order?.orderNumber,
      'materialName':
          ?(order?.materialName ?? source.details?['productName'] as String?),
    };
  }

  ResponseBody _answer(
    String identifier,
    FakeSource source,
    String resolution, [
    List<Map<String, dynamic>>? candidates,
  ]) {
    final order = _liveOrder(source);
    if (order == null) {
      return _ok(<String, dynamic>{
        'identifier': identifier,
        'sourceType': source.sourceType,
        'status': 'NOT_ELIGIBLE',
        'statusLabel': 'غير مؤهل للجرش',
        'message': source.sourceType == 'PALLET'
            ? 'لا يوجد أمر جرش لهذه الطبلية.'
            : 'لا يوجد أمر جرش لهذا الرول.',
        'allowedToStartGrinding': false,
        'allowedToCompleteGrinding': false,
        'details':
            source.details ??
            <String, dynamic>{
              'scannedValue': identifier,
              'productName': 'كاسة 250',
              'quantity': 1200,
            },
        'resolution': resolution,
        'candidates': ?candidates,
      });
    }
    return _ok(<String, dynamic>{
      'identifier': identifier,
      'sourceType': source.sourceType,
      'status': order.status,
      'statusLabel': FakeOrder.labelFor(order.status),
      'message': FakeOrder.messageFor(order),
      'allowedToStartGrinding': order.status == 'READY_FOR_GRINDING',
      'allowedToCompleteGrinding': order.status == 'IN_GRINDING',
      'order': order.toJson(),
      'resolution': resolution,
      'candidates': ?candidates,
    });
  }

  ResponseBody _queue(RecordedRequest r) {
    final status = r.uri.queryParameters['status'];
    if (status != 'READY_FOR_GRINDING' && status != 'IN_GRINDING') {
      return _error(400, 'VALIDATION_ERROR');
    }
    final rows = orders.values.where((o) => o.status == status).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return _ok(<String, dynamic>{
      'orders': <Map<String, dynamic>>[for (final o in rows) o.toJson()],
      'limit': 100,
    });
  }

  Future<ResponseBody> _execute(
    RecordedRequest r,
    FakeWorker worker,
    int orderId,
    String command,
  ) async {
    final id = r.body?['clientRequestId'];
    if (id is! String || id.isEmpty || id.length > 64) {
      return _error(400, 'VALIDATION_ERROR');
    }
    final message = command == 'START' ? 'بدأ الجرش.' : 'تم الجرش فعليًا';
    final previous = idempotency[id];
    if (previous != null) {
      if (previous.orderId == orderId && previous.command == command) {
        return _ok(<String, dynamic>{
          'order': orders[orderId]!.toJson(),
          'replayed': true,
          'message': message,
        });
      }
      return _error(409, 'GRINDING_IDEMPOTENCY_KEY_REUSED');
    }
    final order = orders[orderId];
    if (order == null) return _error(404, 'GRINDING_ORDER_NOT_FOUND');
    if (command == 'START') {
      if (order.status == 'PENDING_APPROVAL') {
        return _error(409, 'GRINDING_APPROVAL_REQUIRED');
      }
      if (order.status != 'READY_FOR_GRINDING') {
        return _error(409, 'GRINDING_ORDER_NOT_READY');
      }
      order
        ..status = 'IN_GRINDING'
        ..startedByName = worker.name
        ..startedAt = now;
    } else {
      if (order.status == 'COMPLETED') {
        return _error(409, 'GRINDING_ORDER_ALREADY_COMPLETED');
      }
      if (order.status != 'IN_GRINDING') {
        return _error(409, 'GRINDING_ORDER_NOT_IN_PROGRESS');
      }
      order
        ..status = 'COMPLETED'
        ..completedByName = worker.name
        ..completedAt = now;
    }
    order.version++;
    _transitions[orderId] = transitionsFor(orderId) + 1;
    idempotency[id] = FakeIdempotencyEntry(orderId, command);
    await onCommitted?.call(r);
    return _ok(<String, dynamic>{
      'order': order.toJson(),
      'replayed': false,
      'message': message,
    });
  }

  // ── Biometric gate ────────────────────────────────────────────────────

  static const Map<String, String> biometricMessages = <String, String>{
    'BIOMETRIC_VERIFICATION_REQUIRED':
        'يرجى تمرير البصمة على جهاز البصمة ثم إعادة المحاولة.',
    'BIOMETRIC_VERIFICATION_EXPIRED':
        'انتهت صلاحية التحقق بالبصمة. يرجى تمرير البصمة مرة أخرى ثم إعادة المحاولة.',
    'BIOMETRIC_DEVICE_UNAVAILABLE':
        'جهاز البصمة غير متصل حاليًا. يرجى المحاولة بعد قليل أو إبلاغ المسؤول.',
    'BIOMETRIC_MAPPING_MISSING':
        'لم يتم ربط بصمتك بحسابك بعد. يرجى مراجعة مسؤول النظام.',
    'BIOMETRIC_MAPPING_DISABLED':
        'ربط البصمة الخاص بحسابك غير مفعّل. يرجى مراجعة مسؤول النظام.',
    'BIOMETRIC_LOGIN_ATTEMPT_EXPIRED':
        'انتهت مهلة محاولة الدخول. يرجى تسجيل الدخول مرة أخرى.',
  };

  ResponseBody? _biometricGate(FakeWorker worker) {
    if (!_biometricEnforced ||
        !_biometricAgentOnline ||
        worker.biometricExempt) {
      return null;
    }
    final mappingCode = switch (worker.mapping) {
      FakeBiometricMapping.linked => null,
      FakeBiometricMapping.missing => 'BIOMETRIC_MAPPING_MISSING',
      FakeBiometricMapping.disabled => 'BIOMETRIC_MAPPING_DISABLED',
    };
    if (mappingCode != null) return biometricDenial(mappingCode);
    if (worker.punch == FakePunch.fresh) return null;
    final code = !_biometricTerminalOnline
        ? 'BIOMETRIC_DEVICE_UNAVAILABLE'
        : worker.punch == FakePunch.expired
        ? 'BIOMETRIC_VERIFICATION_EXPIRED'
        : 'BIOMETRIC_VERIFICATION_REQUIRED';
    if (!biometricAttemptsAvailable) return biometricDenial(code);
    final token = 'bat-${++_attemptSeq}-q3Jx8d6cYt0H1m0yF3kZ0wS9gQx8B7nV';
    biometricAttempts[token] = FakeBiometricAttempt(token, worker.operatorId);
    return biometricDenial(code, attemptToken: token);
  }

  /// A `BIOMETRIC_*` 403 exactly as the handoff shows it (§4.2).
  static ResponseBody biometricDenial(
    String code, {
    String? attemptToken,
    String? statusPath = biometricStatusPath,
  }) => _error(
    403,
    code,
    message: biometricMessages[code],
    details: <String, dynamic>{
      'validitySeconds': 300,
      if (attemptToken != null) ...<String, dynamic>{
        'attemptToken': attemptToken,
        'attemptExpiresAt': '2026-09-24T08:15:00.000Z',
        'statusPath': ?statusPath,
      },
      'attemptAvailable': attemptToken != null,
    },
  );

  /// A status answer for [FaultKind.custom].
  static ResponseBody biometricStatus(String status) => _ok(<String, dynamic>{
    'status': status,
    'attemptExpiresAt': '2026-09-24T08:15:00.000Z',
  });

  String _attemptStatus(FakeBiometricAttempt attempt) {
    final worker = workerById(attempt.operatorId)!;
    if (!_biometricEnforced || worker.biometricExempt) return 'NOT_REQUIRED';
    if (!_biometricAgentOnline) return 'ENFORCEMENT_SUSPENDED';
    switch (worker.mapping) {
      case FakeBiometricMapping.missing:
        return 'MAPPING_MISSING';
      case FakeBiometricMapping.disabled:
        return 'MAPPING_DISABLED';
      case FakeBiometricMapping.linked:
        break;
    }
    if (worker.punch == FakePunch.fresh) return 'VERIFIED';
    if (!_biometricTerminalOnline) return 'DEVICE_UNAVAILABLE';
    return 'PENDING';
  }

  /// Long-poll: an unchanged PENDING / DEVICE_UNAVAILABLE is held until
  /// something changes or the client cancels.
  Future<ResponseBody> _biometricStatus(
    RecordedRequest r,
    RequestOptions options,
    Future<void>? cancelFuture,
  ) async {
    final token = r.headers['X-Biometric-Attempt-Token'];
    var cancelled = false;
    unawaited(cancelFuture?.then((_) => cancelled = true));
    while (true) {
      final attempt = biometricAttempts[token];
      if (attempt == null || attempt.expired) {
        return _error(
          410,
          'BIOMETRIC_LOGIN_ATTEMPT_EXPIRED',
          message: biometricMessages['BIOMETRIC_LOGIN_ATTEMPT_EXPIRED'],
        );
      }
      final status = _attemptStatus(attempt);
      final unchanged =
          (status == 'PENDING' || status == 'DEVICE_UNAVAILABLE') &&
          status == attempt.lastAnswer;
      if (!unchanged) {
        attempt.lastAnswer = status;
        return biometricStatus(status);
      }
      await Future.any<void>(<Future<void>>[
        _biometricChange.future,
        ?cancelFuture,
      ]);
      if (cancelled) {
        biometricPollsAborted++;
        throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'fake: long-poll cancelled',
        );
      }
    }
  }

  // ── Responses ─────────────────────────────────────────────────────────

  static ResponseBody _ok(Map<String, dynamic> data) =>
      _json(200, <String, dynamic>{'success': true, 'data': data});

  static ResponseBody _error(
    int status,
    String code, {
    String? message,
    Map<String, dynamic>? details,
  }) => _json(status, <String, dynamic>{
    'success': false,
    'error': <String, dynamic>{
      'code': code,
      'message': message ?? 'English technical message for $code',
      'details': ?details,
    },
  });

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  static ResponseBody _text(int status, String body) => ResponseBody.fromString(
    body,
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['text/html'],
    },
  );

  /// A JSON response for [FaultKind.custom].
  static ResponseBody jsonResponse(int status, Object body) =>
      _json(status, body);
}

enum FaultKind {
  /// Fails before reaching the server (nothing committed).
  connectionError,

  /// Times out before reaching the server (nothing committed).
  receiveTimeout,

  /// The server commits, then the response is lost on the way back.
  lostResponseAfterCommit,

  /// 503 with an HTML body (no envelope).
  serverError,

  /// 200 with an HTML body (captive portal / proxy page).
  captivePortal,

  /// 401 without an envelope (device key rejected).
  deviceUnauthorized,

  /// Waits for [FakeFault.release] (or cancellation); then commits when
  /// [FakeFault.thenCommit], else fails with a connection error.
  hang,

  /// Returns [FakeFault.response].
  custom,
}

class FakeFault {
  FakeFault(
    this.kind, {
    this.method,
    this.pathEndsWith,
    int times = 1,
    this.release,
    this.thenCommit = false,
    this.response,
  }) : remaining = times;

  final FaultKind kind;
  final String? method;
  final String? pathEndsWith;
  final Completer<void>? release;
  final bool thenCommit;
  final ResponseBody? response;
  int remaining;

  bool matches(RecordedRequest r) =>
      (method == null || method == r.method) &&
      (pathEndsWith == null || r.path.endsWith(pathEndsWith!));
}

class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
    this.contentType,
    this.receiveTimeout,
  });

  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final Map<String, dynamic>? body;
  final String? contentType;
  final Duration? receiveTimeout;

  String get path => uri.path;

  String? get sessionToken => headers['X-Session-Token'] as String?;

  String? get deviceKey => headers['X-Device-Key'] as String?;

  String? get attemptToken => headers['X-Biometric-Attempt-Token'] as String?;

  String? get clientRequestId => body?['clientRequestId'] as String?;

  @override
  String toString() => 'RecordedRequest($method $path)';
}

enum FakePunch { none, fresh, expired }

enum FakeBiometricMapping { linked, missing, disabled }

class FakeBiometricAttempt {
  FakeBiometricAttempt(this.token, this.operatorId);

  final String token;
  final int operatorId;
  bool expired = false;
  String? lastAnswer;
}

class FakeWorker {
  FakeWorker({
    required this.pin,
    required this.operatorId,
    required this.name,
    this.allowed = true,
  });

  final String pin;
  final int operatorId;
  final String name;
  bool allowed;
  FakePunch punch = FakePunch.none;
  FakeBiometricMapping mapping = FakeBiometricMapping.linked;
  bool biometricExempt = false;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'operatorId': operatorId,
    'name': name,
  };
}

class FakeSession {
  FakeSession({
    required this.token,
    required this.operatorId,
    required this.sessionId,
  });

  final String token;
  final int operatorId;
  final int sessionId;
  bool ended = false;
  bool expired = false;

  bool get usable => !ended && !expired;
}

class FakeSource {
  FakeSource(this.identifier, this.sourceType, {this.orderId, this.details});

  final String identifier;
  final String sourceType;
  final int? orderId;
  final Map<String, dynamic>? details;
}

class FakeIdempotencyEntry {
  FakeIdempotencyEntry(this.orderId, this.command);

  final int orderId;
  final String command;
}

class FakeOrder {
  FakeOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.sourceType,
    required this.sourceOrigin,
    required this.sourceIdentifier,
    required this.createdAt,
    this.materialName,
    this.expectedWeightKg,
    this.sourceQuantity,
    this.lineName,
    this.directScrap = false,
    this.legacy = false,
    this.startedByName,
    this.startedAt,
    this.completedByName,
    this.completedAt,
  });

  final int id;
  final String orderNumber;
  String status;
  final String sourceType;
  final String sourceOrigin;
  final String sourceIdentifier;
  final String createdAt;
  final String? materialName;
  final Object? expectedWeightKg;
  final Object? sourceQuantity;
  final String? lineName;
  final bool directScrap;
  final bool legacy;
  String? startedByName;
  String? startedAt;
  String? completedByName;
  String? completedAt;
  int version = 0;

  static String labelFor(String status) => switch (status) {
    'PENDING_APPROVAL' => 'بانتظار موافقة المدير',
    'READY_FOR_GRINDING' => 'جاهز للجرش',
    'IN_GRINDING' => 'قيد الجرش',
    'COMPLETED' => 'تم الجرش',
    'REJECTED' => 'مرفوض',
    'CANCELLED' => 'ملغى',
    _ => status,
  };

  static String? messageFor(FakeOrder order) => switch (order.status) {
    'PENDING_APPROVAL' => 'بانتظار موافقة المدير — لا يمكن بدء الجرش بعد.',
    'READY_FOR_GRINDING' => 'جاهز للجرش — يمكنك بدء الجرش.',
    'IN_GRINDING' => 'قيد الجرش — أكّد انتهاء الجرش بعد الجرش الفعلي.',
    'COMPLETED' => 'تم جرش هذا الأمر.',
    _ => null,
  };

  // Null fields are omitted, as the contract's envelope does (§4.1).
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'orderNumber': orderNumber,
    'status': status,
    'statusLabel': labelFor(status),
    'sourceType': sourceType,
    'sourceOrigin': sourceOrigin,
    'sourceIdentifier': sourceIdentifier,
    'materialName': ?materialName,
    'expectedWeightKg': ?expectedWeightKg,
    'sourceQuantity': ?sourceQuantity,
    'lineName': ?lineName,
    'directScrap': directScrap,
    'legacy': legacy,
    'startedByName': ?startedByName,
    'startedAt': ?startedAt,
    'completedByName': ?completedByName,
    'completedAt': ?completedAt,
    'createdAt': createdAt,
    'version': version,
  };
}
