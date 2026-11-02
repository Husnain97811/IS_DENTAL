import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' show SHA256Digest;
import 'package:url_launcher/url_launcher.dart';
import 'package:is_dental/core/constants/views.dart';

import 'drive_config.dart';

/// The Google sign-in of THIS computer, kept in the encrypted database.
class DriveTokens {
  const DriveTokens({
    required this.refresh,
    required this.access,
    required this.expiry,
    this.email = '',
  });
  final String refresh, access, email;
  final DateTime expiry;

  Map<String, dynamic> toJson() => {
    'refresh': refresh,
    'access': access,
    'expiry': expiry.toUtc().toIso8601String(),
    'email': email,
  };

  factory DriveTokens.fromJson(Map<String, dynamic> j) => DriveTokens(
    refresh: '${j['refresh'] ?? ''}',
    access: '${j['access'] ?? ''}',
    expiry: DateTime.tryParse('${j['expiry']}') ?? DateTime(2000),
    email: '${j['email'] ?? ''}',
  );

  DriveTokens copyWith({String? access, DateTime? expiry, String? email}) =>
      DriveTokens(
        refresh: refresh,
        access: access ?? this.access,
        expiry: expiry ?? this.expiry,
        email: email ?? this.email,
      );
}

class DriveException implements Exception {
  DriveException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// A file DentOS keeps in the clinic's Drive folder.
class DriveFile {
  const DriveFile(this.id, this.name, this.props, this.createdTime);
  final String id, name;
  final Map<String, String> props;
  final DateTime? createdTime;
}

/// Sign-in (OAuth "installed app" flow with PKCE on a loopback port) and
/// the handful of Drive REST calls DentOS needs. No Google SDK — plain
/// HTTPS, so nothing else to install or keep up to date.
class DriveClient {
  DriveClient(this._db);
  final AppDatabase _db;
  final _http = http.Client();

  static const _kTokens = 'gdrive_tokens';
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';
  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const folderMime = 'application/vnd.google-apps.folder';

  DriveTokens? _t;

  // ─────────────────────────────────────────────────────────── sign-in ──
  Future<DriveTokens?> tokens() async {
    if (_t != null) return _t;
    final raw = await _db.getSetting(_kTokens);
    if (raw == null || raw.isEmpty) return null;
    try {
      return _t = DriveTokens.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(DriveTokens? t) async {
    _t = t;
    await _db.setSetting(_kTokens, t == null ? '' : jsonEncode(t.toJson()));
  }

  /// Opens the browser for the clinic's Google sign-in and waits (up to 5
  /// minutes) for the answer on a one-time local port.
  Future<DriveTokens> connect() async {
    if (!DriveConfig.configured) {
      throw DriveException('Google Drive is not set up in this DentOS build.');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final verifier = _randomUrlSafe(48);
    final challenge = base64Url
        .encode(_sha256(utf8.encode(verifier)))
        .replaceAll('=', '');
    final state = _randomUrlSafe(16);

    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': DriveConfig.clientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': DriveConfig.scope,
      'access_type': 'offline', // a refresh token, so it keeps working
      'prompt': 'consent',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
    });

    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw DriveException('Could not open the browser.');
      }
      String? code;
      String? error;
      await for (final req in server.timeout(const Duration(minutes: 5))) {
        final q = req.uri.queryParameters;
        if (q['state'] != state) {
          req.response.statusCode = 404;
          await req.response.close();
          continue;
        }
        code = q['code'];
        error = q['error'];
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_doneHtml(code != null));
        await req.response.close();
        break;
      }
      if (code == null) {
        throw DriveException(
          error == 'access_denied'
              ? 'Google sign-in was cancelled.'
              : 'Google sign-in did not finish.',
        );
      }

