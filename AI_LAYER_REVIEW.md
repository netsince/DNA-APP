# AI 请求层代码评审报告

> 评审对象:`lib/services/`(LLM Provider 层)+ `lib/pages/chat/`(发送/流式消费链路)
> 评审方式:逐行阅读 + grep 取证,所有行号基于当前 main 分支工作区(0.2.1+3)
> 日期:本会话生成
> 更新一:LLM 服务中间件 `lib/services/llm_service_base.dart` 已落地。
> 更新二:A2 / A3 / A4 / C5 已修复,另发现并修复 `stripThoughtTags` 内容回吐存量 bug;最新状态见文末「TODO」

---

## 总体判断

**上层讲究,下层粗糙。**

消息组装层(KV-cache 友好的 payload 布局、Lorebook 预算裁剪、CJK 感知 token 近似)设计相当用心;
但传输层(超时语义、取消机制、错误契约)和适配器工程(三份复制粘贴、双真相源手工同步)欠账明显。

按严重度分五档:P0 正确性 Bug → P1 兼容性地雷 → 架构债 → 隐私安全 → 小毛病。

---

## A. 会真实咬人的 Bug(P0)

### A1. Anthropic 错误契约不一致 → 聊天页永久锁死 ⚠️ 最严重

三个流式适配器的错误处理方式不同:

- OpenAI / 智谱 / DeepSeek:错误以字符串 yield —— `[ERROR] ...`
  (`lib/services/openai_service.dart:274`、`lib/services/zhipu_service.dart:292`)
- **Anthropic:直接 `throw Exception(...)`**
  (`lib/services/anthropic_service.dart:253`、`:258`)

而消费端 `_streamAssistantResponse` 的 `await for` **没有 try/catch**
(`lib/pages/chat/builders/chat_stream_handlers.dart:18-71`),调用方 `_send()` 也不 catch。

触发链推演:

```
Anthropic 端点任何网络错误 / HTTP 非 200
  → throw 逃逸成未处理异步异常
  → setState(() => _sending = false)(chat_actions_send.dart:276)永远执行不到
  → _sending 永久为 true
  → 该会话无法再发送任何消息,只能重启 App
```

### A2. `<think>` 标签跨 chunk 边界撕裂泄漏

流式标签解析器在找不到开标签时把**整个 buffer 冲进可见正文**,
没有"扣住可能是标签前缀的尾巴"的 holdback 逻辑
(`lib/pages/chat/chat_stream_parser.dart:36-40`)。

推演:chunk1 以 `...text<thi` 结尾、chunk2 为 `nk>abc`
→ 两轮都匹配失败 → 用户看到原文 `abc`,
思考内容混入正文并被持久化到数据库。

- DeepSeek 官方路径安全:reasoning 走独立的 `reasoning_content` 字段,
  标签由客户端整块合成(`openai_service.dart:297-300`);
- 但凡是把 `&lt;think&gt;` 放在 content 里输出的模型(QwQ、R1 蒸馏系、各类中转站)会高频踩中。

### A3. 断流黑洞:body 阶段零超时 + 全应用没有"停止生成"按钮

流式的 20s 超时挂在 `_client.send()` 的 Future 上,**只守护到响应头到达为止**——
Dart http 包中该 Future 在状态行+响应头到达即完成,与首个 token 无关,更与 body 无关
(`lib/services/openai_service.dart:269`;智谱同款 `zhipu_service.dart:248`;
DeepSeek 继承 OpenAI)。

body 流上没有任何超时。同时 grep 整个 `lib/pages/chat`,
所有"停止"都是 TTS 和语音录入的——**不存在中断 LLM 生成的控件**。

三者叠加:

```
响应头到达后流卡死(服务端挂起未关连接、静默丢包)
  → await for 永挂
  → 用户无 UI 手段中断
  → _sending 永真 → 会话冻结直到重启
```

对照:正确写法就在本项目自己代码里——`lib/services/sherpa_model_service.dart:183-189`
对下载流套了 `response.stream.timeout(30s)` 空闲超时,聊天链路没抄这份作业。

各路径超时语义汇总:

