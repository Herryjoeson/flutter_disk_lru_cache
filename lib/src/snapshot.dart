part of flutter_disk_lru_cache;

class Snapshot {
  final String key;
  final int sequenceNumber;
  final List<RandomAccessFile?> _sinkList;
  final List<int> _lengths;

  Snapshot(this.key, this.sequenceNumber, this._sinkList, this._lengths);

  /// 获取对应的文件读模式
  RandomAccessFile getRandomAccessFile(int index) => _sinkList[index]!;

  /// 返回对应的[index]文件字节长度
  int getLength(int index) => _lengths[index];

  /// 关闭
  void close() {
    for (var element in _sinkList) {
      if (element != null) element.close();
    }
  }
}