      final res = await _http.post(
        Uri.parse(_tokenUrl),
        body: {
          'code': code,
          'client_id': DriveConfig.clientId,
          'client_secret': DriveConfig.clientSecret,
          'redirect_uri': redirect,
          'grant_type': 'authorization_code',
          'code_verifier': verifier,
        },
      );
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final refresh = j['refresh_token'] as String?;
      if (res.statusCode != 200 || refresh == null) {
        throw DriveException(
          'Google did not give DentOS lasting access '
          '(${j['error_description'] ?? j['error'] ?? res.statusCode}).',
        );
      }
      var t = DriveTokens(
        refresh: refresh,
        access: '${j['access_token']}',
        expiry: DateTime.now().add(
          Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3000),
        ),
      );
      await _save(t);
      try {
        final about = await getJson(
          '$_api/about',
          query: {'fields': 'user(emailAddress)'},
        );
        t = t.copyWith(email: '${about['user']?['emailAddress'] ?? ''}');
        await _save(t);
      } catch (_) {}
      return t;
    } on TimeoutException {
      throw DriveException('Google sign-in took too long. Try again.');
    } finally {
      await server.close(force: true);
    }
  }

  /// Forgets this computer's Google sign-in (and tells Google).
  Future<void> disconnect() async {
    final t = await tokens();
    if (t != null) {
      try {
        await _http
            .post(
              Uri.parse('https://oauth2.googleapis.com/revoke'),
              body: {'token': t.refresh},
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    await _save(null);
  }

  Future<String> _access() async {
    final t = await tokens();
    if (t == null) throw DriveException('Google Drive is not connected.');
    if (t.expiry.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return t.access;
    }
    final res = await _http
        .post(
          Uri.parse(_tokenUrl),
          body: {
            'client_id': DriveConfig.clientId,
            'client_secret': DriveConfig.clientSecret,
            'refresh_token': t.refresh,
            'grant_type': 'refresh_token',
          },
        )
        .timeout(const Duration(seconds: 20));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      if (j['error'] == 'invalid_grant') {
        await _save(null); // revoked or expired — must sign in again
        throw DriveException(
          'Google Drive access has ended. Connect Google Drive again.',
          401,
        );
      }
      throw DriveException('Could not reach Google (${res.statusCode}).');
    }
    final next = t.copyWith(
      access: '${j['access_token']}',
      expiry: DateTime.now().add(
        Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3000),
      ),
    );
    await _save(next);
    return next.access;
  }

  // ─────────────────────────────────────────────────────────── REST ──
  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final req = http.Request(method, url)
        ..headers.addAll({
          'Authorization': 'Bearer ${await _access()}',
          ...?headers,
        });
      if (body is String) req.body = body;
      if (body is List<int>) req.bodyBytes = body;
      final res = await http.Response.fromStream(
        await _http.send(req).timeout(timeout),
      ).timeout(timeout);
      if (res.statusCode == 401 && attempt == 0) {
        // token expired early — refresh and try once more
        final t = await tokens();
        if (t != null) await _save(t.copyWith(expiry: DateTime(2000)));
        continue;
      }
      if (res.statusCode >= 400) {
        throw DriveException(
          'Google Drive refused the request (${res.statusCode}).',
          res.statusCode,
        );
      }
      return res;
    }
    throw DriveException('Google Drive refused the request (401).', 401);
  }

  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String>? query,
  }) async {
    final res = await _send(
      'GET',
      Uri.parse(url).replace(queryParameters: query),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Every file matching [q], following pages.
  Future<List<DriveFile>> list(
    String q, {
    String orderBy = 'createdTime',
  }) async {
    final out = <DriveFile>[];
    String? page;
    do {
      final j = await getJson(
        '$_api/files',
        query: {
          'q': q,
          'spaces': 'drive',
          'orderBy': orderBy,
          'pageSize': '1000',
          'fields': 'nextPageToken,files(id,name,appProperties,createdTime)',
          if (page != null) 'pageToken': page,
        },
      );
      for (final f in (j['files'] as List? ?? const [])) {
        final m = f as Map<String, dynamic>;
        out.add(
          DriveFile(
            '${m['id']}',
            '${m['name'] ?? ''}',
            {
              for (final e
                  in ((m['appProperties'] as Map?) ?? const {}).entries)
                '${e.key}': '${e.value}',
            },
            DateTime.tryParse('${m['createdTime']}'),
          ),
        );
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<String> createFolder(String name, Map<String, String> props) async {
    final res = await _send(
      'POST',
      Uri.parse('$_api/files?fields=id'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({
        'name': name,
        'mimeType': folderMime,
        'appProperties': props,
      }),
    );
    return '${(jsonDecode(res.body) as Map)['id']}';
  }

  /// Resumable upload — works the same for a 50 KB photo and a 60 MB scan.
  Future<String> upload({
    required String folderId,
    required String name,
    required Uint8List bytes,
    required Map<String, String> props,
  }) async {
    final start = await _send(
      'POST',
      Uri.parse('$_upload/files?uploadType=resumable&fields=id'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': '${bytes.length}',
      },
      body: jsonEncode({
        'name': name,
        'parents': [folderId],
        'appProperties': props,
      }),
    );
    final session = start.headers['location'];
    if (session == null) throw DriveException('Upload could not start.');
    final res = await _send(
      'PUT',
      Uri.parse(session),
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
      timeout: const Duration(minutes: 10),
    );
    return '${(jsonDecode(res.body) as Map)['id']}';
  }

  Future<Uint8List> download(String fileId) async {
    final res = await _send(
      'GET',
      Uri.parse('$_api/files/$fileId?alt=media'),
      timeout: const Duration(minutes: 10),
    );
    return res.bodyBytes;
  }

  Future<void> delete(String fileId) async {
    try {
      await _send('DELETE', Uri.parse('$_api/files/$fileId'));
    } on DriveException catch (e) {
      if (e.status != 404) rethrow; // already gone is fine
    }
  }

  // ─────────────────────────────────────────────────────────── helpers ──
  static String _randomUrlSafe(int bytes) {
    final r = Random.secure();
    return base64Url
        .encode(List.generate(bytes, (_) => r.nextInt(256)))
        .replaceAll('=', '');
  }

  static Uint8List _sha256(List<int> data) =>
      SHA256Digest().process(Uint8List.fromList(data));

  static String _doneHtml(bool ok) =>
      '<!doctype html><html><head><meta charset="utf-8"><title>DentOS</title>'
      '<style>body{font-family:system-ui,sans-serif;background:#eef3f9;'
      'display:grid;place-items:center;height:100vh;margin:0;color:#0d1626}'
      '.c{background:#fff;padding:40px 48px;border-radius:18px;'
      'box-shadow:0 12px 32px rgba(13,22,38,.08);text-align:center}'
      'h1{font-size:22px;margin:0 0 8px}p{color:#64748b;margin:0}</style>'
      '</head><body><div class="c"><h1>'
      '${ok ? 'Google Drive is connected' : 'Sign-in was not completed'}'
      '</h1><p>You can close this window and go back to DentOS.</p>'
      '</div></body></html>';
}
