#!/usr/bin/env python3
"""Build the reviewed Coder Core candidate list from Coder Dict.

The source list is ordered by programming relevance. This generator keeps the
first 500 unique terms and reduces dictionary-style translations to one concise
technical meaning. The generated list is deterministic so editorial fixes can
be reviewed as a normal diff.
"""

from __future__ import annotations

import html
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "apps/codeword/assets/vocab/qwerty_coder.json"
OUTPUT = ROOT / "apps/codeword/assets/vocab/qwerty_coder_core.json"
WORD_LIMIT = 500

TECH_MARKERS = (
    "计算机",
    "电脑",
    "程序",
    "编程",
    "代码",
    "软件",
    "网络",
    "数据",
    "文件",
    "命令",
    "函数",
    "变量",
    "接口",
    "系统",
    "目录",
    "磁盘",
    "驱动",
    "记录",
    "按键",
    "字串",
    "字符串",
    "缺省",
    "默认",
    "卷动",
    "宏",
    "缓冲",
    "模块",
    "堆栈",
    "DOS命令",
)
POS_RE = re.compile(r"(?<![A-Za-z])(n|v|vt|vi|adj|adv|prep|conj|pron|num|abbr)\.")
HAN_RE = re.compile(r"[\u4e00-\u9fff]")

OVERRIDES: dict[str, tuple[str, str]] = {
    "current": ("adj.", "当前的"),
    "change": ("v.", "更改"),
    "key": ("n.", "键、键值"),
    "if": ("conj.", "如果、条件判断"),
    "set": ("v.", "设置、集合"),
    "on": ("prep.", "开启、基于"),
    "all": ("adj.", "全部"),
    "shell": ("n.", "命令行外壳"),
    "enter": ("v.", "输入、进入"),
    "do": ("v.", "执行"),
    "select": ("v.", "选择"),
    "group": ("n.", "分组"),
    "first": ("adj.", "第一个"),
    "print": ("v.", "打印、输出"),
    "number": ("n.", "数字、编号"),
    "message": ("n.", "消息"),
    "example": ("n.", "示例"),
    "insert": ("v.", "插入"),
    "item": ("n.", "项目、条目"),
    "edit": ("v.", "编辑"),
    "marked": ("adj.", "已标记的"),
    "variable": ("n.", "变量"),
    "string": ("n.", "字符串"),
    "each": ("adj.", "每一个"),
    "following": ("adj.", "以下的"),
    "only": ("adv.", "仅、只"),
    "task": ("n.", "任务"),
    "include": ("v.", "包含"),
    "default": ("n.", "默认值"),
    "structure": ("n.", "结构"),
    "open": ("v.", "打开"),
    "enable": ("v.", "启用"),
    "erase": ("v.", "擦除"),
    "search": ("v.", "搜索"),
    "after": ("prep.", "在……之后"),
    "prompt": ("n.", "提示符、提示词"),
    "execute": ("v.", "执行"),
    "about": ("prep.", "关于"),
    "escape": ("v.", "退出、转义"),
    "same": ("adj.", "相同的"),
    "run": ("v.", "运行"),
    "store": ("v.", "存储"),
    "scroll": ("v.", "滚动"),
    "macro": ("n.", "宏"),
    "page": ("n.", "页面"),
    "reference": ("n.", "引用、参考"),
    "other": ("adj.", "其他的"),
    "while": ("conj.", "当……时、循环条件"),
    "color": ("n.", "颜色"),
    "allow": ("v.", "允许"),
    "decimal": ("n.", "十进制、小数"),
    "between": ("prep.", "在……之间"),
    "date": ("n.", "日期"),
    "remove": ("v.", "移除"),
    "arrow": ("n.", "箭头"),
    "modify": ("v.", "修改"),
    "video": ("n.", "视频"),
    "content": ("n.", "内容"),
    "either": ("pron.", "任意一个"),
    "ok": ("adj.", "确定、可用"),
    "paragraph": ("n.", "段落"),
    "exit": ("v.", "退出"),
    "find": ("v.", "查找"),
    "keyboard": ("n.", "键盘"),
    "single": ("adj.", "单个的"),
    "through": ("prep.", "通过"),
    "such": ("adj.", "这样的"),
    "but": ("conj.", "但是"),
    "highlight": ("v.", "高亮显示"),
    "until": ("conj.", "直到"),
    "place": ("v.", "放置"),
    "rename": ("v.", "重命名"),
    "swap": ("v.", "交换"),
    "close": ("v.", "关闭"),
    "unless": ("conj.", "除非"),
    "split": ("v.", "拆分"),
    "cancel": ("v.", "取消"),
    "document": ("n.", "文档"),
    "numeric": ("adj.", "数值的"),
    "go": ("v.", "执行、前往"),
    "load": ("v.", "加载"),
    "size": ("n.", "大小"),
    "install": ("v.", "安装"),
    "assign": ("v.", "赋值、指派"),
    "support": ("v.", "支持"),
    "specific": ("adj.", "特定的"),
    "skip": ("v.", "跳过"),
    "click": ("v.", "点击"),
    "otherwise": ("adv.", "否则"),
    "graphic": ("n.", "图形"),
    "sort": ("v.", "排序"),
    "bracket": ("n.", "括号"),
    "edge": ("n.", "边缘、边"),
    "form": ("n.", "表单、形式"),
    "append": ("v.", "追加"),
    "buffer": ("n.", "缓冲区"),
    "update": ("v.", "更新"),
    "automatically": ("adv.", "自动地"),
    "shortcut": ("n.", "快捷方式"),
    "condition": ("n.", "条件"),
    "complete": ("v.", "完成"),
    "network": ("n.", "网络"),
    "release": ("v.", "发布、释放"),
    "fixed": ("adj.", "固定的、已修复的"),
    "alias": ("n.", "别名"),
    "quote": ("v.", "引用"),
    "correct": ("adj.", "正确的"),
    "else": ("adv.", "否则"),
    "maximum": ("n.", "最大值"),
    "uppercase": ("n.", "大写字母"),
    "force": ("v.", "强制"),
    "lowercase": ("n.", "小写字母"),
    "temporary": ("adj.", "临时的"),
    "put": ("v.", "放置、写入"),
    "encounter": ("v.", "遇到"),
    "browse": ("v.", "浏览"),
    "loaded": ("adj.", "已加载的"),
    "variant": ("n.", "变体"),
    "normal": ("adj.", "正常的"),
    "module": ("n.", "模块"),
    "monochrome": ("adj.", "单色的"),
    "stack": ("n.", "栈、堆叠"),
    "even": ("adj.", "偶数的"),
    "scheme": ("n.", "方案"),
    "overview": ("n.", "概览"),
    "move": ("v.", "移动"),
    "choose": ("v.", "选择"),
    "letter": ("n.", "字母"),
    "add": ("v.", "添加"),
    "block": ("n.", "代码块、区块"),
    "tree": ("n.", "树形结构"),
    "continue": ("v.", "继续、跳过本次循环"),
    "begin": ("v.", "开始"),
    "turn": ("v.", "转向、转换"),
    "whether": ("conj.", "是否"),
    "write": ("v.", "写入"),
    "read": ("v.", "读取"),
    "lock": ("v.", "锁定"),
    "determine": ("v.", "判断、确定"),
    "give": ("v.", "给出"),
    "spill": ("v.", "溢出"),
    "refresh": ("v.", "刷新"),
    "pass": ("v.", "传递、通过"),
}