| 路径 | 超时语义 |
|---|---|
| 流式聊天(OpenAI/智谱/DeepSeek) | 20s = 到响应头为止;body 阶段零超时 |
| 流式聊天(**Anthropic**) | **无任何超时**(裸 `await _client.send(request)`,`anthropic_service.dart:251`) |
| 非流式 createChatCompletion(重说/摘要/灵感) | `.timeout(20s)` 挂在 `post()` 上,等完整 body 读完才返回 → 真正的总时长 20s(`openai_service.dart:186`) |
| validateApi / fetchModels(GET /models) | 总时长 12s |

### A4. 中途退出页面,已生成的回复全部丢失

发送时空 assistant 占位气泡先落库(`chat_actions_send.dart:231`),
流式期间只改内存对象,**只在流正常结束时才 `upsertConversation`**
(`chat_stream_handlers.dart:89`)。

用户中途返回页面 → `!mounted` 提前 return → 最终落库被跳过
→ 数据库里留一个空气泡,已生成且已计费的那几百字全部丢失。

### A5. `Future.timeout` 不取消底层请求

http 包的 Request 没有取消机制:超时只是"不再等待",
socket 继续悬挂直到服务端关连接。每次超时/失败都泄漏一条连接。
也因此,"加停止按钮"需要 provider 层先支持可取消(暴露 close 或换可取消传输),不是纯 UI 改动。

---

## B. 兼容性地雷(P1,"换个 API 就坏"系列)

| # | 问题 | 位置 | 后果 |
|---|---|---|---|
| B1 | `temperature` / `frequency_penalty` / `presence_penalty` **无条件发送**(仅 top_p/top_k/min_p/rep 做了非默认值裁剪) | `openai_service.dart:167-172` | OpenAI o1/o3/gpt-5 系及部分 reasoning 端点直接 400;没有按模型能力裁剪参数的机制 |
| B2 | baseUrl 不以 `/v1` 结尾就强插 `/v1` | `openai_service.dart:375-381` | Gemini OpenAI 兼容层(`/v1beta/openai`)、Azure(deployment 路径 + `api-key` 头)根本接不上 |
| B3 | 连通性校验 = GET `/models` 返回 200 | `openai_service.dart:51-61` | 不少兼容网关不实现 /models → 明明能聊却校验失败,OOBE 卡死 |
| B4 | fetchModels 硬编码 `{data:[{id}]}` 形状;兜底模型表 Anthropic 与智谱有,**OpenAI 无**(失败时返回空列表) | `anthropic_service.dart` / `zhipu_service.dart` 有兜底,OpenAI 无兜底 | 其他家返回裸数组即显示"模型列表为空",行为不一致 |
| B5 | OpenAI 路径从不发送 `max_tokens`(Anthropic 反而写死 8192) | `openai_service.dart:167-184`、`anthropic_service.dart:22` | 部分本地推理/代理默认输出极短或无上限烧钱 |

---

## C. 架构设计债

### C1. 字符串哨兵协议

错误走 `[ERROR]` 前缀、思考走内联 `&lt;think&gt;` 标签,全混在一个 `Stream<String>` 里。
模型若真输出 "[ERROR]" 开头的文本会被误判为错误并丢弃整条回复
(`chat_stream_handlers.dart:38`)。
应改为 sealed chunk 类型(Content / Reasoning / Error / Done)。

### C2. 接口参数爆炸 + 抽象泄漏

`streamChatCompletion` 有 15 个参数;厂商特有的 `thinkingType/reasoningEffort`
上浮到通用接口,controller 还挂着单厂商 getter `deepseekThinkingType`
(`lib/state/app_controller.dart:73-86`)。每加一家厂商要动接口 + 全部实现。

### C3. 三份复制粘贴适配器,且已经漂移

OpenAI 与智谱约 95% 相同(SSE 解析、`_extractError`、采样体各持一份)。
漂移实证:

1. 错误处理 throw vs yield(A1);
2. 超时——OpenAI 系 20s/12s,**Anthropic 全文件无一处 `.timeout`**
   (校验 `:104`、非流式 `:187`、流式 `:251` 全部裸奔);
3. 错误信息提取:Anthropic 截断 200 字符,OpenAI 不截断。

DeepSeek 用继承复用(`deepseek_service.dart:11`)是正确路线,但只有这一家这么做。

### C4. 双真相源手工缝合

legacy 扁平字段(`provider/baseUrl/apiKey/selectedModel`)与新
`LlmProviderConfig/LlmModelConfig` 列表并存,
靠 `_syncActiveModelToLegacyFields()` 手工同步(`app_controller.dart:191-230`);
`ensureApiReady` 读的还是 legacy 字段(`lib/utils/api_guard.dart:9-11`)。
任何新写入路径忘调 sync 即产生漂移——典型的"迁移做了一半"状态。

