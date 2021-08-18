part of flutter_disk_lru_cache;

/// 编辑器对象
class Editor {
  /// 对应的文件实体
  late final _Entry _entry;

  /// 是否写入
  late final List<bool> _written = !_entry.readable ? List.filled(_valueCount, false) : [];

  /// 对应的文件关系,和disk_lru_cache的[valueCount]是一致的，
  /// 比如可能是1对多，或则是一对一，取决于[valueCount]
  final int _valueCount;

  /// 是否出现错误
  bool _hasErrors = false;

  /// 是否提交
  bool _committed = false;

  Editor(this._entry, this._valueCount);

  /// 返回一个新的无缓冲输出流，以便在其中写入值，如果基础输出流遇到错误，返回的输出流不会抛出例外情况
  FaultHidingIOSink newOutputIOSink(int index) {
    if (index < 0 || index >= _valueCount) {
      throw IllegalArgumentException(
        "Expected index $index to be greater than 0 and less than the maximum value count of $_valueCount",
      );
    }
    if (_entry.currentEditor != this) throw IllegalStateException();
    if (!_entry.readable) _written[index] = true;
    return FaultHidingIOSink(_entry.getDirtyFile(index).openWrite(), (e) => _hasErrors = true);
  }

  /// index需要对得上上面的valueCount
  /// 配置对应的内容值到文件中
  Future<void> set(int index, Object value) async {
    FaultHidingIOSink? faultHidingIOSink;
    try {
      faultHidingIOSink = newOutputIOSink(index);
      faultHidingIOSink.write(value);
      await faultHidingIOSink.flush();
      await faultHidingIOSink.close();
    } finally {
      faultHidingIOSink?.close();
    }
  }

  /// 提交
  Future<void> commit(DiskLruCache cache) async {
    if (_committed) {
      return;
    }
    if (_hasErrors) {
      await cache._completeEdit(this, false);
      await cache.remove(_entry.key);
    } else {
      await cache._completeEdit(this, true);
    }
    _committed = true;
  }

  /// 中断提交
  Future<void> abort(DiskLruCache cache) async {
    await cache._completeEdit(this, false);
  }
}
