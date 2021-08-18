import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_disk_lru_cache/flutter_disk_lru_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() async {
  test(
    'test flutter disk lru cache',
    () async {
      DiskLruCache diskLruCache = await DiskLruCache.open(Directory("./disk"));
      try {
        for (int i = 0; i < 20; i++) {
          final key = md5
              .convert(
                utf8.encode(DateTime.now().microsecondsSinceEpoch.toString()),
              )
              .toString();
          Editor? editor = await diskLruCache.edit(key);
          if (editor == null) {
            throw Exception("editor为空");
          }
          final Uint8List imageBytes = await getBaiduImage();
          FaultHidingIOSink faultHidingIOSink = editor.newOutputIOSink(0);
          faultHidingIOSink.write(imageBytes);
          await faultHidingIOSink.close();
          await editor.commit(diskLruCache);
        }
        diskLruCache.flush();
        Snapshot? snapshot = await diskLruCache.get("25d55ad283aa400af464c76d713c07ad");
        if (snapshot == null) {
          print("snapshot对象为空");
          return;
        }
        RandomAccessFile inV1 = snapshot.getRandomAccessFile(0);
        Uint8List bytes = inV1.readSync(inV1.lengthSync());
        diskLruCache.edit(snapshot.key, sequenceNumber: snapshot.sequenceNumber);
        print(inV1.lengthSync()); // 138656
        print(bytes);
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
