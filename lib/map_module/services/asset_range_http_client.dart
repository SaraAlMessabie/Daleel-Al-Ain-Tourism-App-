import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Makes a bundled binary asset look like an HTTP server with byte-range
/// support. PMTiles can then read only the pieces it needs without any network.
class AssetRangeHttpClient extends http.BaseClient {
  AssetRangeHttpClient(this._bytes);

  final Uint8List _bytes;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw StateError('The offline map archive client is closed.');
    }

    final rangeHeader = request.headers['range'];
    var start = 0;
    var end = _bytes.length - 1;
    var statusCode = 200;

    if (rangeHeader != null) {
      final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(rangeHeader);
      if (match == null) {
        return _response(request, const <int>[], 416, <String, String>{
          'content-range': 'bytes */${_bytes.length}',
        });
      }

      start = int.parse(match.group(1)!);
      final requestedEnd = match.group(2);
      if (requestedEnd != null && requestedEnd.isNotEmpty) {
        end = int.parse(requestedEnd);
      }

      if (start >= _bytes.length || start > end) {
        return _response(request, const <int>[], 416, <String, String>{
          'content-range': 'bytes */${_bytes.length}',
        });
      }

      end = end.clamp(start, _bytes.length - 1);
      statusCode = 206;
    }

    final body = Uint8List.sublistView(_bytes, start, end + 1);
    final headers = <String, String>{
      'accept-ranges': 'bytes',
      'content-length': '${body.length}',
      'content-type': 'application/octet-stream',
      if (statusCode == 206)
        'content-range': 'bytes $start-$end/${_bytes.length}',
    };

    return _response(request, body, statusCode, headers);
  }

  http.StreamedResponse _response(
    http.BaseRequest request,
    List<int> body,
    int statusCode,
    Map<String, String> headers,
  ) {
    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      statusCode,
      contentLength: body.length,
      headers: headers,
      request: request,
    );
  }

  @override
  void close() {
    _closed = true;
    super.close();
  }
}
