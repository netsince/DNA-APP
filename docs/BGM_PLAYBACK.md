# 角色卡背景音乐（BGM）播放契约

这份文档固定的是「背景音乐为什么这么写」，不是 API 说明。改 `bgm_player.dart` /
`bgm_engine.dart` / `audio_output.dart` 之前先读完。

起因：用户反馈 Android 上绑定 3 分钟以上的曲子「只播前半段，后面的直接没了」
（实测文件 `corn wave - Приятные Сны.mp3`，7.07 MB / ID3v2.3）。根因不在文件也不在
存储层（落盘是 `File.copy` 全量拷贝，备份恢复是全量 `writeAsBytes`），而在播放层：
三条独立缺陷叠在一起，任何一条都能让音乐在中途消失，而且**应用自己完全不知道**。

## 三层结构与唯一入口

| 层 | 文件 | 职责 |
|---|---|---|
| 配置 | `lib/services/audio_output.dart` | 长音频播放模式 / 音频焦点的**唯一**定义处 |
| 引擎 | `lib/services/bgm_engine.dart` | `BgmEngine` 接口 + audioplayers 实现（可替换，为了可测） |
| 状态机 | `lib/services/bgm_player.dart` | `BgmPlaybackController`：意图、音量、兜底重播；`BgmPlayer.instance` 只是持有唯一引擎的外壳 |

状态下发只有两条出口：`_applyVolume()`（音量）与 `_setIntent()`（意图）。引擎事件
只允许**纠正**意图，不允许直接改状态。

## 不变量

1. **音量只有一个出口**：原生音量恒为 `baseVolume × (ducked ? 0.25 : 1)`，与「是否暂停」无关。
   暂停期间写 0 会被下一次播放继承 → 「恢复播放但永远静音」。
2. **播完必须从头再来**：意图是「在播」时，引擎报 `completed` / `stopped` 就
   `seekToStart()` + `play()` + 重新落音量。不依赖原生 `ReleaseMode.loop` 是否上报完成。
3. **意图与真实状态不许分叉**：引擎调用失败即复位意图；外部原因造成的停止由事件纠正。
4. **长音频必须流式解码**：`PlayerMode.mediaPlayer`（不是 `lowLatency`，Android 上后者是
   SoundPool：整段解码进静态缓冲、不支持 seek/时长，且加载失败状态码被 audioplayers 忽略）。
5. **焦点策略按音轨分工**：背景音乐 `mixWithOthers`（**绝不持有焦点**）；朗读
   `gainTransientMayDuck`（短暂持焦点、把别人的音乐压低，读完自动归还）。
   两条音轨若都申请焦点，就会互抢 —— 先播的那个被原生 `pause()` 而 Dart 侧毫不知情，
   这就是「角色读一句台词，背景音乐永久停掉」的成因。
6. **失焦即暂停**：`inactive` 也算暂停（Android 下拉通知栏/系统弹窗/来电浮层，
   桌面端窗口失焦），只有 `resumed` 恢复。策略写成纯函数 `bgmActionForLifecycle`，
   页面回调只做分发。

## 产品策略（用户明确要求，别自行反转）

| 策略 | 落点 | 钉住它的测试 |
|---|---|---|
| 失焦暂停音乐 | `bgmActionForLifecycle`（`bgm_player.dart`），`inactive` → pause | 生命周期组 3 条 |
| 朗读时压低别人的音乐 | `buildSpeechAudioContext()`（`audio_output.dart`） | 「朗读要压低别人」「两条音轨的焦点策略必须分开」 |

这两条都**被反向修改过**（先后经历「inactive 也暂停」→「只认真后台」→「失焦暂停」），
所以它们不是散落在回调里的 `if`，而是带测试的数据/常量。

## 能失败的测试（`test/bgm_player_test.dart`，共 20 条）