### C5. 测试盲区

`test/` 下 18 个测试文件,没有任何 provider/SSE 解析测试;
全仓库无一处 `MockClient`。构造函数明明留了 `client` 注入口
(`openai_service.dart:10`)却从未用于测试——
全项目最容易回归的流解析逻辑零覆盖。

---

## D. 隐私 / 安全(与"隐私优先"定位相悖的点)

- **debugPrint 打印完整对话响应体**:`openai_service.dart:58`、`:187`(智谱同款)。
  release 模式下 debugPrint 仍输出到平台日志(Android logcat 可见),
  对话内容进系统日志。建议加 `kDebugMode` 守卫或删除。
- API Key 明文存 SharedPreferences(`lib/services/settings_service.dart:18`)。
- baseUrl 不校验 scheme:用户填 `http://` 时密钥明文传输且无任何警告。

---

## E. 小毛病速览

- `finish_reason == 'length'` 截断无提示,用户只看到莫名断尾的回复;
- usage 字段不读取,token 全靠本地 cl100k 近似(注释自知对非 OpenAI 模型是估计值);
- 重试 = 并发发 3 个一模一样的请求(`Future.wait`,`chat_actions_send.dart:487-510`),
  费钱且易触发限流;摘要/重说共用非流式 20s 总时长超时,长对话摘要在慢端点上很容易超;
- `ChatTokenCounter`:仅 release 对 >10000 字符走近似,debug 下全量 BPE 在 UI isolate 跑,
  开发期大文本必卡(`lib/pages/chat/chat_token_counter.dart:41`);
- SSE 多行 `data:` 与注释行未按规范处理(LLM 场景罕见,低危);
- Anthropic `max_tokens` 写死 8192 不可配置。

---

## 值得肯定的

- payload 的**缓存友好布局**:静态 system 前缀稳定,Lorebook/作者注释统一追加尾部,
  注释明确写了动机是 DeepSeek KV cache 命中率(`lib/pages/chat/chat_message_builder.dart:36-38`);
- Lorebook 的 sticky/冷却/延迟/预算裁剪是完整实现而非摆设(`chat_actions_send.dart:77-134`);
- 高级采样参数仅在非默认值时携带,保护标准端点(`openai_service.dart:341-365`);
- token 预算从最新往最旧裁剪、摘要计入预算(`lib/pages/chat/chat_message_slice.dart:46-75`);
- CJK 感知的长文本 token 近似(`chat_token_counter.dart:55-68`);
- `sherpa_model_service.dart` 里有全项目唯一的正确流式超时范本(可直接复用其模式);
- provider 构造函数预留 `http.Client` 注入口,为可测试性留了门(只是没用上)。

---

## 修复优先级路线图

### P0(止血,建议立即修)

1. **A1**:Anthropic 改为 yield `[ERROR]` 统一错误契约;消费端补 try/catch 复位 `_sending`;
2. **A3**:body 流套空闲超时(照抄自家 `sherpa_model_service.dart:183-189` 的
   `stream.timeout` 写法,建议 60~120s);
3. **A3/A5**:provider 层暴露取消能力 + 聊天页加"停止生成"按钮;
4. **A4**:unmount 时先把 partial 文本落库再退出循环。

### P1(兼容性)

5. **B1**:按模型/provider 能力矩阵裁剪采样参数(reasoning 系不发 temperature/penalty);
6. **B2**:baseUrl 规则提供"手动指定完整路径"逃生门,不再强插 /v1;
7. **B3**:validateApi 允许跳过 /models 校验,或改为轻量 chat 探测。

### P2(架构还债)

8. 合并 OpenAI/智谱为 OpenAI 兼容基类(DeepSeek 已示范);
9. sealed chunk 协议替代 `[ERROR]`/`&lt;think&gt;` 字符串哨兵;
10. 用 MockClient 补齐 SSE 拆包 / 断标签 / 错误路径 / 各家差异的单测。

---

## 验证方式说明

