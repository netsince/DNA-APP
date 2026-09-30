import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:dna/island_app/api/client.dart';
import 'package:dna/island_app/auth_session.dart';
import 'package:dna/island_app/server_config.dart';

/// 带 JWT 认证头的网络图片提供器。
///
/// 用于加载需要登录才能访问的图片（如生图产出图/参考图 `/image-gen/output|reference/...`）。
/// 复用 [ApiClient] 的 HttpClient（共享连接池），请求带 `Authorization: Bearer <token>`。
class AuthNetworkImage extends ImageProvider<AuthNetworkImage> {
  AuthNetworkImage(this.url)
      : resolved = ServerConfig.resolveUrl(url);

  final String url;
  final String resolved;

  @override
  Future<AuthNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<AuthNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
      AuthNetworkImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      debugLabel: resolved,
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final bytes = await fetchAuthImageBytes(resolved);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is AuthNetworkImage && other.resolved == resolved;

  @override
  int get hashCode => resolved.hashCode;
}

/// 带 JWT 认证头拉取图片原始字节（生图产出图/参考图等需要登录的资源）。
///
/// 供 [AuthNetworkImage] 解码与下载/保存复用。
Future<Uint8List> fetchAuthImageBytes(String url) async {
  final resolved = url.startsWith('http') ? url : ServerConfig.resolveUrl(url);
  final client = ApiClient.instance.httpClient;
  final token = AuthSession.instance.token;
  final request = await client.getUrl(Uri.parse(resolved));
  if (token != null && token.isNotEmpty) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  if (response.statusCode != 200) {
    throw HttpException('图片加载失败：${response.statusCode}',
        uri: Uri.parse(resolved));
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
