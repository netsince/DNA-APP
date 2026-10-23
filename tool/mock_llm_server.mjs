#!/usr/bin/env node
/**
 * 本地假 LLM 服务器 —— 用于真机手动验证 AI 层改动(AI_LAYER_REVIEW.md 实机验证手册)。
 *
 * 零依赖,Node >= 18 运行:
 *   node tools/mock_llm_server.mjs
 *
 * 约定:
 *   - 任何路由都打印请求日志;POST /chat/completions 会额外打印请求体里
 *     我们关心的字段是否存在(temperature / top_p / max_tokens ...),
 *     用于肉眼验证 B1 能力矩阵、B5 max_tokens、C4 配置派生。
 *   - API Key 必须是 `sk-mock-123`,否则返回 401 + 中文 error.message,
 *     用于验证错误文案提取与"失败后不锁死"(A1)。
 *   - 流式输出每 350ms 吐一片,给你时间点「停止生成」;
 *     客户端中途断开时会打印 `[DISCONNECT]` —— 这就是 A5 真取消的服务端证据。
 *
 * 路由一览(配合不同的 baseUrl 填法,验证 B2 端点规则):
 *   GET  /v1/models                      OpenAI 形列表
 *   GET  /alt/v2/models                  裸数组形列表(vX 段路径,不应被补 /v1)
 *   GET  /v1beta/openai/models           {"models":[…]} 形(Gemini 兼容层式路径)
 *   GET  /nomodels/v1/models             404(验证 B3:无 /models 也放行)
 *   POST 以上各自前缀下的 /chat/completions
 *   baseUrl 填 `http://127.0.0.1:8787/weird/path#` 时会打到 /weird/path/chat/completions(# 不会发给服务器)
 */
import http from 'node:http';

const PORT = 8787;
const KEY = 'sk-mock-123';
const DRIP_MS = 350;

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

function sendJson(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

/** 打印请求体中我们关心的采样字段是否存在(B1/B5/C4 的肉眼证据)。 */
function summarizeBody(body) {
  const flags = {
    temperature: 'temperature' in body,
    frequency_penalty: 'frequency_penalty' in body,
    presence_penalty: 'presence_penalty' in body,
    top_p: 'top_p' in body,
    top_k: 'top_k' in body,
    min_p: 'min_p' in body,
    repetition_penalty: 'repetition_penalty' in body,
    max_tokens: 'max_tokens' in body,
    thinking: 'thinking' in body,
    reasoning_effort: 'reasoning_effort' in body,
  };
  const present = Object.entries(flags).filter(([, v]) => v).map(([k]) => k);
  return `model=${body.model} stream=${!!body.stream} 携带字段=[${present.join(', ') || '无采样参数'}]`;
}

function openAiChunk(delta, extra = {}) {
  return JSON.stringify({
    choices: [{ delta, ...extra }],
  });
}

/**
 * 核心:按剧本向客户端滴灌 SSE。
 * script: 数组,元素为 {delta?, extra?, raw?, pauseMs?}
 */
async function dripSse(res, script, { tag = '' } = {}) {
  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache',
    connection: 'keep-alive',
  });
  let finished = false;
  res.on('close', () => {
    if (!finished) log(`[DISCONNECT] ${tag} 客户端在流结束前断开 ← A5 真取消证据`);
  });

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  for (const step of script) {
    if (res.writableEnded || res.destroyed) return;
    if (step.pauseMs) {
      await sleep(step.pauseMs);
      continue;
    }
    if (step.comment !== undefined) {
      res.write(`: ${step.comment}\n`); // SSE 注释行(E-SSE 应被忽略)
      continue;
    }
    const payload =
      step.raw !== undefined ? step.raw : openAiChunk(step.delta ?? {}, step.extra ?? {});
    res.write(`data: ${payload}\n\n`);
    await sleep(step.ms ?? DRIP_MS);
  }
  finished = true;
  res.write('data: [DONE]\n\n');
  res.end();
}

