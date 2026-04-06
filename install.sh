#!/bin/bash
# 项目初始化工具包 - 安装脚本
# 用法：bash install.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo ""
echo "=============================="
echo "  项目初始化工具包 - 安装"
echo "=============================="
echo ""

# ----------------------------------------
# 1. 安装 Skills
# ----------------------------------------
echo "--- 安装 Claude Code Skills ---"
echo ""

mkdir -p "$CLAUDE_SKILLS_DIR"

SKILLS=(init-project add-module entropy-review migrate-project)
for skill in "${SKILLS[@]}"; do
    SKILL_SRC="$SCRIPT_DIR/.claude/skills/$skill"
    SKILL_DST="$CLAUDE_SKILLS_DIR/$skill"

    if [ ! -d "$SKILL_SRC" ]; then
        error "找不到 $skill skill 源文件：$SKILL_SRC"
        continue
    fi

    if [ -d "$SKILL_DST" ]; then
        warn "/$skill 已存在，覆盖更新"
        rm -rf "$SKILL_DST"
    fi

    cp -r "$SKILL_SRC" "$SKILL_DST"
    info "已安装 /$skill"
done

echo ""

# ----------------------------------------
# 2. 安装 Claude Code settings hook
# ----------------------------------------
echo "--- 配置 Claude Code Hook ---"
echo ""

HOOK_CMD='bash -c '"'"'INPUT=$(cat); CMD=$(echo "$INPUT" | jq -r ".tool_input.command // empty"); if echo "$CMD" | grep -qE "^git commit"; then echo "提交前检查：\n1. 修改了模块职责？→ 更新 __init__.py\n2. 新增状态转换？→ 更新 VALID_TRANSITIONS + TRANSITION_SIDE_EFFECTS\n3. 新增副作用？→ 添加 service.py handler\n4. 发现新的坑？→ 更新模块 CLAUDE.md\n5. 跨模块边界歧义？→ 更新根 CLAUDE.md 边界表\n6. pytest 和 check_boundaries.py 是否通过"; fi'"'"''

if [ -f "$CLAUDE_SETTINGS" ]; then
    # 检查是否已有 hooks 配置
    if command -v jq &> /dev/null; then
        HAS_HOOK=$(jq -r '.hooks.PreToolUse // empty' "$CLAUDE_SETTINGS" 2>/dev/null)
        if [ -n "$HAS_HOOK" ] && [ "$HAS_HOOK" != "null" ]; then
            warn "settings.json 已有 hook 配置，跳过（避免覆盖你的自定义 hook）"
            warn "如需添加提交提醒 hook，请手动合并 .claude/settings.json"
        else
            # 合并 hook 到现有配置
            cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak"
            jq '.hooks = {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "'"$(echo "$HOOK_CMD" | sed 's/"/\\"/g')"'"}]}]}' "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp" && mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
            info "已添加提交提醒 hook（原配置备份在 settings.json.bak）"
        fi
    else
        warn "未安装 jq，无法安全合并 settings.json"
        warn "请手动将 .claude/settings.json 的内容合并到 $CLAUDE_SETTINGS"
    fi
else
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    cp "$SCRIPT_DIR/.claude/settings.json" "$CLAUDE_SETTINGS"
    info "已创建 settings.json 并配置提交提醒 hook"
fi

echo ""

# ----------------------------------------
# 3. 复制脚本模板
# ----------------------------------------
echo "--- 安装脚本模板 ---"
echo ""

TEMPLATES_DIR="$HOME/.claude/project-templates"
mkdir -p "$TEMPLATES_DIR/scripts"

cp "$SCRIPT_DIR/scripts/check_boundaries.py" "$TEMPLATES_DIR/scripts/"
cp "$SCRIPT_DIR/scripts/pre-commit" "$TEMPLATES_DIR/scripts/"
chmod +x "$TEMPLATES_DIR/scripts/pre-commit"

info "已安装 check_boundaries.py 到 $TEMPLATES_DIR/scripts/"
info "已安装 pre-commit hook 到 $TEMPLATES_DIR/scripts/"

echo ""

# ----------------------------------------
# 4. 检查依赖
# ----------------------------------------
echo "--- 检查依赖 ---"
echo ""

MISSING=()

if command -v ruff &> /dev/null; then
    info "ruff $(ruff --version 2>/dev/null | head -1)"
else
    MISSING+=("ruff")
    warn "ruff 未安装"
fi

if command -v pyright &> /dev/null; then
    info "pyright $(pyright --version 2>/dev/null | head -1)"
else
    MISSING+=("pyright")
    warn "pyright 未安装"
fi

if command -v pytest &> /dev/null; then
    info "pytest $(pytest --version 2>/dev/null | head -1)"
else
    MISSING+=("pytest")
    warn "pytest 未安装"
fi

if command -v jq &> /dev/null; then
    info "jq $(jq --version 2>/dev/null)"
else
    MISSING+=("jq")
    warn "jq 未安装（Claude Code hook 需要 jq 解析输入）"
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    warn "以下依赖缺失，建议安装："
    echo "  pip install ${MISSING[*]}"
fi

echo ""

# ----------------------------------------
# 5. 完成
# ----------------------------------------
echo "=============================="
echo "  安装完成"
echo "=============================="
echo ""
echo "已安装的 Skills："
echo "  /init-project      新项目初始化"
echo "  /add-module        添加业务模块"
echo "  /entropy-review    熵减审计"
echo "  /migrate-project   旧项目迁移"
echo ""
echo "脚本模板位置："
echo "  $TEMPLATES_DIR/scripts/"
echo ""
echo "下一步："
echo "  1. 安装 LSP 插件（在 Claude Code 中）：/plugin install pyright-lsp@claude-plugins-official"
echo "  2. 新项目初始化：/init-project"
echo "  3. 旧项目迁移：/migrate-project"
echo ""
