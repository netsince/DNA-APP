// 该文件必须使用 onnxruntime 的私有绑定（src/bindings/...），因为官方包
// 未公开导出这些低层 FFI 类型（OrtApi/OrtValue 等）。
// ignore_for_file: implementation_imports
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;

/// 一个已加载的 ONNX 会话的轻量封装，便于按名称喂入/取出张量。
class OrtSessionWrapper {
  OrtSessionWrapper(this._session, this._options);

  final OrtSession _session;
  final OrtSessionOptions _options;

  /// 以指定输入运行，返回按 [outputNames] 顺序的 [OrtValue]。
  /// [floatInputs]/[intInputs]：输入名 -> 扁平 Float32List/Int64List；
  /// [shapes]：输入名 -> 形状。
  List<OrtValue> run(
    Map<String, Float32List> floatInputs,
    Map<String, Int64List> intInputs,
    Map<String, List<int>> shapes, {
    List<String>? outputNames,
  }) {
    final Map<String, OrtValue> feeds = <String, OrtValue>{};
    for (final String name in floatInputs.keys) {
      feeds[name] = _floatTensor(floatInputs[name]!, shapes[name]!);
    }
    for (final String name in intInputs.keys) {
      feeds[name] = _int64Tensor(intInputs[name]!, shapes[name]!);
    }
    final OrtRunOptions runOpts = OrtRunOptions();
    try {
      final List<OrtValue?> raw = _session.run(
        runOpts,
        feeds,
        outputNames ?? _session.outputNames,
      );
      final List<OrtValue> out = raw.whereType<OrtValue>().toList();
      // 释放输入
      for (final OrtValue v in feeds.values) {
        v.release();
      }
      runOpts.release();
      return out;
    } catch (e) {
      for (final OrtValue v in feeds.values) {
        v.release();
      }
      runOpts.release();
      rethrow;
    }
  }

  /// 用原始 ORT API 直接把 float 张量读成扁平 Float32List。
  /// 相比 `OrtValue.value`（内部建扁平 List&lt;num&gt; 再 reshape 成嵌套，且要再次展平）
  /// 这里只做一次拷贝，避免 GPT 每步 KV cache 的大量重复分配。
  Float32List readFloatTensor(OrtValue value) {
    final bg.OrtApi api = OrtEnv.instance.ortApiPtr.ref;
    final int addr = value.address;
    final infoPtrPtr = calloc<Pointer<bg.OrtTensorTypeAndShapeInfo>>();
    api.GetTensorTypeAndShape.asFunction<
            bg.OrtStatusPtr Function(
                Pointer<bg.OrtValue>, Pointer<Pointer<bg.OrtTensorTypeAndShapeInfo>>)>()(
        Pointer.fromAddress(addr), infoPtrPtr);
    final info = infoPtrPtr.value;
    final countPtr = calloc<Size>();
    api.GetTensorShapeElementCount.asFunction<
            bg.OrtStatusPtr Function(
                Pointer<bg.OrtTensorTypeAndShapeInfo>, Pointer<Size>)>()(
        info, countPtr);
    final int count = countPtr.value;
    final dataPtrPtr = calloc<Pointer<Void>>();
    api.GetTensorMutableData.asFunction<
            bg.OrtStatusPtr Function(
                Pointer<bg.OrtValue>, Pointer<Pointer<Void>>)>()(
        Pointer.fromAddress(addr), dataPtrPtr);
    final Float32List out = Float32List(count);
    if (count > 0) {
      final Pointer<Float> p = dataPtrPtr.value.cast<Float>();
      final Float32List view = p.asTypedList(count);
      out.setAll(0, view);
    }
    calloc.free(infoPtrPtr);
    calloc.free(countPtr);
    calloc.free(dataPtrPtr);
    return out;
  }

