part of flutter_disk_lru_cache;

/// 错误的回调
typedef void ErrorVoidCallback(Object e);

/// 代理类ioSink
class FaultHidingIOSink implements IOSink {
  final IOSink sink;
  final ErrorVoidCallback onError;

  FaultHidingIOSink(this.sink, this.onError);

  @override
  void add(List<int> data) {
    try {
      sink.add(data);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) => sink.addError(error, stackTrace);

  @override
  Future addStream(Stream<List<int>> stream) async {
    try {
      return await sink.addStream(stream);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  Future close() async {
    try {
      return await sink.close();
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  Future get done => sink.done;

  @override
  Future flush() async {
    try {
      return await sink.flush();
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  void write(Object? object) {
    try {
      sink.write(object);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  void writeAll(Iterable objects, [String separator = ""]) {
    try {
      sink.writeAll(objects, separator);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  void writeCharCode(int charCode) {
    try {
      sink.writeCharCode(charCode);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  void writeln([Object? object = ""]) {
    try {
      sink.writeln(object);
    } catch (e) {
      this.onError(e);
    }
  }

  @override
  late Encoding encoding = utf8;
}