以上结论基于本会话对以下文件的逐行阅读与 grep 取证:
`llm_provider.dart`、`openai_service.dart`(全文)、`anthropic_service.dart`(全文)、
`zhipu_service.dart`(流式段全文)、`deepseek_service.dart`(全文)、
`chat_actions_send.dart`(626 行全文)、`chat_stream_handlers.dart`(全文)、
`chat_stream_parser.dart`(全文)、`chat_message_builder.dart`、`chat_system_prompt.dart`、
`chat_message_slice.dart`、`chat_token_counter.dart`、`api_guard.dart`、
`app_controller.dart`(Provider 注册/legacy 同步段)、`settings_service.dart`(存储键段)、
`main.dart`(装配段)、`test/` 目录清单。

A1/A2/A3 的触发链是从代码语义推演的,置信度高但未实机复现;
建议按报告中场景(Anthropic 断网、content 含 `&lt;think&gt;` 的模型分块输出、流中途拔网线)实测确认。

---

## TODO

> 状态基于「sealed chunk 重构轮」之后的当前代码(`lib/services/llm_request.dart`、`llm_stream_chunk.dart` 已落地)。
> 标记:✅ 已修好 · 📌 有意保留 / 遗留(含原因与计划)

### 一、已修好 ✅

| 编号 | 问题 | 修复方式 |
|---|---|---|
| A1 | Anthropic 流式错误直接 throw → 异常逃逸后聊天页永久锁死 | 四家适配器统一继承 `LlmServiceBase`,传输层任何失败一律产出 `LlmErrorChunk`,绝不向调用方抛异常;回归测试固化 |
| A2 | `&lt;think&gt;` 标签跨 chunk 撕裂泄漏进正文/思考 | 解析器 holdback + `finalizeStreamState()`;配套回归测试 |
| A2 关联发现 | `stripThoughtTags` 从未真正剥除内容 | 闭标签分支改为整体丢弃;单测捕获并回归 |
| A3 | 断流黑洞:body 阶段零超时 + 无停止手段 | 空闲看门狗(断流产 `LlmErrorChunk` 而非永挂)+ 发送位「停止生成」按钮(break 取消订阅,partial 落库) |
| A4 | 中途退出页面丢失已生成的回复 | `_persistPartialAssistantMessage`:unmount 先落库再退出循环 |
| A5 | 底层请求不可取消(取消订阅后服务端继续烧 token) | **每条流使用独立 `http.Client`**,generator 的 `finally` 中硬关闭——消费方 break/超时/页面退出都会真实拆除连接,服务端生成随之中止。回归:`_HoldOpenClient` 验证 `[DONE]` 早停、看门狗验证断流收场 |
| B1 | reasoning 系模型(o1/o3/gpt-5/reasoner/qwq/r1/glm-z)收到非默认采样直接 400 | 能力矩阵 `LlmServiceBase.supportsSamplingControls(model)`:命中即整体省略 temperature/frequency_penalty/presence_penalty/top_p/top_k/min_p/rep*(OpenAI 与智谱共用;Anthropic 无此限制不受影响);测试覆盖请求体 |
| B2 | baseUrl 强插 `/v1`(Gemini `/v1beta/openai`、自建 `/v2`、任意非标准路径接不上) | 三段规则:① `#` 结尾 = 显式原样使用(逃生口);② 路径已含 vX 版本段则不再补;③ 其余自动补 `/v1`。DeepSeek/智谱仍走自有覆写。四组端点用例覆盖 |
| B3 | validateApi 以 GET /models 200 判定连通(不提供列表的端点被误判失败) | `interpretModelsProbe`:404/405 → 放行并注明"已跳过列表校验";401/403 等仍如实报错 |
| B4 | fetchModels 假设 `{"data":[…]}` 单一形状 | `extractModelIds` 容忍裸数组 / `data` 形 / `models` 形;三家适配器统一走基类实现 |
| B5 | max_tokens 不受控:OpenAI 永不发、Anthropic 写死 8192 | `LlmModelConfig.maxTokens`(持久化+copyWith):OpenAI 兼容端点配置即发;Anthropic 配置覆盖默认值(缺省 8192),测试覆盖两条路径 |
| C1 | 字符串哨兵协议(`[ERROR]` 前缀 + 内联 think 标签承载通道语义) | **sealed chunk 协议**落地:`LlmContentChunk / LlmReasoningChunk / LlmNoticeChunk / LlmErrorChunk`,消费端 switch 穷尽性由编译器保证;DeepSeek `reasoning_content` 与 Anthropic `thinking_delta` 直通思考通道,不再借道文本标记(content 内的字面标签仍由解析器状态机处理,两层职责分离) |
| C2 | 接口 15 参数爆炸、厂商参数上浮 | `LlmRequest` 参数对象 + `AppController.buildLlmRequest()` 工厂;接口收敛为 `createChatCompletion(request)` / `streamChatCompletion(request)`;全部 7 处调用点(流式/重试×2/灵感×2/摘要×2)已切换 |
| C3 | 三份复制粘贴适配器行为漂移 | 流式管线、SSE 解析、错误提取、模型探针解释、响应解析、端点规则全部收口基类;智谱非流式复用 `parseOpenAiChatResponse`;DeepSeek 继承 OpenAI 实现;厂商仅剩鉴权头/端点/请求体形状差异 |
| C4(运行时) | 双真相源:补全请求读 legacy 扁平字段,配置页写实体字段 | 运行时统一从激活配置派生:`buildLlmRequest` 读 `activeModel/activeProviderConfig`,`ensureApiReady` 同步改造——请求正确性不再依赖 `_syncActiveModelToLegacyFields` 是否跑过 |
| C5 | provider/SSE 解析零单测 | `test/chat_stream_parser_test.dart`(标签撕裂/holdback/finalize/strip)+ `test/llm_service_base_test.dart`(25 用例:SSE 规范/多行 data/注释行/[DONE] 早停/类型化分片/A1 回归/看门狗/B1 请求体/B2 端点/B5 max_tokens/usage 提取/Anthropic event 解析) |
| D-debugPrint | 完整对话响应体经 debugPrint 进平台日志 | 已删除全部相关调用 |
| E-notice | finish_reason=length 截断无提示 | 流式追加 `LlmNoticeChunk("回复因达到 max_tokens 上限被截断")`,聊天页收尾展示;测试覆盖 |
| E-usage | 服务端 usage 不读取 | `ChatCompletionResult.totalTokens`:OpenAI 兼容取 `usage.total_tokens`,Anthropic 取 input+output 之和 |
| E-retry | 重试并发同刻发 3 个相同请求易触限流 | 并发批内按序错峰(300ms × index);顺序模式不变 |
| E-token | debug 豁免导致全量 BPE 卡主线程 | 近似阈值降至 6000 字符且不再豁免 debug |
| E-SSE | 多行 data: 不符规范 | 泵按规范以 `\n` 拼接同一事件的多个 data 行后再解码;注释行跳过;event 名保留;测试覆盖 |
| widget_test 存量失败 | 「与汝共奏」匹配到 2 个 widget(FitText 内部 Text 所致) | 断言放宽为 `findsWidgets`(至少渲染一次),语义不变 |

