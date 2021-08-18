part of flutter_disk_lru_cache;

/// 文件的映射
class _Entry {
  /// 转化过的文件名
  final String key;

  /// 所属文件夹
  final Directory directory;

  /// 对应的文件关系,和disk_lru_cache的[valueCount]是一致的，
  /// 比如可能是1对多，或则是一对一，取决于[valueCount]
  final int valueCount;

  /// 文件的大小
  List<int> _lengths = [];

  List<int> get lengths => _lengths;

  /// 如果此条目曾经发布过，则为真。
  bool readable = false;

  /// 正在进行的编辑，如果未编辑此条目，则为空
  Editor? currentEditor;

  /// 最近提交到此条目的编辑的序列号.
  int sequenceNumber = 0;

  _Entry(this.key, this.directory, this.valueCount) {
    _lengths = new List.filled(valueCount, 0);
  }

  /// 格式化文件大小输出
  String get getLengths {
    final StringBuffer result = new StringBuffer();
    for (int size in _lengths) {
      result.write(' ');
      result.write(size);
    }
    return result.toString();
  }

  void setLengths(List<String> strings) {
    if (strings.length != valueCount) {
      throw IllegalArgumentException("unexpected journal line: ${strings.toString()}");
    }

    for (int i = 0; i < strings.length; i++) {
      int? num = int.tryParse(strings[i]);
      if (num == null) {
        throw FormatException("unknown int string: ${strings[i]}");
      }
      _lengths[i] = num;
    }
  }

  /// 获取主文件,commit完毕
  File getCleanFile(int i) => File("${directory.path}/$key.$i");

  /// 获取未成功操作完毕的文件，比如没有commit
  File getDirtyFile(int i) => File("${directory.path}/$key.$i.tmp");
}
