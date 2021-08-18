part of flutter_disk_lru_cache;

class IllegalArgumentException implements Exception {
  final dynamic message;

  IllegalArgumentException([this.message]);

  String toString() {
    Object? message = this.message;
    if (message == null) return "IllegalArgumentException";
    return "IllegalArgumentException: $message";
  }
}