### 二、有意保留 / 遗留 📌

| 项目 | 说明 | 计划 |
|---|---|---|
| D-key:API Key 明文存 SharedPreferences | 引入 `flutter_secure_storage` 需要平台集成(Windows 凭据管理器)与**存量 Key 无损迁移**方案;在无法真机验证迁移路径的情况下贸然替换有丢 Key 风险 | 单独立项:加依赖 → 启动时读到明文即搬迁进安全存储并清除旧键 → 迁移完成标志位;迁移前保持现读取兼容 |
| C4(UI 写路径):设置页仍同时写 legacy 扁平字段 | 属设置页大重构范畴;运行时已不依赖这些字段(见上),当前仅作向后兼容的冗余写入 | 后续设置页改版时一并拆除 |
| B4(兜底差异):拉取模型失败时 OpenAI 返回空列表,智谱/Anthropic 回退内置清单 | 有意保留:通用兼容网关没有"正确的兜底名单",回退反而误导;两大官方厂商有稳定型号清单可兜底 | 维持现状 |
| 非流式补全的超时弃单 | `.timeout(completionTimeout)` 放弃后,共享连接池中的该次请求可能继续跑到服务端结束(仅浪费,不影响正确性);流式路径已通过独立客户端彻底解决 | 若实测成为问题,为非流式同样换独立客户端 |

### 下一步建议(按收益排序)

1. D-key 安全存储迁移(唯一真正的安全遗留);
2. 实机验证清单:停止生成即时生效且服务端确已中断(A5)、o3/gpt-5 正常出字(B1)、Gemini `/v1beta/openai` 可直连(B2)、404-models 网关能过校验(B3)、截断提示可见(E-notice);
3. 设置页改版时拆除 legacy 双写(C4 收尾)。

## 实机验证手册

