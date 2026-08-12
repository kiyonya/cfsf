import 'dart:async';
import 'dart:io';

typedef StatusValidator =
    bool Function({required int statusCode, HttpHeaders? headers});

HttpClient createHttpClient({
  Duration timeout = const Duration(milliseconds: 5000),
  String? anycastIp,
}) {
  final httpClient = HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = (_, _, _) => true;

  httpClient.connectionFactory =
      (Uri uri, String? proxyHost, int? proxyPort) async {
        final timeoutDuration = timeout;
        final targetHost = uri.host;
        final connectHost = (anycastIp != null && anycastIp!.isNotEmpty)
            ? anycastIp!
            : targetHost;
        final connectPort = uri.port;
        final isHttps = uri.scheme.toLowerCase().startsWith('https');

        Socket? socket;
        try {
          socket = await Socket.connect(
            connectHost,
            connectPort,
            timeout: timeoutDuration,
          );
          if (isHttps) {
            socket = await SecureSocket.secure(
              socket!,
              host: targetHost,
              supportedProtocols: ['http/1.1'],
              onBadCertificate: (cert) => true,
            ).timeout(timeoutDuration);
          }
          return ConnectionTask.fromSocket(Future.value(socket), () {
            socket?.destroy();
          });
        } catch (_) {
          socket?.destroy();
          rethrow;
        }
      };
  return httpClient;
}

bool checkStatusCode({
  required int statusCode,
  StatusValidator? statusValidation,
  List<int>? allowedStatus,
  HttpHeaders? headers,
}) {
  if (statusValidation == null &&
      (allowedStatus == null || allowedStatus.isEmpty)) {
    return true;
  }
  bool isValid = false;
  if (statusValidation != null) {
    isValid = statusValidation(statusCode: statusCode, headers: headers);
  } else if (allowedStatus != null && allowedStatus.isNotEmpty) {
    isValid = allowedStatus.contains(statusCode);
  }
  return isValid;
}

/**
 * throwable
 */
Future<({String? colo, int status})> httpHead({
  required String url,
  Duration timeout = const Duration(milliseconds: 5000),
  String? anycastIp,
  List<int> allowedStatus = const [200, 201],
  StatusValidator? statusValidator,
}) async {
  final HttpClient client = createHttpClient(
    timeout: timeout,
    anycastIp: anycastIp,
  );
  try {
    final Uri uri = Uri.parse(url);
    final String hostname = uri.host;
    final request = await client.headUrl(uri);
    request.followRedirects = false;
    request.headers.set('Host', hostname);
    final response = await request.close().timeout(
      timeout,
      onTimeout: () {
        final TimeoutException e = TimeoutException('Response timeout');
        request.abort(e);
        throw e;
      },
    );
    
    final int statusCode = response.statusCode;

    if (statusCode == 525) {
      final String httpUrl = url.replaceFirst("https", "http");
      return httpHead(
        url: httpUrl,
        timeout: timeout,
        anycastIp: anycastIp,
        allowedStatus: allowedStatus,
        statusValidator: statusValidator,
      );
    }

    final bool isStatusCodeValid = checkStatusCode(
      statusCode: statusCode,
      statusValidation: statusValidator,
      allowedStatus: allowedStatus,
      headers: response.headers,
    );
    if (!isStatusCodeValid) {
      throw Exception("${statusCode} not satisfied");
    }

    String? colo = response.headers['cf-ray']?.first
        ?.split('-')
        .last
        .toUpperCase();
    return (status: statusCode, colo: colo);
  } catch (e) {
    rethrow;
  } finally {
    client.close(force: true);
  }
}

Future<({double speed, String? colo, int ttfb, int status})> httpDownload({
  required String url,
  Duration timeout = const Duration(milliseconds: 5000),
  Duration downloadTimeout = const Duration(milliseconds: 10000),
  String? anycastIp,
  int maxBytesRead = 1024 * 1024 * 10,
  List<int> allowedStatus = const [200, 201, 302, 307, 301],
  StatusValidator? statusValidator,
}) async {
  final HttpClient client = createHttpClient(
    timeout: timeout,
    anycastIp: anycastIp,
  );
  try {
    final Uri uri = Uri.parse(url);
    final String hostname = uri.host;
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    request.headers.set('Host', hostname);

    final ttfbStart = DateTime.now().millisecondsSinceEpoch;
    final response = await request.close().timeout(
      timeout,
      onTimeout: () {
        final TimeoutException e = TimeoutException('Response timeout');
        request.abort(e);
        throw e;
      },
    );

    final int statusCode = response.statusCode;
    if (statusCode == 525) {
      final String httpUrl = url.replaceFirst("https", "http");
      return httpDownload(
        url: httpUrl,
        timeout: timeout,
        downloadTimeout: downloadTimeout,
        anycastIp: anycastIp,
        maxBytesRead: maxBytesRead,
        allowedStatus: allowedStatus,
      );
    }

    final bool isStatusCodeValid = checkStatusCode(
      statusCode: statusCode,
      statusValidation: statusValidator,
      allowedStatus: allowedStatus,
      headers: response.headers,
    );
    if (!isStatusCodeValid) {
      throw Exception("${statusCode} not satisfied");
    }

    final ttfb = DateTime.now().millisecondsSinceEpoch - ttfbStart;
    String? colo = response.headers['cf-ray']?.first
        ?.split('-')
        .last
        .toUpperCase();
    double speed = 0.0;
    int bytesRead = 0;
    final Duration bodyTimeout = downloadTimeout;
    final Stopwatch downloadStopwatch = Stopwatch()..start();
    final int respReadStart = DateTime.now().microsecondsSinceEpoch;
    try {
      await for (final chunk in response.timeout(bodyTimeout)) {
        if (downloadStopwatch.elapsed > bodyTimeout) {
          throw TimeoutException('Download timeout');
        }
        bytesRead += chunk.length;
        if (bytesRead >= maxBytesRead) break;
      }
    } catch (e) {
      rethrow;
    } finally {

      final int respReadEnd = DateTime.now().microsecondsSinceEpoch;
      final double elapsedMicro = (respReadEnd - respReadStart).toDouble();
      if (bytesRead > 0 && elapsedMicro > 0) {
        speed = (bytesRead / (elapsedMicro / 1000000.0)).floorToDouble();
      } else {
        speed = 0.0;
      }
    }
    return (speed: speed, colo: colo, ttfb: ttfb, status: statusCode);
  } catch (e) {
    rethrow;
  } finally {
    client.close(force: true);
  }
}
