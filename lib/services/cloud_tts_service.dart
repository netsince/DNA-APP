import 'dart:async';
import 'dart:convert';

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts/tts_player.dart';

/// 一次云端合成结果。
class CloudTtsClip {
  const CloudTtsClip({
    required this.url,
    required this.seconds,
    this.voice,
    this.files = const <String>[],
  });

  /// 可直接播放的音频地址（绝对 URL）。
  final String url;

  /// 时长（秒），用于 UI 提示。
  final double seconds;

  /// 实际使用的音色名（由 bridge 决定）。
  final String? voice;

  /// 直连模式下已下载到本机的音频文件（按顺序播放）。
  final List<String> files;
}

/// 云端语音合成服务。
///
/// 合成不在 Dart 侧直连厂商：密钥、角色→音色映射、动作描写清洗、缓存都在本机的
/// dna-bridge（Node 服务，默认 http://127.0.0.1:8791）里完成。DNA 只做两件事：
/// 把文本交给 bridge，拿到音频地址后用 audioplayers 播放。
///
/// 这样换厂商、改音色、调节语速都不需要重新编译 DNA。
class CloudTtsService {
  CloudTtsService._();

  static final CloudTtsService instance = CloudTtsService._();

  static const String _kEnabled = 'cloud_tts_enabled';
  static const String _kBaseUrl = 'cloud_tts_base_url';
  static const String _kVoice = 'cloud_tts_voice';
  static const String _kMode = 'cloud_tts_mode';
  static const String _kApiBase = 'cloud_tts_api_base';
  static const String _kApiKey = 'cloud_tts_api_key';
  static const String _kApiModel = 'cloud_tts_api_model';

  /// 直连模式下的「角色 → 音色」映射（本机保存，等价于桌面端 tts.config.json 的 voiceMap）。
  static const String _kCharVoices = 'cloud_tts_char_voices';

  /// bridge 控制台的默认地址。
  static const String kDefaultBaseUrl = 'http://127.0.0.1:8791';

  /// 直连模式下的默认厂商地址与音色。
  static const String kDefaultApiBase = 'https://api.breeze.blue';
  static const String kDefaultApiModel = 'breeze-tts-2';
  static const String kDefaultVoiceId = 'voc_848ke6mwrvdr';

  /// `bridge` = 交给本机 dna-bridge（桌面端默认）；
  /// `direct` = 手机端直连 TTS 厂商 API（Android 默认）。
  static const String kModeBridge = 'bridge';
  static const String kModeDirect = 'direct';

  bool _enabled = false;
  String _baseUrl = kDefaultBaseUrl;
  String _voice = '';
  String _mode = kModeBridge;
  String _apiBase = kDefaultApiBase;
  String _apiKey = '';
  String _apiModel = kDefaultApiModel;
  bool _loaded = false;

  /// 直连模式的角色音色表：角色名 → 音色 id（空串表示跟随全局）。
  Map<String, String> _charVoices = <String, String>{};

  bool get enabled => _enabled;
  String get baseUrl => _baseUrl;

  /// 是否直连厂商（手机端没有本机 Node 服务时用）。
  bool get directMode => _mode == kModeDirect;
  String get mode => _mode;
  String get apiBase => _apiBase;
  String get apiModel => _apiModel;
  bool get hasApiKey => _apiKey.trim().isNotEmpty;

  /// 选中的音色 id；空串表示「按角色名自动匹配」。
  String get voice => _voice;