> 配套道具:`tools/mock_llm_server.mjs`(零依赖假 LLM 服务器,已在本仓库自测通过)。
> 它同时充当**证据来源**:控制台会打印每个请求携带的采样字段(B1/B5/C4 的肉眼证据),
> 客户端中途断开时打印 `[DISCONNECT]`(A5 真取消的服务端证据)。

### 准备(两个终端)

```bash
# 终端 1:假服务器(API Key 固定为 sk-mock-123)
node tools/mock_llm_server.mjs

# 终端 2:跑起 App
flutter run -d windows
```

App 内配置(OOBE 或 设置→AI 服务):Base URL `http://127.0.0.1:8787/v1`,Key `sk-mock-123`,
点「拉取模型」应得到 gpt-4o / mock-reasoner / mock-truncate / mock-slow 四个模型。

### 场景清单

| # | 测什么 | 怎么做 | 预期 |
|---|---|---|---|
| 1 | C1 思考通道 | 选 `mock-reasoner` 发消息;长按气泡→「查看思考」 | 思考面板出现"先拆解问题……",正文只有"第一步;第二步;第三步。",两者不混 |
| 2 | A2 标签撕裂防泄漏 | 选 `gpt-4o` 发消息(剧本故意把字面标签撕成两片) | 正文无任何标签残留;"内部盘算一下"进思考面板而非正文 |
| 3 | **A3/A5 停止生成** | 选 `mock-slow`,生成 2 秒后点输入栏的 ■ 停止钮 | App:立即出「已停止生成」、已生成的句子保留、可继续发下一条;**mock 控制台立刻打 `[DISCONNECT]`**(服务端确认被掐断,旧版会继续烧完 40 句) |
| 3b | 停止按钮可见性(UI 回归) | ① 发送后输入框已清空,生成中仍应看到 ■ 停止钮;② 生成期间在输入框补几个字,点停止后不应把补的字发出去 | ① 即便无输入,生成中 ■ 恒定显示;② 停止只停止、不发送残留文字,想发再点一次发送键 |
| 4 | A4 中途退出不丢内容 | `mock-slow` 生成中直接返回会话列表,再进来 | 已生成的 partial 还在气泡里 |
| 5 | A1 错误契约 | 把 Key 改成错的再发送 | snack 显示「HTTP 401: 测试密钥不正确…」,发送键恢复可用(**不再永久转圈锁死**) |
| 6 | E 截断提示 | 选 `mock-truncate` 发消息 | 结束后提示「回复因达到 max_tokens 上限被截断。」,已出正文保留 |
| 7 | B2 端点规则 | 依次换三种 Base URL 并各发一条消息 | ① `/v1beta/openai` 与 ② `/weird/path#` 都能正常对话(mock 日志分别命中对应路径,**没有多出来的 /v1**);③ 普通 `/v1` 照常 |
| 8 | B3/B4 校验容忍与形状 | Base URL 换 `…/nomodels/v1` 点校验;换 `…/alt/v2` 点拉取模型 | 前者显示成功并注明"未提供 /models,已跳过";后者列出 bare-a/bare-b(裸数组形状也能解析) |
| 9 | B1/B5/C4 请求体肉眼验证 | ① 模型名改 `o3-mini` 发一条;② 改回 `gpt-4o`,在模型配置开自定义采样+填"单轮最大输出=512"再发 | mock 控制台:① 显示 `携带字段=[]`;② 出现 `top_p, max_tokens`。且这些值来自**模型配置页**(不动旧设置页也生效 → C4 派生) |
| 10 | D 明文 HTTP 警示 | Base URL 用本机局域网 IP(如 `http://192.168.x.x:8787/v1`,`ipconfig` 查看)点校验;再换回 127.0.0.1 | 局域网地址文案尾部有 ⚠️ 提醒;127.0.0.1 无提醒 |
| 11 | E 重说错峰 + 非流式路径 | 长按助手消息→「重说」;再用输入栏灵感入口生成一次 | mock 日志 3 条 POST 时间戳彼此错开约 0.3s(不再同刻齐发);灵感/摘要走非流式,返回含 usage 且正常展示 |
| 12 | A3 空闲看门狗(慢) | 选 `mock-stall` 发送后干等 | ~2 分钟后出「连接中断:TimeoutException…」snack 而非永远转圈 |

### 可选的真实厂商抽查

