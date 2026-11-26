import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dna/services/audio_output.dart';
import 'package:dna/services/bgm_engine.dart';
import 'package:dna/services/bgm_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

/// 角色卡背景音乐播放状态机的关键行为测试。
///
/// 每个用例都对应一条不变量（见 `BgmPlaybackController` 的类注释）：
///
/// * 不变量 1「音量只有一个出口」→ 「暂停期间的音量写入不得为 0」等；
/// * 不变量 2「播完从头再来」→ 「completed / stopped 后 seek(0) + play」；
/// * 不变量 3「意图与真实状态不许分叉」→ 「用户 stop 之后不许自己复活」；
/// * 不变量 4「长音频模式 + 不抢焦点」→ 配置断言 + 源码守护。
///
/// 这些用例**都能失败**：把被钉住的那一处改回旧实现，对应用例立刻红
/// （破坏性验证记录见 docs/BGM_PLAYBACK.md）。
const String kMusic = '/doc/tas/music_ta_1.mp3';

/// 假引擎：只记录调用，不碰平台通道。
class FakeBgmEngine implements BgmEngine {
  final List<String> calls = <String>[];
  final List<double> volumes = <double>[];
  final StreamController<BgmEngineEvent> _events =
      StreamController<BgmEngineEvent>.broadcast();

  int countOf(String call) => calls.where((String c) => c == call).length;

  @override
  Stream<BgmEngineEvent> get events => _events.stream;

  void emit(BgmEngineEvent event) => _events.add(event);

  @override
  Future<void> open(String path) async => calls.add('open');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> seekToStart() async => calls.add('seekToStart');

  @override
  Future<void> setVolume(double volume) async {
    calls.add('setVolume');
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _events.close();
  }
}