/** 默认流式剧本:注释行 + 多行 data + 思考 + 正文(内含字面标签撕裂) + 正常收尾。 */
function defaultScript() {
  const TAG_OPEN = '<thi' + 'nk>';
  const TAG_CLOSE = '</thi' + 'nk>';
  return [
    { comment: 'keep-alive ping(应被忽略)' },
    // 多行 data:一个事件拆两行,拼回后才是合法 JSON(E-SSE)
    { raw: '{"choices":[{"delta":' + '\n{"content":"你好"}}]}' },
    { delta: { reasoning_content: '用户在打招呼,' } },
    { delta: { reasoning_content: '我该回应问候。' } },
    // 字面思考标签故意跨片撕裂,验证 A2 holdback 不泄漏进正文
    { delta: { content: `${TAG_OPEN}内部盘算一下${TAG_CLOSE}` } },
    { delta: { content: '你好呀!' } },
    { delta: { content: '今天想聊点什么?' } },
  ];
}

function scriptFor(model) {
  if (model === 'mock-truncate') {
    return [
      { delta: { content: '这段回答本来很长很长,' } },
      { delta: { content: '但是在这里被上限掐断了' } },
      { delta: {}, extra: { finish_reason: 'length' } }, // E-notice 截断提示
    ];
  }
  if (model === 'mock-reasoner') {
    return [
      { delta: { reasoning_content: '先拆解问题……' } },
      { delta: { reasoning_content: '再分三步作答……', pauseMs: 600 } },
      { delta: { content: '第一步;第二步;第三步。' } },
    ];
  }
  if (model === 'mock-stall') {
    // 只回头注释心跳,永不给数据 → 触发空闲看门狗(默认 120s)。
    return [
      { comment: 'stall...' , ms: 100 },
      { pauseMs: 10 * 60 * 1000 },
    ];
  }
  if (model === 'mock-slow') {
    // 慢速长文:专门留时间给你点「停止生成」。
    return Array.from({ length: 40 }, (_, i) => ({ delta: { content: `第${i + 1}句。` } }));
  }
  return defaultScript();
}

async function handleChat(req, res, url) {
  let raw = '';
  req.on('data', (c) => (raw += c));
  req.on('end', async () => {
    let body = {};
    try {
      body = JSON.parse(raw || '{}');
    } catch {
      /* 忽略畸形体 */
    }
    log(`POST ${url.pathname} ← ${summarizeBody(body)}`);

    const auth = req.headers['authorization'] ?? '';
    if (auth !== `Bearer ${KEY}`) {
      // A1/错误提取:非 200 必须以 LlmErrorChunk 收场并展示中文原因。
      return sendJson(res, 401, {
        error: { message: '测试密钥不正确(应为 sk-mock-123)' },
      });
    }

    const wantsStream = !!body.stream;
    const script = scriptFor(String(body.model ?? ''));
    if (!wantsStream) {
      // 非流式:灵感/摘要走这条路。带 usage 验证 E-usage 解析。
      const text = (script.length ? '' : '') + '这是非流式的完整回复。';
      return sendJson(res, 200, {
        choices: [{ message: { role: 'assistant', content: text } }],
        usage: { prompt_tokens: 12, completion_tokens: 34, total_tokens: 46 },
      });
    }
    await dripSse(res, script, { tag: url.pathname });
  });
}

const MODELS_OPENAI = { data: [{ id: 'gpt-4o' }, { id: 'mock-reasoner' }, { id: 'mock-truncate' }, { id: 'mock-slow' }] };
const MODELS_BARE = [{ id: 'bare-a' }, { id: 'bare-b' }];
const MODELS_MODELS_KEY = { models: [{ id: 'm-key-a' }, { id: 'm-key-b' }] };

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  log(`${req.method} ${url.pathname}`);

  if (req.method === 'GET' && (url.pathname === '/v1/models' || url.pathname === '/v1beta/openai/models')) {
    return sendJson(res, 200, MODELS_OPENAI);
  }
  if (req.method === 'GET' && url.pathname === '/alt/v2/models') {
    return sendJson(res, 200, MODELS_BARE); // B4:裸数组形状
  }
  if (req.method === 'GET' && url.pathname === '/nomodels/v1/models') {
    return sendJson(res, 404, { error: { message: '这里故意不提供模型列表' } }); // B3
  }

  if (req.method === 'POST' && url.pathname.endsWith('/chat/completions')) {
    return void handleChat(req, res, url);
  }

  sendJson(res, 404, { error: { message: `mock 未实现:${req.method} ${url.pathname}` } });
});

server.listen(PORT, () => {
  log(`mock LLM 已就绪 → http://127.0.0.1:${PORT} 与 http://<本机LAN IP>:${PORT}  (Key: ${KEY})`);
});
