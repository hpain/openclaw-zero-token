#!/usr/bin/env node
import { fileURLToPath, pathToFileURL } from 'node:url'; // 1. 引入 pathToFileURL
import { dirname, resolve } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// 2. 获取绝对路径
const indexPath = resolve(__dirname, 'dist/index.mjs');

// 3. 将路径转换为 file:/// 协议的 URL 字符串
await import(pathToFileURL(indexPath).href);