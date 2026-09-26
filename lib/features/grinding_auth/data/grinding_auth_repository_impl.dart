import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bootstrap/providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/entities/biometric_attempt.dart';
import '../domain/entities/grinding_worker.dart';
import '../domain/repositories/grinding_auth_repository.dart';
import 'grinding_auth_remote_data_source.dart';

class GrindingAuthRepositoryImpl implements GrindingAuthRepository {
  GrindingAuthRepositoryImpl(this._remote);

  final GrindingAuthRemoteDataSource _remote;

  @override
  Future<PinLoginResult> loginWithPin(String pin) =>
      _guard(() => _remote.loginWithPin(pin));

  @override
  Future<GrindingSession> getSession() => _guard(_remote.getSession);

  @override
  Future<bool> logout() => _guard(_remote.logout);

  @override
  Future<BiometricAttemptStatusResponse> getBiometricAttemptStatus({
    required String? statusPath,
    required String attemptToken,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _guard(
        () => _remote.getBiometricAttemptStatus(
          statusPath: statusPath,
          attemptToken: attemptToken,
          cancelToken: cancelToken,
        ),
      );
    } on AppFailure catch (failure) {
      // 410 means "unknown or expired attempt" on this endpoint, with or
      // without the envelope (a proxy may strip it) — never keep polling.
      final gone = switch (failure) {
        ApiFailure(:final status) ||
        ServerFailure(:final status) => status == 410,
        _ => false,
      };
      if (gone) throw const AppFailure.biometricAttemptExpired();
      rethrow;
    }
  }

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AppFailure {
      rethrow;
    } on DioException catch (e) {
      throw ErrorMapper.fromException(e);
    } catch (e, st) {
      throw ErrorMapper.fromException(e, st);
    }
  }
}

final grindingAuthRemoteDataSourceProvider =
    Provider<GrindingAuthRemoteDataSource>(
      (ref) => GrindingAuthRemoteDataSource(ref.watch(dioProvider)),
    );

final grindingAuthRepositoryProvider = Provider<GrindingAuthRepository>((ref) {
  return GrindingAuthRepositoryImpl(
    ref.watch(grindingAuthRemoteDataSourceProvider),
  );
});
