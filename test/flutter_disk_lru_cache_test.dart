import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_disk_lru_cache/flutter_disk_lru_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() async {
  test(
    'test flutter disk lru cache',
    () async {
      DiskLruCache diskLruCache = await DiskLruCache.open(Directory("./disk"));
      try {
        final key = "1ed614ecb59ddb04e42338ae77f446ef";
        Editor? editor = await diskLruCache.edit(key);
        if (editor == null) {
          throw Exception("editor为空");
        }
        final Uint8List imageBytes = await getBaiduImage();
        FaultHidingIOSink faultHidingIOSink = editor.newOutputIOSink(0);
        await faultHidingIOSink.writeByte(imageBytes);
        await faultHidingIOSink.flush();
        await faultHidingIOSink.close();
        await editor.commit(diskLruCache);
        diskLruCache.flush();
        Snapshot? snapshot = await diskLruCache.get(key);
        if (snapshot == null) {
          print("snapshot对象为空");
          return;
        }
        RandomAccessFile randomAccessFile = snapshot.getRandomAccessFile(0);
        randomAccessFile.readSync(snapshot.getLength(0));
        snapshot.close();
      } catch (e) {
        print(e);
      }
      diskLruCache.close();
    },
  );
}

Future<Uint8List> getBaiduImage() async {
  final HttpClient client = HttpClient();
  final HttpClientRequest request = await client.openUrl(
    "GET",
    Uri.parse("https://pic.rmb.bdstatic.com/bjh/down/ce1d02ad141d9f1ba0799bd503d7243e.jpeg"),
  );
  final HttpClientResponse response = await request.close();

  final Completer<Uint8List> completer = Completer<Uint8List>.sync();
  final List<List<int>> chunks = <List<int>>[];
  int contentLength = 0;
  response.listen(
    (List<int> chunk) {
      chunks.add(chunk);
      contentLength += chunk.length;
    },
    onDone: () {
      final Uint8List bytes = Uint8List(contentLength);
      int offset = 0;
      for (List<int> chunk in chunks) {
        bytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      completer.complete(bytes);
    },
    onError: completer.completeError,
    cancelOnError: true,
  );
  return completer.future;
}
