part of flutter_disk_lru_cache;

class DiskLruCache {
  /// 操作的记录文件名
  static const String JOURNAL_FILE = "journal";

  /// 临时文件
  static const String JOURNAL_FILE_TEMP = "journal.tmp";

  /// 备份文件
  static const String JOURNAL_FILE_BACKUP = "journal.bkp";

  /// 标识
  static const String MAGIC = "libcore.io.DiskLruCache";

  /// 版本
  static const String VERSION_1 = "1";

  /// 记录的操作行为符
  static const String READ = "READ";
  static const String DIRTY = "DIRTY";
  static const String CLEAN = "CLEAN";
  static const String REMOVE = "REMOVE";

  static const int ANY_SEQUENCE_NUMBER = -1;

  /// 正则匹配
  static const String STRING_KEY_PATTERN = r"^[a-zA-Z0-9_-]{1,120}$";

  /// 存储缓存的文件路径
  final Directory cacheDirectory;

  /// 操作数据的记录文件
  late final File journalFile = File("${cacheDirectory.path}/$JOURNAL_FILE");

  /// 重新构建的记录临时文件
  late final File journalFileTmp = File("${cacheDirectory.path}/$JOURNAL_FILE_TEMP");

  /// 备份文件
  late final File journalFileBackup = File("${cacheDirectory.path}/$JOURNAL_FILE_BACKUP");

  /// 锁
  static late final Lock _runtimeLock = Lock(reentrant: true);

  /// 存储对应的lru磁盘文件map
  final LinkedHashMap<String, _Entry> _lruEntries = LinkedHashMap(
    equals: (String k1, String k2) => k1 == k2,
  );

  /// 存储最大的容量
  int _maxSize;

  /// 版本
  final String appVersion;

  /// ValuesCount是Key所对应的文件数，我们通常选择一一对应的简单关系，这样比较方便控制，当然我们也可以一对多的关系，通常写入1,表示一一对应的关系。
  final int valueCount;

  /// 存储的大小
  int _size = 0;

  /// 冗余的数据值，默认为0
  int _redundantOpCount = 0;

  /// 为了区分旧快照和当前快照，给出了每个条目每次提交编辑时的序列号。如果发生以下情况，则快照已过时
  /// 其序列号不等于其条目的序列号。
  int _nextSequenceNumber = 0;

  /// 记录文件的IO流
  IOSink? _journalFileWriter;

  DiskLruCache._(this.cacheDirectory, this.appVersion, this.valueCount, this._maxSize);

  /// 只有当日志大小减半时，我们才重建日志至少取消2000项
  bool get _journalRebuildRequired => _redundantOpCount >= 2000 && _redundantOpCount >= _lruEntries.length;

  /// 检查是否关闭缓存
  Future<bool> get isClosed async => await _runtimeLock.synchronized(() => _journalFileWriter == null);

  /// 容量的大小
  Future<int> get size async => await _runtimeLock.synchronized(() => _size);

  /// 返回此缓存应用于存储其数据的最大字节数
  Future<int> get maxSize async => await _runtimeLock.synchronized(() => _maxSize);

  /// 更改缓存可以存储的最大字节数
  Future<void> setMaxSize(int maxSize) async {
    await _runtimeLock.synchronized(
      () async {
        _maxSize = maxSize;
        await _cleanup();
      },
    );
  }

  /// 检查是否存在缓存目录，没有就创建
  static Future<DiskLruCache> open(
    Directory directory, {
    String version = "1.0.0",
    int valueCount = 1,
    int maxSize = 20 * 1024 * 1024,
  }) async {
    if (maxSize <= 0) throw Exception("maxSize <= 0");
    if (valueCount <= 0) throw Exception("valueCount <= 0");

    if (!await directory.exists()) {
      await directory.create();
    }

    File backupFile = File("${directory.path}/$JOURNAL_FILE_BACKUP");
    if (await backupFile.exists()) {
      File journalFile = File("${directory.path}/$JOURNAL_FILE");
      await journalFile.exists() ? await backupFile.delete() : await backupFile.rename(journalFile.path);
    }

    DiskLruCache cache = new DiskLruCache._(directory, version, valueCount, maxSize);
    if (await cache.journalFile.exists()) {
      try {
        await cache._readJournal();
        await cache._processJournal();
        return cache;
      } catch (e) {
        await cache.delete();
      }
    }
    await cache._rebuildJournal();
    return cache;
  }