void main() {
  group('音量不变量（不变量 1）', () {
    test('播放中：音量 = base，duck 后 = base×系数，unduck 后回到 base', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.setBaseVolume(0.8);
      await bgm.play(kMusic);
      expect(engine.volumes.last, closeTo(0.8, 1e-9));

      await bgm.duck();
      expect(
        engine.volumes.last,
        closeTo(0.8 * BgmPlaybackController.kDuckFactor, 1e-9),
      );

      await bgm.unduck();
      expect(engine.volumes.last, closeTo(0.8, 1e-9));
    });

    test('暂停期间改音量/duck，音量绝不被写成 0；resume 后落到新音量', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.setBaseVolume(0.8);
      await bgm.play(kMusic);
      await bgm.pause();

      // 旧实现：_effectiveVolume() 在「暂停中」返回 0.0，这三步都会把
      // 原生音量写成 0，而 resume() 又不重设音量 → 恢复播放但永远静音。
      await bgm.setBaseVolume(0.6);
      await bgm.duck();
      await bgm.unduck();

      expect(
        engine.volumes,
        everyElement(greaterThan(0.0)),
        reason: '暂停期间的任何音量下发都不能是 0（恢复播放会继承它）',
      );

      await bgm.resume();
      expect(
        engine.volumes.last,
        closeTo(0.6, 1e-9),
        reason: 'resume 必须重新落一次音量，而不是沿用暂停期间的值',
      );
    });

    test('没有播放意图时不写音量（空写会把 0 留给下一次播放）', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.setBaseVolume(0.7);
      await bgm.duck();
      await bgm.unduck();
      await bgm.stop();

      expect(engine.volumes, isEmpty);
    });
  });

  group('播完从头再来（不变量 2）', () {
    test('引擎报 completed → seekToStart + play，并重新落音量', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.setBaseVolume(0.5);
      await bgm.play(kMusic);
      engine.calls.clear();

      engine.emit(BgmEngineEvent.completed);
      await pumpEventQueue();

      expect(engine.calls, <String>['seekToStart', 'play', 'setVolume']);
      expect(engine.volumes.last, closeTo(0.5, 1e-9));
      expect(bgm.isPlaying.value, isTrue);
    });

    test('引擎被外部掐停（stopped）同样从头再来', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.play(kMusic);
      engine.calls.clear();

      engine.emit(BgmEngineEvent.stopped);
      await pumpEventQueue();

      expect(engine.countOf('seekToStart'), 1);
      expect(engine.countOf('play'), 1);
    });

    test('用户 stop 之后不许自己复活', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.play(kMusic);
      await bgm.stop();
      engine.calls.clear();

      engine.emit(BgmEngineEvent.completed);
      engine.emit(BgmEngineEvent.stopped);
      await pumpEventQueue();

      expect(engine.calls, isEmpty);
      expect(bgm.isPlaying.value, isFalse);
    });

    test('暂停期间报 completed 也不许自己开播', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.play(kMusic);
      await bgm.pause();
      engine.calls.clear();

      engine.emit(BgmEngineEvent.completed);
      await pumpEventQueue();

      expect(engine.countOf('play'), 0);
    });

    test('放不出来的文件不会无限空转：一个窗口内重启次数有上限，且状态不再骗人', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.play(kMusic);
      for (int i = 0; i < BgmPlaybackController.kMaxRestartsPerWindow + 5; i++) {
        engine.emit(BgmEngineEvent.completed);
        await pumpEventQueue();
      }

      expect(engine.countOf('play'), BgmPlaybackController.kMaxRestartsPerWindow);
      expect(
        bgm.isPlaying.value,
        isFalse,
        reason: '放弃自动重播后必须把 isPlaying 置 false，不许继续显示在播',
      );
    });
  });

  group('播放流程', () {
    test('同一首曲子重复进入不打断进度，换曲子才重新设源', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.play(kMusic);
      engine.calls.clear();

      await bgm.play(kMusic);
      expect(engine.countOf('open'), 0);
      expect(engine.countOf('play'), 1);
      expect(engine.countOf('seekToStart'), 0);

      await bgm.play('/doc/tas/music_ta_2.mp3');
      expect(engine.countOf('open'), 1);
    });

    test('离开再进入聊天页从头开始（stop 清掉位置）', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.play(kMusic);
      await bgm.stop();
      engine.calls.clear();

      await bgm.play(kMusic);
      expect(engine.countOf('open'), 1);
      expect(engine.countOf('play'), 0);
    });

    test('pause / resume 幂等：重复调用不重复下发原生指令', () async {
      final FakeBgmEngine engine = FakeBgmEngine();
      final BgmPlaybackController bgm = BgmPlaybackController(engine);

      await bgm.play(kMusic);
      engine.calls.clear();

      await bgm.pause();
      await bgm.pause();
      expect(engine.countOf('pause'), 1);

      await bgm.resume();
      await bgm.resume();
      expect(engine.countOf('play'), 1);
    });
  });

  group('长音频配置不变量（不变量 4）', () {
    test('长音频必须用流式解码模式（Android = MediaPlayer，不是 SoundPool）', () {
      expect(kLongAudioPlayerMode, PlayerMode.mediaPlayer);
    });

    test('播放时不许申请音频焦点（否则会把 BGM 在原生层挤停）', () {
      final AudioContext ctx = buildCoexistingAudioContext();
      expect(ctx.android.audioFocus, AndroidAudioFocus.none);
    });

    test('朗读要压低别人：transient may duck，且声明为语音内容', () {
      final AudioContext ctx = buildSpeechAudioContext();
      expect(ctx.android.audioFocus, AndroidAudioFocus.gainTransientMayDuck);
      expect(ctx.android.contentType, AndroidContentType.speech);
    });

    test('两条音轨的焦点策略必须分开：BGM 用共存上下文，TTS 用朗读上下文', () {
      final String engine = File('lib/services/bgm_engine.dart').readAsStringSync();
      expect(engine.contains('buildCoexistingAudioContext'), isTrue);

      final String tts = File('lib/services/tts/tts_player.dart').readAsStringSync();
      expect(tts.contains('buildSpeechAudioContext'), isTrue);
      expect(
        tts.contains('buildCoexistingAudioContext'),
        isFalse,
        reason: '朗读不申请焦点就压不住别的 App 的音乐（用户明确要求压低）',
      );
    });

    // 源码守护（同 docs/TESTING_CONVENTIONS.md §4 的既有做法）：
    // 播放模式的选择只允许出现在 audio_output.dart 一处，别处再写 PlayerMode.xxx
    // 就会红 —— 这正是这个坑此前的复发路径。
    test('播放模式只有一处定义：bgm / tts 代码里不得再出现 PlayerMode.', () {
      const List<String> guarded = <String>[
        'lib/services/bgm_player.dart',
        'lib/services/bgm_engine.dart',
        'lib/services/tts/tts_player.dart',
      ];
      for (final String path in guarded) {
        final String src = File(path).readAsStringSync();
        expect(
          src.contains('PlayerMode.'),
          isFalse,
          reason: '$path 不许自己选播放模式，统一用 audio_output.dart 的常量',
        );
      }
      final String audioOutput = File('lib/services/audio_output.dart').readAsStringSync();
      expect(
        audioOutput.split('= PlayerMode.').length - 1,
        1,
        reason: '播放模式只允许在 audio_output.dart 里选一次（赋值语句只有一处）',
      );
    });

    test('原生音量只有一个写入口（状态机里只有一处 setVolume 下发）', () {
      final String src = File('lib/services/bgm_player.dart').readAsStringSync();
      expect(src.split('_engine.setVolume').length - 1, 1);
    });
  });

  group('生命周期策略：失焦即暂停', () {
    test('inactive / paused / hidden / detached 都暂停音乐', () {
      const List<AppLifecycleState> pausing = <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ];
      for (final AppLifecycleState state in pausing) {
        expect(
          bgmActionForLifecycle(state),
          BgmLifecycleAction.pause,
          reason: '$state 应当暂停背景音乐',
        );
      }
    });

    test('resumed 恢复播放', () {
      expect(
        bgmActionForLifecycle(AppLifecycleState.resumed),
        BgmLifecycleAction.resume,
      );
    });

    test('页面回调只做分发：生命周期判断只允许在 bgmActionForLifecycle 里', () {
      final String src =
          File('lib/pages/chat/state/chat_state_mixin.dart').readAsStringSync();
      expect(src.contains('bgmActionForLifecycle(state)'), isTrue);
      expect(
        src.split('AppLifecycleState.').length - 1,
        0,
        reason: '页面不该自己判断生命周期状态（这条策略被改错过两次）',
      );
    });
  });
}
