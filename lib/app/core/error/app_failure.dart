final class AppFailure implements Exception {
  const AppFailure({
    required this.code,
    required this.message,
    required this.stage,
    required this.retryable,
  });
  final String code;
  final String message;
  final String stage;
  final bool retryable;
  @override
  String toString() => message;
}