  /// 从本地偏好读取配置（幂等，可重复调用）。
  Future<void> load() async {
    if (_loaded) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kEnabled) ?? false;
    _voice = prefs.getString(_kVoice) ?? '';
    final String? saved = prefs.getString(_kBaseUrl);
    _baseUrl =
        (saved == null || saved.trim().isEmpty) ? kDefaultBaseUrl : saved.trim();
    // 手机端默认直连厂商；桌面端默认走本机 bridge。
    final String? mode = prefs.getString(_kMode);
    _mode = (mode == kModeDirect || mode == kModeBridge)
        ? mode!
        : (Platform.isAndroid || Platform.isWindows
            ? kModeDirect
            : kModeBridge);
    final String? apiBase = prefs.getString(_kApiBase);
    _apiBase = (apiBase == null || apiBase.trim().isEmpty)
        ? kDefaultApiBase
        : apiBase.trim();
    // 老版本在桌面端默认存成 bridge（走本机 127.0.0.1 的 node 服务）。
    // 打包版已经不带那个服务了，留着 bridge 只会「点了没声」——
    // 只要地址指向本机，就在加载时迁移成直连并落盘一次。
    if (_mode == kModeBridge &&
        (Platform.isAndroid || Platform.isWindows) &&
        (_baseUrl.contains('127.0.0.1') || _baseUrl.contains('localhost'))) {
      _mode = kModeDirect;
      await prefs.setString(_kMode, kModeDirect);
    }
    _apiKey = prefs.getString(_kApiKey) ?? '';
    final String? model = prefs.getString(_kApiModel);
    _apiModel = (model == null || model.trim().isEmpty)
        ? kDefaultApiModel
        : model.trim();
    final String? charVoices = prefs.getString(_kCharVoices);
    _charVoices = <String, String>{};
    if (charVoices != null && charVoices.trim().isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(charVoices);
        if (decoded is Map) {
          _charVoices = <String, String>{
            for (final MapEntry<Object?, Object?> e in decoded.entries)
              if ('${e.key}'.trim().isNotEmpty) '${e.key}': '${e.value ?? ''}',
          };
        }
      } catch (_) {
        // 配置坏了就当没配过，不影响朗读。
      }
    }
    _loaded = true;
  }

  /// 切换 bridge / direct（手机端一般不用改）。
  Future<void> setMode(String mode) async {
    _mode = mode == kModeDirect ? kModeDirect : kModeBridge;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, _mode);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  Future<void> setBaseUrl(String value) async {
    final String v = value.trim().isEmpty ? kDefaultBaseUrl : value.trim();
    _baseUrl = v;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, v);
  }

  /// 合成并由本机 bridge 播放，等播完再返回。
  ///
  /// DNA 侧刻意不碰 audioplayers：实测这套构建里播 mp3 会在
  /// Media Foundation 路径上直接崩进程（MSVCP140.dll 访问违例）。
  /// bridge 用 WPF MediaPlayer 播，稳。
  Future<CloudTtsClip> speakAndPlay(
    String text, {
    String? voice,
    String? characterId,
    String? characterName,
  }) async {
    await load();
    if (directMode) {
      return _speakAndPlayDirect(
        text,
        voice: voice,
        characterName: characterName,
      );
    }
    final String chosen = (voice ?? _voice).trim();
    final Map<String, Object?> body = <String, Object?>{
      'text': text,
      if (chosen.isNotEmpty) 'voice': chosen,
      if (characterId != null && characterId.isNotEmpty) 'characterId': characterId,
    };
    final http.Response res = await http
        .post(
          _uri('/api/play'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 10));
    if (res.statusCode != 200) {
      throw CloudTtsException('语音服务返回 HTTP ${res.statusCode}');
    }
    final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const CloudTtsException('语音服务返回格式异常');
    }
    if (decoded['ok'] != true) {
      throw CloudTtsException('${decoded['error'] ?? '合成失败'}');
    }
    final String path = '${decoded['url'] ?? ''}';
    final String base = _baseUrl.replaceAll(RegExp(r'/+$'), '');
    return CloudTtsClip(
      url: path.startsWith('http') ? path : '$base$path',
      seconds: (decoded['seconds'] as num?)?.toDouble() ?? 0,
      voice: decoded['voice'] as String?,
    );
  }

  /// 停止播放（bridge 播放或手机端本地播放）。
  Future<void> stopPlayback() async {
    if (directMode) {
      await TtsPlayer.instance.stop();
      return;
    }
    try {
      await http.post(_uri('/api/stop')).timeout(const Duration(seconds: 3));
    } catch (_) {
      // 服务没起或已停，忽略
    }
  }

  /// 选择音色（空串 = 按角色名自动匹配）。
  Future<void> setVoice(String id) async {
    _voice = id;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVoice, id);
  }

  /// 从 bridge 拉可选音色（Breeze 账户里的中文音色），失败返回空列表。
  Future<List<CloudTtsVoice>> listVoices() async {
    await load();
    if (directMode) return _listVoicesDirect();
    try {
      final http.Response res = await http
          .get(_uri('/api/voices'))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const <CloudTtsVoice>[];
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! List) return const <CloudTtsVoice>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> m) => CloudTtsVoice(
                id: '${m['id'] ?? ''}',
                label: '${m['label'] ?? m['id'] ?? ''}',
              ))
          .toList();
    } catch (_) {
      return const <CloudTtsVoice>[];
    }
  }
  /// 角色 → 音色映射（桌面端来自 bridge 的 tts.config.json voiceMap；
  /// 直连模式读本机保存的表）。
  Future<List<CloudCharVoice>> listCharacterVoices() async {
    await load();
    if (directMode) {
      final List<CloudCharVoice> local = _charVoices.entries
          .map((MapEntry<String, String> e) => CloudCharVoice(
                id: e.key,
                name: e.key,
                voice: e.value,
              ))
          .toList();
      return local;
    }
    try {
      final http.Response res = await http
          .get(_uri('/api/voice-map'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const <CloudCharVoice>[];
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) return const <CloudCharVoice>[];
      final Object? chars = decoded['characters'];
      if (chars is! List) return const <CloudCharVoice>[];
      return chars
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> m) => CloudCharVoice(
                id: '${m['id'] ?? ''}',
                name: '${m['name'] ?? ''}',
                voice: '${m['voice'] ?? ''}',
              ))
          .where((CloudCharVoice c) => c.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const <CloudCharVoice>[];
    }
  }

  /// 给某个角色单独指定音色（空串 = 跟随全局/自动）。
  Future<bool> setCharacterVoice(String name, String voiceId) async {
    await load();
    if (directMode) {
      final String key = name.trim();
      if (key.isEmpty) return false;
      if (voiceId.trim().isEmpty) {
        _charVoices.remove(key);
      } else {
        _charVoices[key] = voiceId.trim();
      }
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCharVoices, jsonEncode(_charVoices));
      return true;
    }
    try {
      final http.Response res = await http
          .post(
            _uri('/api/voice-map'),
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(<String, Object?>{'name': name, 'voice': voiceId}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
      return decoded is Map<String, dynamic> && decoded['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 把合成好的音频下载到临时文件，返回本地路径。
  ///
  /// 为什么不直接播 HTTP 地址：audioplayers 的 Windows 实现在 UrlSource 上会走
  /// Media Foundation 流式路径，实测会直接把进程打崩（MSVCP140.dll 访问违例）。
  /// 官方原有的播放路径是本地文件，稳。
  Future<String> downloadToTemp(String url) async {
    final http.Response res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw CloudTtsException('下载音频失败 HTTP ${res.statusCode}');
    }
    final Directory dir = await getTemporaryDirectory();
    final String path =
        '${dir.path}${Platform.pathSeparator}cloud_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final File file = File(path);
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return path;
  }

  /// 读取语音服务的 API 配置（地址 / 模型 / Key 是否已填）。
  Future<CloudTtsApiConfig?> getApiConfig() async {
    await load();
    if (directMode) return _localApiConfig();
    try {
      final http.Response res = await http
          .get(_uri('/api/config'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final Object? key = decoded['apiKey'];
      return CloudTtsApiConfig(
        baseUrl: '${decoded['baseUrl'] ?? ''}',
        model: '${decoded['model'] ?? ''}',
        hasKey: key is Map<String, dynamic> && key['present'] == true,
        maskedKey: key is Map<String, dynamic> ? '${key['masked'] ?? ''}' : '',
      );
    } catch (_) {
      return null;
    }
  }

  /// 保存 API 配置到本机语音服务（Key 只留在本机 tts.config.json）。
  Future<CloudTtsApiConfig?> saveApiConfig({
    String? baseUrl,
    String? apiKey,
    String? model,
  }) async {
    await load();
    if (directMode) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (baseUrl != null && baseUrl.trim().isNotEmpty) {
        _apiBase = baseUrl.trim();
        await prefs.setString(_kApiBase, _apiBase);
      }
      if (apiKey != null) {
        _apiKey = apiKey.trim();
        await prefs.setString(_kApiKey, _apiKey);
      }
      if (model != null && model.trim().isNotEmpty) {
        _apiModel = model.trim();
        await prefs.setString(_kApiModel, _apiModel);
      }
      return _localApiConfig();
    }
    try {
      final http.Response res = await http
          .post(
            _uri('/api/config'),
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(<String, Object?>{
              if (baseUrl != null) 'baseUrl': baseUrl,
              if (apiKey != null) 'apiKey': apiKey,
              if (model != null) 'model': model,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final Object? key = decoded['apiKey'];
      return CloudTtsApiConfig(
        baseUrl: '${decoded['baseUrl'] ?? ''}',
        model: '${decoded['model'] ?? ''}',
        hasKey: key is Map<String, dynamic> && key['present'] == true,
        maskedKey: key is Map<String, dynamic> ? '${key['masked'] ?? ''}' : '',
      );
    } catch (_) {
      return null;
    }
  }

  Uri _uri(String path) {
    final String base = _baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  // ---------------------------------------------------------------------------
  // 直连厂商（手机端）：DNA 自己调 TTS 接口、自己播放
  // ---------------------------------------------------------------------------

  String get _apiBaseClean => _apiBase.replaceAll(RegExp(r'/+$'), '');

  /// 直连模式选音色：显式传入 > 该角色的单独音色 > 全局音色 > 默认。
  String _pickedVoiceId(String? voice, {String? characterName}) {
    final String v = (voice ?? '').trim();
    if (v.isNotEmpty) return v;
    final String name = (characterName ?? '').trim();
    if (name.isNotEmpty) {
      final String mapped = (_charVoices[name] ?? '').trim();
      if (mapped.isNotEmpty) return mapped;
    }
    final String sel = _voice.trim();
    if (sel.isNotEmpty) return sel;
    return kDefaultVoiceId;
  }

  /// 去掉（动作描写）【】[]，只留台词；台词为空时回退原文。
  String _stripActions(String text) {
    String out = text
        .replaceAll(RegExp(r'（[^）]*）'), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\*[^*]*\*'), '')
        .trim();
    if (out.isEmpty) out = text.trim();
    return out;
  }

  /// 按标点切成不超过 [maxLen] 的片段，避免单次请求过长。
  List<String> _splitText(String text, int maxLen) {
    const String punct = '。！？!?；;…\n';
    final List<String> sentences = <String>[];
    final StringBuffer cur = StringBuffer();
    for (final int code in text.runes) {
      final String ch = String.fromCharCode(code);
      cur.write(ch);
      if (punct.contains(ch)) {
        final String s = cur.toString().trim();
        if (s.isNotEmpty) sentences.add(s);
        cur.clear();
      }
    }
    if (cur.toString().trim().isNotEmpty) sentences.add(cur.toString().trim());

    final List<String> out = <String>[];
    final StringBuffer buf = StringBuffer();
    for (final String s in sentences) {
      if (s.length > maxLen) {
        if (buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
        for (int i = 0; i < s.length; i += maxLen) {
          out.add(s.substring(
              i, i + maxLen > s.length ? s.length : i + maxLen));
        }
        continue;
      }
      if (buf.length + s.length > maxLen && buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
      buf.write(s);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out.where((String s) => s.trim().isNotEmpty).toList();
  }

  Future<CloudTtsClip> _speakDirect(
    String text, {
    String? voice,
    String? characterName,
  }) async {
    final String key = _apiKey.trim();
    if (key.isEmpty) {
      throw const CloudTtsException(
          '还没有填 API Key：到「设置 → 端侧语音合成 → 云端语音合成」填上再试');
    }
    final String clean = _stripActions(text);
    if (clean.trim().isEmpty) {
      throw const CloudTtsException('没有可朗读的台词');
    }
    final String voiceId =
        _pickedVoiceId(voice, characterName: characterName);
    final List<String> files = <String>[];
    double seconds = 0;
    for (final String chunk in _splitText(clean, 180)) {
      final Uri uri = Uri.parse(
          '$_apiBaseClean/v1/text-to-speech/$voiceId?output_format=mp3');
      final http.Response res = await http
          .post(
            uri,
            headers: <String, String>{
              'xi-api-key': key,
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'text': chunk,
              'language_code': 'zh',
              'model_id': _apiModel,
              'voice_settings': <String, Object?>{'speed': 1.0},
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        throw CloudTtsException(_friendlyHttpError(res));
      }
      final Directory dir = await getTemporaryDirectory();
      final File f = File(
          '${dir.path}${Platform.pathSeparator}cloud_tts_${DateTime.now().microsecondsSinceEpoch}.mp3');
      await f.writeAsBytes(res.bodyBytes, flush: true);
      files.add(f.path);
      // mp3 约 16KB/s（128kbps），用于 UI 上的时长提示
      seconds += res.bodyBytes.length / 16000.0;
    }
    return CloudTtsClip(
      url: files.isNotEmpty ? files.first : '',
      seconds: double.parse(seconds.toStringAsFixed(2)),
      voice: voiceId,
      files: files,
    );
  }

  String _friendlyHttpError(http.Response res) {
    String detail = '';
    try {
      detail = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (detail.length > 160) detail = detail.substring(0, 160);
    } catch (_) {}
    if (res.statusCode == 401 || res.statusCode == 403) {
      return 'API Key 无效或没有权限（HTTP ${res.statusCode}）';
    }
    return '合成失败 HTTP ${res.statusCode}${detail.isEmpty ? '' : '：$detail'}';
  }

  Future<CloudTtsClip> _speakAndPlayDirect(
    String text, {
    String? voice,
    String? characterName,
  }) async {
    final CloudTtsClip clip =
        await _speakDirect(text, voice: voice, characterName: characterName);
    for (final String file in clip.files) {
      await TtsPlayer.instance.playFile(file);
      await _waitPlaybackDone();
    }
    return clip;
  }

  /// 等本地播放结束（`TtsPlayer.playing` 会自然归位）。
  Future<void> _waitPlaybackDone() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final Stopwatch sw = Stopwatch()..start();
    while (TtsPlayer.instance.playing.value &&
        sw.elapsed < const Duration(minutes: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  /// 直连模式下拉音色列表（厂商 /v1/voices）。
  Future<List<CloudTtsVoice>> _listVoicesDirect() async {
    if (!hasApiKey) return const <CloudTtsVoice>[];
    try {
      final http.Response res = await http
          .get(Uri.parse('$_apiBaseClean/v1/voices'),
              headers: <String, String>{'xi-api-key': _apiKey.trim()})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const <CloudTtsVoice>[];
      final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final Object? list = decoded is Map<String, dynamic>
          ? decoded['voices']
          : decoded;
      if (list is! List) return const <CloudTtsVoice>[];
      return list
          .whereType<Map<String, dynamic>>()
          .where((Map<String, dynamic> m) =>
              '${m['language_code'] ?? 'zh'}'.startsWith('zh'))
          .map((Map<String, dynamic> m) => CloudTtsVoice(
                id: '${m['voice_id'] ?? m['id'] ?? ''}',
                label: '${m['name'] ?? m['voice_id'] ?? ''}',
              ))
          .where((CloudTtsVoice v) => v.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const <CloudTtsVoice>[];
    }
  }

  /// 按句末标点切分（直连模式分块用）。
  CloudTtsApiConfig _localApiConfig() => CloudTtsApiConfig(
        baseUrl: _apiBase,
        model: _apiModel,
        hasKey: hasApiKey,
        maskedKey: _maskKey(_apiKey),
      );

  String _maskKey(String key) {
    final String k = key.trim();
    if (k.isEmpty) return '';
    if (k.length <= 8) return '${k.substring(0, 2)}…';
    return '${k.substring(0, 6)}…${k.substring(k.length - 4)}（${k.length} 字符）';
  }

  /// bridge 是否在线。
  Future<bool> ping({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final http.Response r = await http.get(_uri('/api/state')).timeout(timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 合成一句话，返回可播放的音频地址。
  Future<CloudTtsClip> speak(
    String text, {
    String? voice,
    String? characterName,
  }) async {
    await load();
    if (directMode) {
      return _speakDirect(text, voice: voice, characterName: characterName);
    }
    final Map<String, Object?> body = <String, Object?>{
      'text': text,
      if (voice != null && voice.isNotEmpty) 'voice': voice,
    };
    final http.Response res = await http
        .post(
          _uri('/api/say'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw CloudTtsException('语音服务返回 HTTP ${res.statusCode}');
    }
    final Object? decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const CloudTtsException('语音服务返回格式异常');
    }
    if (decoded['ok'] != true) {
      throw CloudTtsException('${decoded['error'] ?? '合成失败'}');
    }
    final String path = '${decoded['url'] ?? ''}';
    final String base = _baseUrl.replaceAll(RegExp(r'/+$'), '');
    return CloudTtsClip(
      url: path.startsWith('http') ? path : '$base$path',
      seconds: (decoded['seconds'] as num?)?.toDouble() ?? 0,
      voice: decoded['voice'] as String?,
    );
  }
}

/// 云端合成失败（服务未启动、额度不足、网络错误等）。
class CloudTtsException implements Exception {
  const CloudTtsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一个可选音色。
class CloudTtsVoice {
  const CloudTtsVoice({required this.id, required this.label});

  final String id;
  final String label;
}

/// 语音服务里的 API 配置（Key 只在服务端保存，界面只拿掩码）。
class CloudTtsApiConfig {
  const CloudTtsApiConfig({
    required this.baseUrl,
    required this.model,
    required this.hasKey,
    required this.maskedKey,
  });

  final String baseUrl;
  final String model;
  final bool hasKey;
  final String maskedKey;
}

/// 一个角色当前使用的音色。
class CloudCharVoice {
  const CloudCharVoice({required this.id, required this.name, required this.voice});

  final String id;
  final String name;
  final String voice;
}