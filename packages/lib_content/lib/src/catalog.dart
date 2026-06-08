import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:lib_core/lib_core.dart';

/// Built-in vocabulary catalogues (metadata only — words loaded on demand).
const List<VocabList> kBuiltinLists = [
  VocabList(
    id: 'cs_core',
    name: 'CS 基础',
    description: '算法 / 数据结构 / 计算机系统',
    emoji: '💻',
    domainColor: '#6366F1',
    level: 1,
    wordCount: 50,
  ),
  VocabList(
    id: 'python_core',
    name: 'Python 核心',
    description: '语法 / 标准库 / 惯用法',
    emoji: '🐍',
    domainColor: '#3776AB',
    level: 1,
    wordCount: 50,
  ),
  VocabList(
    id: 'ai_core',
    name: 'AI 核心',
    description: '机器学习 / 深度学习 / 经典模型',
    emoji: '🧠',
    domainColor: '#10B981',
    level: 1,
    wordCount: 100,
  ),
  VocabList(
    id: 'llm_core',
    name: 'LLM 与 NLP',
    description: '大模型 / Transformer / Prompt',
    emoji: '✨',
    domainColor: '#8B5CF6',
    level: 1,
    wordCount: 50,
  ),
  VocabList(
    id: 'web_core',
    name: 'Web 前端',
    description: 'HTML / CSS / JS / 框架',
    emoji: '🌐',
    domainColor: '#F59E0B',
    level: 1,
    wordCount: 50,
  ),
  VocabList(
    id: 'devops_core',
    name: '云原生',
    description: 'Docker / K8s / CI/CD / 监控',
    emoji: '☁️',
    domainColor: '#14B8A6',
    level: 1,
    wordCount: 50,
  ),
  VocabList(
    id: 'data_core',
    name: '数据工程',
    description: 'SQL / 数仓 / Spark / 流水线',
    emoji: '📊',
    domainColor: '#EC4899',
    level: 1,
    wordCount: 50,
  ),
  VocabList(
    id: 'security_core',
    name: '安全',
    description: '密码学 / Web 安全 / 攻防',
    emoji: '🔐',
    domainColor: '#EF4444',
    level: 1,
    wordCount: 50,
  ),
  VocabList(
    id: 'product_core',
    name: '业务产品',
    description: '产品 / 增长 / 商业分析',
    emoji: '📈',
    domainColor: '#F97316',
    level: 1,
    wordCount: 50,
  ),
];

/// Loads vocabulary word lists bundled as JSON assets.
class ContentLoader {
  /// Load all words for a built-in list. Asset path: `assets/vocab/<listId>.json`.
  static Future<List<VocabWord>> loadList(String listId) async {
    final raw = await rootBundle.loadString('assets/vocab/$listId.json');
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(VocabWord.fromJson).toList(growable: false);
  }
}