| 用例 | 钉住的不变量 |
|---|---|
| 播放中音量 = base / duck / unduck | 1 |
| 暂停期间改音量、duck、unduck 不得写 0；resume 必须重落音量 | 1 |
| 没有播放意图时不写音量 | 1 + 3 |
| `completed` → `seekToStart` + `play` + 落音量 | 2 |
| `stopped`（被外部掐停）同样从头再来 | 2 + 3 |
| 用户 `stop` 之后不许自己复活 | 3 |
| 暂停期间报 `completed` 不许自己开播 | 3 |
| 放不出来的文件：一个窗口内重启次数有上限，且 `isPlaying` 必须置 false | 2 + 3 |
| 同曲重复进入不打断 / 离开再进入从头 | — |
| `pause` / `resume` 幂等 | — |
| 模式 = `mediaPlayer`；BGM 焦点 = `none`；朗读焦点 = `gainTransientMayDuck` | 4 + 5 |
| 两条音轨焦点策略分开（源码守护：tts 不许用共存上下文） | 5 |
| `inactive`/`paused`/`hidden`/`detached` → pause，`resumed` → resume | 6 |
| 页面回调只做分发（源码守护：页面里不许出现 `AppLifecycleState.`） | 6 |
| 源码守护：`bgm_*/tts_player` 里不许出现 `PlayerMode.`；`setVolume` 下发只有一处 | 4 + R3 |

## 破坏性验证记录（2026-11-26，本机 `flutter test test/bgm_player_test.dart`）

把修复处逐个改回旧实现，确认对应用例变红，再复原：

1. `effectiveVolume` 改回「暂停中返回 0.0」+ 模式改回 `lowLatency`：

```
Expected: every element(a value greater than <0.0>)
  Actual: [0.8, 0.0, 0.0, 0.0]
暂停期间的任何音量下发都不能是 0（恢复播放会继承它）
Expected: PlayerMode:<PlayerMode.mediaPlayer>
  Actual: PlayerMode:<PlayerMode.lowLatency>
Some tests failed.            → 2 条红
```

2. 去掉 `resume()` 里的 `_applyVolume()`，并停用兜底重播：

```
Expected: <String>['seekToStart', 'play', 'setVolume']
  Actual: []
Expected: <1>   Actual: <0>        （stopped 后不再重播）
Expected: <3>   Actual: <0>        （坏文件限流用例同时红）
Some tests failed.            → 3 条红
```

3. 两条新策略各自改回旧样子（TTS 用共存上下文、`inactive` → `nothing`）：

```
Expected: true   Actual: <false>                     （tts 不许用共存上下文）
Expected: BgmLifecycleAction:<pause>
  Actual: BgmLifecycleAction:<nothing>
AppLifecycleState.inactive 应当暂停背景音乐
Some tests failed.            → 2 条红
```

复原后：`flutter test test/bgm_player_test.dart test/bgm_test.dart chat_surface_embed_test.dart`
→ `+27: All tests passed!`；`flutter analyze lib` → `No issues found!`。

## 这次让哪一类 bug 变成不可能

* 「播放器停了/静音了，界面还显示在播」——状态只能由意图推出，引擎事件必须纠正它。
* 「某处顺手写了个音量 0 / 某处顺手选了 lowLatency」——音量只有一个出口，播放模式只有
  一处定义，源码守护测试会把第二处打红。
* 「播完不循环」——不再依赖平台 loop 上报，兜底重启 + 限流。

## 还没做的（明确记录，不是遗漏）

* **10 MB 默认上限没动**。3 分钟按 320 kbps 约 7 MB 能过；更长的曲子仍是
  「设置 → 背景音乐 → 解锁上限」的产品选择，不是播放层问题。
* **TTS 播放器的事件订阅仍未显式 cancel**（随 `AudioPlayer.dispose()` 关闭）。
  与本次缺陷同类性不足，未一并处理。
* 「失焦暂停」在 Android 上等于「下拉通知栏也暂停音乐」（`inactive` 的语义就是失焦）。
  这是按产品要求做的取舍；若将来只想在桌面端失焦暂停，改 `bgmActionForLifecycle`
  一处即可，测试会提示哪条策略被动过。

## 设备侧自查（Android）

改完在真机上按这三步确认，任何一步不对都应先看 logcat 里的 `AudioFocus` /
`SoundPool` / `sample ... not READY`：

1. 绑定 3 分钟以上的曲子，进聊天页 → 应当整首放完并无缝从头再来。
2. 期间点消息的朗读按钮 → 背景音乐降到 25% 继续放，朗读结束回满，**不允许停**；
   同时另一个 App 正在放的音乐应被压低、朗读结束自动恢复。
3. 下拉通知栏 / 切到别的窗口（失焦）→ 音乐暂停；回到本应用 → 从暂停处继续**且有声**
   （这条同时验证「暂停期间的音量下发不会留下静音」）。