  /// 读取张量形状（维度列表），用于确认 KV cache 等输出的真实布局。
  List<int> readFloatTensorShape(OrtValue value) {
    final bg.OrtApi api = OrtEnv.instance.ortApiPtr.ref;
    final infoPtrPtr = calloc<Pointer<bg.OrtTensorTypeAndShapeInfo>>();
    api.GetTensorTypeAndShape.asFunction<
            bg.OrtStatusPtr Function(
                Pointer<bg.OrtValue>, Pointer<Pointer<bg.OrtTensorTypeAndShapeInfo>>)>()(
        Pointer.fromAddress(value.address), infoPtrPtr);
    final info = infoPtrPtr.value;
    final rankPtr = calloc<Size>();
    api.GetDimensionsCount.asFunction<
            bg.OrtStatusPtr Function(
                Pointer<bg.OrtTensorTypeAndShapeInfo>, Pointer<Size>)>()(
        info, rankPtr);
    final int rank = rankPtr.value;
    final dimsPtr = calloc<Int64>(rank);
    api.GetDimensions.asFunction<
            bg.OrtStatusPtr Function(
                Pointer<bg.OrtTensorTypeAndShapeInfo>, Pointer<Int64>, int)>()(
        info, dimsPtr, rank);
    final List<int> out = <int>[
      for (int i = 0; i < rank; i++) dimsPtr[i],
    ];
    calloc.free(infoPtrPtr);
    calloc.free(rankPtr);
    calloc.free(dimsPtr);
    return out;
  }

  List<String> get inputNames => _session.inputNames;
  List<String> get outputNames => _session.outputNames;

  // ---- 快速张量创建（原始 ORT API 直接拷贝，避免插件 createTensorWithDataList 的装箱开销） ----
  Pointer<bg.OrtAllocator>? _alloc;
  Pointer<bg.OrtMemoryInfo>? _memInfo;

  void _ensureAlloc() {
    if (_alloc != null) return;
    final bg.OrtApi api = OrtEnv.instance.ortApiPtr.ref;
    final allocPtr = calloc<Pointer<bg.OrtAllocator>>();
    api.GetAllocatorWithDefaultOptions.asFunction<
            bg.OrtStatusPtr Function(Pointer<Pointer<bg.OrtAllocator>>)>()(
        allocPtr);
    _alloc = allocPtr.value;
    final memPtr = calloc<Pointer<bg.OrtMemoryInfo>>();
    api.AllocatorGetInfo.asFunction<
            bg.OrtStatusPtr Function(
                Pointer<bg.OrtAllocator>, Pointer<Pointer<bg.OrtMemoryInfo>>)>()(
        _alloc!, memPtr);
    _memInfo = memPtr.value;
    calloc.free(allocPtr);
    calloc.free(memPtr);
  }

  OrtValue _floatTensor(Float32List data, List<int> shape) {
    _ensureAlloc();
    final bg.OrtApi api = OrtEnv.instance.ortApiPtr.ref;
    final dataPtr = calloc<Float>(data.length)
      ..asTypedList(data.length).setAll(0, data);
    final shapePtr = calloc<Int64>(shape.length)
      ..asTypedList(shape.length).setAll(0, shape);
    final outPtr = calloc<Pointer<bg.OrtValue>>();
    api.CreateTensorWithDataAsOrtValue.asFunction<
            bg.OrtStatusPtr Function(Pointer<bg.OrtMemoryInfo>, Pointer<Void>,
                int, Pointer<Int64>, int, int, Pointer<Pointer<bg.OrtValue>>)>()(
        _memInfo!,
        dataPtr.cast(),
        data.length * 4,
        shapePtr,
        shape.length,
        1, // float32
        outPtr);
    // CreateTensorWithDataAsOrtValue 只引用数据不拷贝，dataPtr 必须交由
    // OrtValueTensor 持有，release 时再释放。
    final OrtValue v = OrtValueTensor(outPtr.value, dataPtr.cast());
    calloc.free(shapePtr);
    calloc.free(outPtr);
    return v;
  }