| 目标 | 做法 |
|---|---|
| B2 实弹(Gemini) | 真 Gemini Key + `https://generativelanguage.googleapis.com/v1beta/openai/`,模型 `gemini-2.0-flash`,能对话即旧版 404 问题已修 |
| B1 实弹(reasoning 系) | OpenRouter 免费额度选 o 系/reasoner 模型,或 DeepSeek 官方 `deepseek-reasoner`:不再报采样参数 400 |
| A1 对照(Anthropic) | 故意填错 Anthropic Key 发消息:snack 报错并可立即重发(修复前此场景永久卡死) |

### 判定标准

以上任一场景与"预期"不符即回归。纯传输层细节(多行 data、注释行、[DONE] 早停等)
已由 `flutter test test/llm_service_base_test.dart` 覆盖,真机不必逐条复演;
真机重点抓 **3(停止)、5(错误)、7(URL 兼容)、9(请求体)** 四项。

## 追加修复:群聊串角色 / 擅自加角色名前缀

用户反馈三联症状:① 群聊串角色(B 用 A 的身份说话);② 输出自带「角色名：」;
③ 出现「角色名A：角色名A：…」叠加。溯源结论与处置:

### 根因链

1. **格式示教(根因②)**:群聊拼历史时每条 AI 发言都被格式化为「角色名：台词」
   (`ChatMessageBuilder.resolveContentWithSpeaker`)。这是强 few-shot 示范,
   模型会模仿该格式输出——系统提示里"不要输出前缀"的一行指令敌不过整段历史的示范压力。
2. **滚雪球(根因③)**:历史加前缀前不检查文本是否已带前缀,且全/半角冒号不一致。
   模型输出 `A: xxx` 入库后,下一轮拼成 `A：A: xxx`,逐轮 +1 层。
3. **串角色(根因①)**:群聊由用户点成员头像点名发言(`_triggerTaReply`),
   身份锚只有系统提示一行锁定语句;而历史是全员带名的"剧本",user 行不带名字,
   弱模型易顺延上一条发言者的视角续演,或一次生成代写多个成员连唱。

### 处置(v2:提示词架构优先,防御降级为安全网)

**核心思路转变**:旧方案一边把历史格式化成「名字：台词」示教模型、一边命令它别这么写——
指令打不过示范,靠输出剥离兜底治标不治本。v2 从结构上消除矛盾:
**说话人信息改由 chat template 的角色通道承载**,不再依赖文本前缀约定。

| 层 | 位置 | 做法 |
|---|---|---|
| **主策略:角色通道映射(v2)** | `chat_message_builder.dart` → `historyEntryFor` / `mergeAdjacentSameRole` | 当前发言角色的历史发言 → `assistant` 消息且无任何标注;其余所有人(其他成员+人类用户)→ `user` 消息,内容以「[名字]」/「[用户]」开头标注。说话人由消息角色结构性表达:模型在自己通道里看到的全是自己说过的话,续写视角天然正确;"模仿前缀"的示范源被整体移除。相邻 user 消息自动合并(满足 Anthropic 严格交替要求)。系统提示(`chat_system_prompt.dart`)同步声明"方括号是记录元数据,不是台词格式;只写自己的下一段台词,写完即停" |
| 安全网:输出剥离 | `chat_stream_handlers.dart`(流式收尾)+ 重说候选收集处 | 入库/上屏前剥掉模型自带的「自己名字：」单层前缀。**仅作保险**:正常情况下模型不再有前缀可剥;若极端场景违规,用户也看不到脏文本 |
| 数据卫生 | 同上 | 历史拼装时 `stripThoughtTags` 照常先行;不再对存储数据做任何改写 |

**已知代价(有意接受)**:切换发言角色会改变历史的角色归属,KV cache 全量失效一次;
群聊轮次本就由人工点头像驱动、频率低,收益(结构性正确)远大于代价。

### 已知边界

- **存量展示**:修复前已入库的带前缀消息,气泡文字仍按原文显示(不改写历史数据);
  新架构下这些前缀不再进入提示词(映射时按说话人走通道,文本原样),不会继续污染模型。
- 他人名字开头的错误归属数据(A 的气泡存了 B 的台词)不做自动改写,避免误伤;
  该消息在 v2 下仍归属其 speakerTaId 的通道。

回归测试:`test/chat_group_prefix_test.dart`(17 用例:通道映射/标注/回退/合并/
端到端拼装/extraUserText 隔离/单聊不受影响/输出侧安全网)。