  /// 读取journal文件
  Future<void> _readJournal() async {
    int lineCount = 0, currentNum = 0;

    /// 按照格式读取每行,确认格式
    var lineStream = journalFile.openRead().transform(ascii.decoder).transform(LineSplitter());

    /// 读取前5行
    final List<String> beforeFiveStringText = [MAGIC, VERSION_1, appVersion, valueCount.toString(), ""];
    await for (final line in lineStream) {
      if (currentNum >= 5) {
        await _readJournalLine(line);
        lineCount++;
      } else {
        if (line != beforeFiveStringText[currentNum]) {
          throw Exception("The Journal file is broken: unexpected file header:$line");
        } else {
          currentNum++;
        }
      }
    }
    _redundantOpCount = lineCount - _lruEntries.length;
    _journalFileWriter = journalFile.openWrite(mode: FileMode.append);
  }

  /// 读取记录文件的行数据
  Future<void> _readJournalLine(String line) async {
    int firstSpace = line.indexOf(' ');
    if (firstSpace == -1) {
      throw IllegalArgumentException("unexpected journal line: " + line);
    }

    int keyBegin = firstSpace + 1;
    int secondSpace = line.indexOf(' ', keyBegin);

    final String key;
    if (secondSpace == -1) {
      key = line.substring(keyBegin).trim();
      if (firstSpace == REMOVE.length && line.startsWith(REMOVE)) {
        _lruEntries.remove(key);
        return;
      }
    } else {
      key = line.substring(keyBegin, secondSpace).trim();
    }

    _Entry? entry = _lruEntries[key];
    if (entry == null) {
      entry = _Entry(key, cacheDirectory, valueCount);
      _lruEntries[key] = entry;
    }

    if (secondSpace != -1 && firstSpace == CLEAN.length && line.startsWith(CLEAN)) {
      List<String> parts = line.substring(secondSpace + 1).split(" ");
      entry.readable = true;
      entry.currentEditor = null;
      entry.setLengths(parts);
    } else if (secondSpace == -1 && firstSpace == DIRTY.length && line.startsWith(DIRTY)) {
      entry.currentEditor = Editor(entry, valueCount);
    } else if (secondSpace == -1 && firstSpace == READ.length && line.startsWith(READ)) {
      // 可以进行读取了.
    } else {
      throw new IllegalArgumentException("unexpected journal line: " + line);
    }
  }

  /// 计算初始大小并收集垃圾，作为打开缓存。脏条目假定不一致，将被删除。
  Future<void> _processJournal() async {
    await _deleteIfExists(journalFileTmp);
    _lruEntries.forEach(
      (String key, _Entry entry) {
        if (entry.currentEditor == null) {
          for (int i = 0; i < valueCount; i++) {
            _size += entry.lengths[i];
          }
        } else {
          entry.currentEditor = null;
          for (int i = 0; i < valueCount; i++) {
            _deleteIfExists(entry.getCleanFile(i));
            _deleteIfExists(entry.getDirtyFile(i));
          }
          _lruEntries.remove(key);
        }
      },
    );
  }

  /// 重新构建记录文件
  Future<void> _rebuildJournal() async {
    await _runtimeLock.synchronized(
      () async {
        if (_journalFileWriter != null) {
          _journalFileWriter!.close();
        }

        if (!await cacheDirectory.exists()) {
          await cacheDirectory.create();
        }

        IOSink tempWriter = journalFileTmp.openWrite();
        try {
          tempWriter.write(MAGIC);
          tempWriter.write("\n");
          tempWriter.write(VERSION_1);
          tempWriter.write("\n");
          tempWriter.write(appVersion);
          tempWriter.write("\n");
          tempWriter.write(valueCount.toString());
          tempWriter.write("\n");
          tempWriter.write("\n");
          _lruEntries.forEach(
            (key, entry) {
              if (entry.currentEditor != null) {
                tempWriter.write(DIRTY + ' ' + entry.key + '\n');
              } else {
                tempWriter.write(CLEAN + ' ' + entry.key + entry.getLengths + '\n');
              }
            },
          );
          await tempWriter.flush();
        } finally {
          await tempWriter.close();
        }

        if (await journalFile.exists()) {
          await _renameTo(journalFile, journalFileBackup, true);
        }

        await _renameTo(journalFileTmp, journalFile, false);
        await _deleteIfExists(journalFileBackup);

        _journalFileWriter = journalFile.openWrite(mode: FileMode.append);
      },
    );
  }

