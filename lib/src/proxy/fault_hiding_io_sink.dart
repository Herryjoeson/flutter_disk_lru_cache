part of flutter_disk_lru_cache;

/// 错误的回调
typedef void ErrorVoidCallback(Object e);

/// 代理类ioSink
class FaultHidingIOSink {
  final RandomAccessFile _randomAccessFile;
  final ErrorVoidCallback _onError;

  FaultHidingIOSink(this._randomAccessFile, this._onError);

  Future<void> write(String text) async {
    try {
      await _randomAccessFile.writeString(text);
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> writeByte(List<int> buffer, [int start = 0, int? end]) async {
    try {
      await _randomAccessFile.writeFrom(buffer, start, end);
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> close() async {
    try {
      await _randomAccessFile.close();
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> flush() async {
    try {
      await _randomAccessFile.flush();
    } catch (e) {
      _onError(e);
    }
  }
}
