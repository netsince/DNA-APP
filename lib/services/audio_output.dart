import 'package:audioplayers/audioplayers.dart';

/// 本应用「长时间音频」（角色背景音乐、TTS 朗读）的播放配置。
///
/// 这两个常量不是可调的偏好，而是 Android 上实测踩过的坑，**只允许在这里定义**：
///
/// 1. [kLongAudioPlayerMode] 必须是 [PlayerMode.mediaPlayer]。
///    `PlayerMode.lowLatency` 在 Android 上走的是 audioplayers 的
///    `SoundPoolPlayer`：整段音频会被解码进静态 AudioTrack 缓冲，不支持 seek、
///    拿不到时长，只适合极短音效。3 分钟以上的曲子在上面会被截断或干脆放不
///    出来；更糟的是 SoundPool 的加载失败状态码在 audioplayers 里被忽略
///    （`SoundPoolPlayer.kt` 的 `onLoadCompleteListener` 不看 `status`），失败了
///    也静默，于是用户看到的是「只播了前半段，后面的直接没了」。
///    `mediaPlayer` 是流式解码，长文件才成立。
///
/// 2. [buildCoexistingAudioContext] 必须不申请音频焦点。
///    audioplayers 默认是 `AUDIOFOCUS_GAIN`。背景音乐播放器和 TTS 播放器各持
///    一个 `AudioPlayer`，谁后申请谁拿走焦点，先播的那个会在原生层收到
///    `AUDIOFOCUS_LOSS` 并被直接 `pause()`（`WrappedPlayer.onLoss` → `pause`），
///    而 Dart 侧完全不知情 —— 表现为「角色读一句台词，背景音乐就永久停下」。
///    两条音轨的混合由 `BgmPlayer.duck/unduck` 自己负责，不需要系统焦点仲裁。
const PlayerMode kLongAudioPlayerMode = PlayerMode.mediaPlayer;

/// 与设备上其它音轨共存（不抢焦点）的音频上下文。理由见 [kLongAudioPlayerMode]。
///
/// **只给背景音乐用。** 背景音乐一旦申请焦点，就会和 TTS 互相抢占（见上）。
AudioContext buildCoexistingAudioContext() =>
    AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build();

/// 朗读（TTS）用的音频上下文：**短暂持有焦点并允许压低别人**
/// （Android `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` / iOS `playback` + `duckOthers`）。
///
/// 为什么两条音轨的焦点策略相反：
/// * 朗读是「短、事件性」的一小段，请求 transient focus 是 Android 的预期用法，
///   别的 App 的音乐会被系统压低、朗读结束自动恢复；
/// * 背景音乐是「长、常驻」的，且同一进程里已经有一条要抢焦点的音轨了 —— 它只要
///   申请焦点，就会变成两条音轨互抢，先播的那个在原生层被 `pause()` 且 Dart 侧
///   察觉不到（这就是「角色读一句台词，音乐永久停掉」的成因）。
///
/// 因此背景音乐**不持有焦点**，系统不会把它当焦点竞争者通知，TTS 抢焦点也就
/// 影响不到它；它自己的降音量由 `BgmPlayer.duck/unduck` 负责。
///
/// iOS 不沿用 `AudioContextConfig(focus: duckOthers)`：那会把 category 强制成
/// `playAndRecord`（需要麦克风权限、可能改变输出路由）。朗读只要
/// `playback` + `duckOthers` 就能压低别人。
AudioContext buildSpeechAudioContext() => AudioContext(
      android: const AudioContextAndroid(
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        usageType: AndroidUsageType.media,
        contentType: AndroidContentType.speech,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: <AVAudioSessionOptions>{
          AVAudioSessionOptions.duckOthers,
          AVAudioSessionOptions.mixWithOthers,
        },
      ),
    );
