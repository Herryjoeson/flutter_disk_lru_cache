# flutter_disk_lru_cache

Dart version based on Android disk LRU cache migration The source code comes
from [android disk LRU cache](https://github.com/JakeWharton/DiskLruCache)

---

## Usage

To use this plugin, follow
the [installing guide](https://pub.dev/packages/flutter_disk_lru_cache/install).

### Example

``` dart
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_disk_lru_cache/flutter_disk_lru_cache.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Directory? tempDirectory = await getTemporaryDirectory();
  if (tempDirectory == null) {
    return;
  }
  
  /// init
  DiskLruCache diskLruCache = await DiskLruCache.open(tempDirectory!, valueCount: "file version nums",version: "1.0.0" ,maxSize: 20 * 10274 * 1024 (20m));
  
  /// key name
  final String key = md5.convert(utf8.encode("https://xxxxx.com/xxx.png")).toString();
  
  /// write data to disk cache
  Editor? editor = await diskLruCache.edit(key);
  if (editor == null) {
    throw Exception("editor is null");
  }
  
  /// request image uint8List
  final Uint8List imageBytes = await getImageUintList();
  
  /// open io stream
  FaultHidingIOSink faultHidingIOSink = editor.newOutputIOSink(0);
  
  /// write uint8List to disk,but it is dirty,is not commited
  faultHidingIOSink.write(imageBytes);
  
  /// close the io stream
  await faultHidingIOSink.close();
  
  /// other way to write data to file
  /// The index needs the corresponding valuecount and cannot be greater than the valuecount. For example, if valuecount = = 1, the sequence
  /// number of the file version should be 0. On the contrary, if valuecount is multiple versions, 0 has started to increment as the version
  /// sequence number
  await editor.set(index, value);
  
  /// comfirm commit
  await editor.commit(diskLruCache);
  
  /// cancel commit
  await editor.abort(diskLruCache);
  
  /// get cache file information
  Snapshot? snapshot = await editor.get(key);
  
  /// request to valueCount version
  RandomAccessFile inV1 = snapshot.getRandomAccessFile(0);
  Uint8List bytes = inV1.readSync(inV1.lengthSync());
  
  /// edit snapshot
  Editor? editor = await diskLruCache.edit(snapshot.key,sequenceNumber: snapshot.sequenceNumber);
  
  /// remove cache
  await diskLruCache.remove(key);
  
  /// flush cache
  await diskLruCache.flush();
  
  /// close disk cache
  await diskLruCache.close();
  
  /// Closes the cache and deletes all of its stored values. This will delete
  /// all files in the cache directory including files that weren't created by the cache.
  await diskLruCache.delete();
}
```