  OrtValue _int64Tensor(Int64List data, List<int> shape) {
    _ensureAlloc();
    final bg.OrtApi api = OrtEnv.instance.ortApiPtr.ref;
    final dataPtr = calloc<Int64>(data.length)
      ..asTypedList(data.length).setAll(0, data);
    final shapePtr = calloc<Int64>(shape.length)
      ..asTypedList(shape.length).setAll(0, shape);
    final outPtr = calloc<Pointer<bg.OrtValue>>();
    api.CreateTensorWithDataAsOrtValue.asFunction<
            bg.OrtStatusPtr Function(Pointer<bg.OrtMemoryInfo>, Pointer<Void>,
                int, Pointer<Int64>, int, int, Pointer<Pointer<bg.OrtValue>>)>()(
        _memInfo!,
        dataPtr.cast(),
        data.length * 8,
        shapePtr,
        shape.length,
        7, // int64
        outPtr);
    final OrtValue v = OrtValueTensor(outPtr.value, dataPtr.cast());
    calloc.free(shapePtr);
    calloc.free(outPtr);
    return v;
  }

  void dispose() {
    _session.release();
    _options.release();
  }
}

/// ONNX 模型组的管理器：懒加载各子模型，统一 dispose。
class OrtEngine {
  OrtEngine({this.threads = 2});

  final int threads;
  bool _envInitialized = false;

  OrtSessionWrapper? _gpt;
  OrtSessionWrapper? _gptCode;
  OrtSessionWrapper? _embText;
  OrtSessionWrapper? _embCode;
  OrtSessionWrapper? _headText;
  OrtSessionWrapper? _headCode;
  OrtSessionWrapper? _dvae;
  OrtSessionWrapper? _vocos;

  void _ensureEnv() {
    if (_envInitialized) return;
    OrtEnv.instance.init();
    _envInitialized = true;
  }

  OrtSessionWrapper _open(String path) {
    _ensureEnv();
    // 与 Python 端一致：禁用图优化，避免 KV cache 0 长度下的 Concat buffer 复用问题。
    final OrtSessionOptions options = OrtSessionOptions()
      ..setIntraOpNumThreads(threads)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortDisableAll);
    // Windows 上 ORTCHAR_T=wchar_t，`fromFile` 的 UTF-8 路径会乱码，改用 fromBuffer。
    // 移动端 ORTCHAR_T=char，`fromFile` 正常（且利于 mmap/懒加载）。
    final OrtSession session = Platform.isWindows
        ? OrtSession.fromBuffer(File(path).readAsBytesSync(), options)
        : OrtSession.fromFile(File(path), options);
    return OrtSessionWrapper(session, options);
  }

  OrtSessionWrapper gpt(String modelsDir) =>
      _gpt ??= _open('$modelsDir/gpt_emb_quant_int8.onnx');

  /// 独立的 code 生成专用 GPT 会话。与 [gpt]（refine 用）分离，
  /// 避免 refine 的自回归污染 code 生成首步的 GPT 前向结果。
  OrtSessionWrapper gptCode(String modelsDir) =>
      _gptCode ??= _open('$modelsDir/gpt_emb_quant_int8.onnx');
  OrtSessionWrapper embText(String modelsDir) =>
      _embText ??= _open('$modelsDir/emb_text.onnx');
  OrtSessionWrapper embCode(String modelsDir) =>
      _embCode ??= _open('$modelsDir/emb_code.onnx');
  OrtSessionWrapper headText(String modelsDir) =>
      _headText ??= _open('$modelsDir/head_text.onnx');
  OrtSessionWrapper headCode(String modelsDir) =>
      _headCode ??= _open('$modelsDir/head_code.onnx');
  OrtSessionWrapper dvae(String modelsDir) =>
      _dvae ??= _open('$modelsDir/dvae.onnx');
  OrtSessionWrapper vocos(String modelsDir) =>
      _vocos ??= _open('$modelsDir/vocos_spectrum.onnx');

  /// 释放所有已加载的会话。
  void dispose() {
    void release(OrtSessionWrapper? w) => w?.dispose();
    release(_gpt); _gpt = null;
    release(_gptCode); _gptCode = null;
    release(_embText); _embText = null;
    release(_embCode); _embCode = null;
    release(_headText); _headText = null;
    release(_headCode); _headCode = null;
    release(_dvae); _dvae = null;
    release(_vocos); _vocos = null;
    if (_envInitialized) {
      OrtEnv.instance.release();
      _envInitialized = false;
    }
  }
}