def concise_translation(word: str, raw: str) -> tuple[str, str]:
    override = OVERRIDES.get(word.casefold())
    if override is not None:
        return override
    clean = html.unescape(
        re.split(r"【|\[(?:记忆|搭配|例句)\]", raw, maxsplit=1)[0]
    ).strip()
    matches = list(POS_RE.finditer(clean))
    segments: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(clean)
        segments.append((f"{match.group(1)}.", clean[match.end() : end].strip()))
    if segments:
        meaningful_segments = [
            segment for segment in segments if HAN_RE.search(segment[1])
        ]
        pos, chosen = max(
            meaningful_segments or segments,
            key=lambda segment: sum(marker in segment[1] for marker in TECH_MARKERS),
        )
    else:
        pos, chosen = "", clean
    clauses = [item.strip() for item in re.split(r"[;；]", chosen) if item.strip()]
    if clauses:
        chosen = max(
            clauses,
            key=lambda clause: sum(marker in clause for marker in TECH_MARKERS),
        )
    senses = [item.strip(" ,，。") for item in re.split(r"[,，]", chosen)]
    senses = [item for item in senses if item]
    technical_senses = [
        item for item in senses if any(marker in item for marker in TECH_MARKERS)
    ]
    if technical_senses:
        senses = technical_senses
    senses = senses[:3]
    senses = [
        re.sub(r"\[(?:计算机|电脑)\]", "", item).strip() for item in senses
    ]
    senses = [re.sub(r"\s+", " ", item) for item in senses]
    meaning = "、".join(senses).strip()
    if not meaning:
        meaning = clean[:36].strip()
    if len(meaning) > 36:
        meaning = f"{meaning[:35].rstrip('、，,')}…"
    return pos, meaning


def main() -> None:
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    output: list[dict[str, object]] = []
    seen: set[str] = set()
    for item in source:
        word = str(item["word"]).strip()
        normalized = word.casefold()
        if not word or normalized in seen:
            continue
        seen.add(normalized)
        pos, meaning = concise_translation(word, str(item["translation"]))
        output.append(
            {
                "id": f"qwerty_coder_core_{len(output) + 1:05d}",
                "word": word,
                "phonetic": str(item.get("phonetic", "")),
                "pos": pos,
                "translation": meaning,
                "translations": [meaning],
                "exampleEn": f'In programming, "{word}" is a common term.',
                "exampleCn": f"在编程语境中，{word} 表示“{meaning}”。",
                "domain": "qwerty_coder_core",
                "level": str(item.get("level", "B1")),
                "synonyms": list(item.get("synonyms", [])),
                "antonyms": list(item.get("antonyms", [])),
            }
        )
        if len(output) == WORD_LIMIT:
            break
    if len(output) != WORD_LIMIT:
        raise SystemExit(f"expected {WORD_LIMIT} unique words, got {len(output)}")
    invalid = [item["word"] for item in output if not HAN_RE.search(item["translation"])]
    if invalid:
        raise SystemExit(f"translations without Chinese meaning: {', '.join(invalid)}")
    OUTPUT.write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