  /// 删除如果存在的文件
  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {}
    }
  }

  /// 重命名，确认是否要删除源文件
  Future<void> _renameTo(File from, File to, bool deleteDestination) async {
    if (deleteDestination) {
      await _deleteIfExists(to);
    }
    await from.rename(to.path);
  }

  /// 清空不用的缩减内存
  void _trimToSize() {
    while (_size > _maxSize) {
      MapEntry<String, _Entry> toEvict = _lruEntries.entries.iterator.current;
      remove(toEvict.key);
    }
  }

  /// 返回名为key的项的快照，如果不返回，则返回null
  /// exist当前不可读。如果返回值，则将其移动到队列的头
  Future<Snapshot?> get(String key) async {
    return await _runtimeLock.synchronized(() async {
      _checkCacheNotClosed();
      _validateKey(key);

      if (!_lruEntries.containsKey(key)) return null;
      final _Entry entry = _lruEntries[key]!;
      if (!entry.readable) return null;

      final List<RandomAccessFile?> sinkList = List.filled(valueCount, null);
      try {
        for (int i = 0; i < valueCount; i++) {
          final File cleanFile = entry.getCleanFile(i);
          !cleanFile.existsSync() ? throw FileSystemException("Invalid file path") : sinkList[i] = cleanFile.openSync();
        }
      } catch (e) {
        for (int i = 0; i < valueCount; i++) {
          if (sinkList[i] != null) {
            sinkList[i]!.close();
          } else {
            break;
          }
        }
        return null;
      }

      _redundantOpCount++;
      _journalFileWriter!.write("$READ $key\n");
      if (_journalRebuildRequired) {
        _cleanup();
      }
      return Snapshot(key, entry.sequenceNumber, sinkList, entry.lengths);
    });
  }

  /// 返回名为key的条目的编辑器，如果另一个条目为空，则返回null
  Future<Editor?> edit(String key, {int sequenceNumber = ANY_SEQUENCE_NUMBER}) async {
    return await _runtimeLock.synchronized(
      () async {
        _checkCacheNotClosed();
        _validateKey(key);

        _Entry? entry = _lruEntries[key];
        if ((entry == null || entry.sequenceNumber != sequenceNumber) && sequenceNumber != ANY_SEQUENCE_NUMBER) {
          return null;
        }

        if (entry == null) {
          entry = _Entry(key, cacheDirectory, valueCount);
          _lruEntries[key] = entry;
        } else if (entry.currentEditor != null) {
          return null;
        }

        Editor editor = Editor(entry, valueCount);
        entry.currentEditor = editor;

        /// 在创建文件之前刷新日志，以防止文件泄漏
        _journalFileWriter!.write("$DIRTY $key\n");
        await _journalFileWriter!.flush();
        return editor;
      },
    );
  }

  /// 如果密钥存在并且可以删除，则删除该项。条目无法删除正在编辑的活动项
  /// 如果条目被删除，则返回true。
  Future<bool> remove(String key) async {
    return await _runtimeLock.synchronized(
      () async {
        _checkCacheNotClosed();
        _validateKey(key);

        if (!_lruEntries.containsKey(key)) return false;
        _Entry entry = _lruEntries[key]!;
        if (entry.currentEditor != null) return false;

        for (int i = 0; i < valueCount; i++) {
          File file = entry.getCleanFile(i);
          if (await file.exists()) {
            file.deleteSync();
          }
          _size -= entry.lengths[i];
          entry.lengths[i] = 0;
        }

        _redundantOpCount++;
        _journalFileWriter!.write(REMOVE + ' ' + key + '\n');
        _lruEntries.remove(key);

        if (_journalRebuildRequired) {
          _cleanup();
        }
        return true;
      },
    );
  }

  /// 完成编辑
  Future<void> _completeEdit(Editor editor, bool success) async {
    await _runtimeLock.synchronized(
      () async {
        _Entry entry = editor._entry;
        if (entry.currentEditor != editor) throw IllegalStateException();

        /// 如果此编辑是第一次创建条目，则每个索引必须有一个值.
        if (success && !entry.readable) {
          for (int i = 0; i < valueCount; i++) {
            if (!editor._written[i]) {
              await editor.abort(this);
              throw IllegalStateException("Newly created entry didn't create value for index $i");
            }
            if (!entry.getDirtyFile(i).existsSync()) {
              await editor.abort(this);
              return;
            }
          }
        }

        for (int i = 0; i < valueCount; i++) {
          File dirty = entry.getDirtyFile(i);
          if (success) {
            if (await dirty.exists()) {
              File clean = entry.getCleanFile(i);
              dirty.renameSync(clean.path);
              int oldLength = entry.lengths[i];
              int newLength = await clean.length();
              entry.lengths[i] = newLength;
              _size -= (oldLength + newLength);
            }
          } else {
            await _deleteIfExists(dirty);
          }
        }

        _redundantOpCount++;
        entry.currentEditor = null;
        if (entry.readable | success) {
          entry.readable = true;
          _journalFileWriter!.write(CLEAN + ' ' + entry.key + entry.getLengths + '\n');
          if (success) {
            entry.sequenceNumber = _nextSequenceNumber++;
          }
        } else {
          _lruEntries.remove(entry.key);
          _journalFileWriter!.write(REMOVE + ' ' + entry.key + '\n');
        }
        await _journalFileWriter!.flush();

        if (_size > _maxSize || _journalRebuildRequired) {
          _cleanup();
        }
      },
    );
  }

  ///关闭缓存并删除其所有存储值。这将删除缓存目录中的所有文件，包括不是由创建的文件缓存。
  Future<void> delete() async {
    await close();
    await _deleteContents(cacheDirectory);
  }

  /// 删除缓存下面的文件
  Future<void> _deleteContents(Directory directory) async {
    for (var file in directory.listSync()) {
      if (file is File) {
        file.deleteSync();
      } else if (file is Directory) {
        _deleteContents(file);
      }
    }
  }

  /// 刷新文件系统缓冲区
  Future<void> flush() async {
    await _runtimeLock.synchronized(
      () async {
        _checkCacheNotClosed();
        _trimToSize();
        if (_journalFileWriter != null) {
          await _journalFileWriter!.flush();
        }
      },
    );
  }

  /// 关闭此缓存。存储的值将保留在文件系统上。
  Future<void> close() async {
    await _runtimeLock.synchronized(
      () async {
        if (_journalFileWriter == null) return;
        _lruEntries.values.forEach(
          (element) {
            if (element.currentEditor != null) {
              element.currentEditor!.abort(this);
            }
          },
        );
        _trimToSize();
        await _journalFileWriter!.close();
        _journalFileWriter = null;
      },
    );
  }

  /// 清理数据源
  Future<void> _cleanup() async {
    await _runtimeLock.synchronized(
      () async {
        if (_journalFileWriter == null) {
          return null; // Closed.
        }
        _trimToSize();
        if (_journalRebuildRequired) {
          await _rebuildJournal();
          _redundantOpCount = 0;
        }
      },
    );
  }

  /// 检查是否关闭了缓存
  void _checkCacheNotClosed() {
    if (_journalFileWriter == null) {
      throw Exception("cache is closed");
    }
  }

  /// 检查对应的key的合法性
  void _validateKey(String key) {
    final bool isMatch = RegExp(STRING_KEY_PATTERN).hasMatch(key);
    if (!isMatch) {
      throw IllegalArgumentException("keys must match regex " + STRING_KEY_PATTERN + ": \"" + key + "\"");
    }
  }
}
