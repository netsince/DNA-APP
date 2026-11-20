#!/usr/bin/env node
// 更新工程内的「模型能力快照」（数据源：https://models.dev/api.json，MIT）。
//
// 用法：
//   node tools/update_model_capabilities.mjs            # 联网抓取 → 写 assets/data/model_capabilities.json
//   node tools/update_model_capabilities.mjs --check    # 只报告差异，不写文件（CI 可用）
//   node tools/update_model_capabilities.mjs --offline  # 用 .cache/models.dev.api.json 重建（无网时）
//
// 为什么只存「裁剪版」：原始 api.json 有几 MB，全塞进 assets 会让安装包白胖一圈；
// 我们只用得到「能不能吃图/音/视频 + 上下文窗口」这几项，裁剪后只有几百 KB。
// 原始响应仍会留一份在 .cache/（已 gitignore），方便离线重跑与排查。

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { gzipSync } from 'node:zlib';
import { dirname, resolve } from 'node:path';

const SOURCE = 'https://models.dev/api.json';
const RAW_CACHE = resolve('.cache/models.dev.api.json');
const OUT_FILE = resolve('assets/data/model_capabilities.json.gz');

const args = new Set(process.argv.slice(2));
const checkOnly = args.has('--check');
const offline = args.has('--offline');

/** 归一化模型 id：小写、去 provider 前缀、去日期后缀与 -latest。 */
export function normalizeModelId(raw) {
  let id = String(raw ?? '').trim().toLowerCase();
  if (!id) return '';
  id = id.replace(/^[a-z0-9_.-]+\//, '');
  id = id.replace(/[-@](?:20\d{2}-?\d{2}-?\d{2}|20\d{6})$/, '');
  id = id.replace(/-(?:latest|preview|stable)$/, '');
  return id;
}

/** 从 models.dev 的 provider→models 结构里抽出能力表。 */
export function extractCapabilities(api) {
  const models = {};
  const providers = Object.values(api ?? {});
  for (const provider of providers) {
    const providerId = String(provider?.id ?? '');
    const providerModels = provider?.models ?? {};
    for (const [modelId, model] of Object.entries(providerModels)) {
      const input = Array.isArray(model?.modalities?.input)
        ? model.modalities.input.map((m) => String(m).toLowerCase())
        : null;
      const caps = {
        image: input ? input.includes('image') : Boolean(model?.attachment),
        audio: input ? input.includes('audio') : false,
        video: input ? input.includes('video') : false,
        pdf: Boolean(model?.attachment),
        context: Number(model?.limit?.context ?? 0) || 0,
        toolCall: Boolean(model?.tool_call),
        reasoning: Boolean(model?.reasoning),
      };
      // 同一模型可能挂在多个 provider 下：能力取并集（任一 provider 支持就算支持），
      // 上下文取最大值。这样用户换中转也不会突然「不支持」。
      const key = normalizeModelId(modelId || model?.id);
      if (!key) continue;
      const prev = models[key];
      if (!prev) {
        models[key] = caps;
      } else {
        models[key] = {
          image: prev.image || caps.image,
          audio: prev.audio || caps.audio,
          video: prev.video || caps.video,
          pdf: prev.pdf || caps.pdf,
          context: Math.max(prev.context, caps.context),
          toolCall: prev.toolCall || caps.toolCall,
          reasoning: prev.reasoning || caps.reasoning,
        };
      }
      // 完整 id（provider/model）单独留一份，精确匹配时优先用它。
      if (providerId) {
        models[providerId.toLowerCase() + '/' + key] = caps;
      }
    }
  }
  return models;
}

function sortObject(obj) {
  return Object.fromEntries(Object.keys(obj).sort().map((k) => [k, obj[k]]));
}

async function loadSource() {
  if (offline) {
    const raw = await readFile(RAW_CACHE, 'utf8');
    return { text: raw, fromCache: true };
  }
  const res = await fetch(SOURCE, { headers: { 'accept': 'application/json' } });
  if (!res.ok) throw new Error('抓取失败：HTTP ' + res.status);
  const text = await res.text();
  await mkdir(dirname(RAW_CACHE), { recursive: true });
  await writeFile(RAW_CACHE, text, 'utf8');
  return { text, fromCache: false };
}

async function main() {
  const { text, fromCache } = await loadSource();
  let api;
  try {
    api = JSON.parse(text);
  } catch {
    throw new Error('数据源不是合法 JSON（可能被拦截/改版），已中止，现有快照未被修改');
  }
  const models = extractCapabilities(api);
  const ids = Object.keys(models);
  if (ids.length < 50) {
    throw new Error('只解析出 ' + ids.length + ' 个模型，明显异常，已中止（防止把坏数据写进工程）');
  }
  const imageCount = ids.filter((k) => models[k].image).length;
  // 紧凑格式：key → [image, audio, video, pdf, context, toolCall, reasoning]
  // 用数组而不是对象，体积能省一半以上；再 gzip 一层（运行时用 archive 的 GZipDecoder 解，Web 也支持）。
  const compact = {};
  for (const id of Object.keys(models).sort()) {
    const m = models[id];
    compact[id] = [
      m.image ? 1 : 0,
      m.audio ? 1 : 0,
      m.video ? 1 : 0,
      m.pdf ? 1 : 0,
      m.context,
      m.toolCall ? 1 : 0,
      m.reasoning ? 1 : 0,
    ];
  }
  const payload = {
    v: 1,
    fields: ['image', 'audio', 'video', 'pdf', 'context', 'toolCall', 'reasoning'],
    generatedAt: new Date().toISOString().slice(0, 10),
    source: SOURCE,
    modelCount: ids.length,
    imageModelCount: imageCount,
    models: compact,
  };
  const out = JSON.stringify(payload);
  const gz = gzipSync(Buffer.from(out, 'utf8'), { level: 9 });

  let prev = null;
  try {
    prev = await readFile(OUT_FILE);
  } catch {}
  const changed = !prev || !prev.equals(gz);
  console.log('[capabilities] 数据源' + (fromCache ? '（本地缓存）' : '（在线）'));
  console.log('[capabilities] 模型 ' + ids.length + ' 个，其中支持图片 ' + imageCount + ' 个');
  console.log('[capabilities] 原始 ' + (out.length / 1024).toFixed(0) + ' KB → gzip ' + (gz.length / 1024).toFixed(0) + ' KB');
  if (checkOnly) {
    console.log('[capabilities] --check：' + (changed ? '有差异（需要更新）' : '与工程内快照一致'));
    process.exitCode = changed ? 2 : 0;
    return;
  }
  if (!changed) {
    console.log('[capabilities] 无需更新');
    return;
  }
  await mkdir(dirname(OUT_FILE), { recursive: true });
  await writeFile(OUT_FILE, gz);
  console.log('[capabilities] 已更新');
}

await main();
