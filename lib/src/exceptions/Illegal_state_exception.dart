part of flutter_disk_lru_cache;

class IllegalStateException implements Exception {
  final dynamic message;

  IllegalStateException([this.message]);

  String toString() {
    Object? message = this.message;
    if (message == null) return "IllegalStateException";
    return "IllegalStateException: $message";
  }
}
