#!/bin/bash
# 项目初始化工具包 - 卸载脚本
# 用法：bash uninstall.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
TEMPLATES_DIR="$HOME/.claude/project-templates"

echo ""
echo "=============================="
echo "  项目初始化工具包 - 卸载"
echo "=============================="
echo ""

# ----------------------------------------
# 确认
# ----------------------------------------
echo "将卸载以下内容："
echo "  - Skills: /init-project, /add-module, /entropy-review, /migrate-project"
echo "  - 脚本模板: $TEMPLATES_DIR/scripts/"
echo "  - Claude Code hook: settings.json 中的提交提醒"
echo ""
echo "不会影响："
echo "  - 已创建的项目代码"
echo "  - 项目内的 CLAUDE.md、check_boundaries.py、pre-commit hook"
echo "  - ruff、pyright、pytest 等工具"
echo ""

read -p "确认卸载？(y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消。"
    exit 0
fi

echo ""

# ----------------------------------------
# 1. 删除 Skills
# ----------------------------------------
echo "--- 卸载 Skills ---"
echo ""

SKILLS=(init-project add-module entropy-review migrate-project)
for skill in "${SKILLS[@]}"; do
    SKILL_DIR="$CLAUDE_SKILLS_DIR/$skill"
    if [ -d "$SKILL_DIR" ]; then
        rm -rf "$SKILL_DIR"
        info "已删除 /$skill"
    else
        warn "/$skill 不存在，跳过"
    fi
done

echo ""

# ----------------------------------------
# 2. 清理 Claude Code hook
# ----------------------------------------
echo "--- 清理 Claude Code Hook ---"
echo ""

if [ -f "$CLAUDE_SETTINGS" ]; then
    if command -v jq &> /dev/null; then
        # 检查是否有 hooks 配置
        HAS_HOOKS=$(jq 'has("hooks")' "$CLAUDE_SETTINGS" 2>/dev/null)
        if [ "$HAS_HOOKS" = "true" ]; then
            # 检查是否只有我们的 hook
            HOOK_COUNT=$(jq '.hooks.PreToolUse // [] | length' "$CLAUDE_SETTINGS" 2>/dev/null)
            OTHER_HOOKS=$(jq '.hooks | keys | map(select(. != "PreToolUse")) | length' "$CLAUDE_SETTINGS" 2>/dev/null)

            if [ "$OTHER_HOOKS" = "0" ] && [ "$HOOK_COUNT" = "1" ]; then
                # 只有我们的 hook，安全删除整个 hooks 配置
                cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak"
                jq 'del(.hooks)' "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp" && mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
                info "已清理提交提醒 hook（原配置备份在 settings.json.bak）"
            else
                warn "settings.json 中有其他 hook 配置，跳过清理"
                warn "如需手动清理，删除 hooks.PreToolUse 中 matcher 为 Bash 的条目"
            fi
        else
            info "settings.json 中无 hook 配置，跳过"
        fi

        # 如果 settings.json 为空对象，删除它
        REMAINING=$(jq 'keys | length' "$CLAUDE_SETTINGS" 2>/dev/null)
        if [ "$REMAINING" = "0" ]; then
            rm "$CLAUDE_SETTINGS"
            info "settings.json 已空，已删除"
        fi
    else
        warn "未安装 jq，无法安全清理 settings.json"
        warn "请手动删除 $CLAUDE_SETTINGS 中的 hooks.PreToolUse 配置"
    fi
else
    info "settings.json 不存在，跳过"
fi

echo ""

# ----------------------------------------
# 3. 删除脚本模板
# ----------------------------------------
echo "--- 清理脚本模板 ---"
echo ""

if [ -d "$TEMPLATES_DIR" ]; then
    rm -rf "$TEMPLATES_DIR"
    info "已删除 $TEMPLATES_DIR"
else
    info "脚本模板目录不存在，跳过"
fi

echo ""

# ----------------------------------------
# 4. 清理备份文件
# ----------------------------------------
if [ -f "$CLAUDE_SETTINGS.bak" ]; then
    read -p "是否删除 settings.json 的备份文件？(y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$CLAUDE_SETTINGS.bak"
        info "已删除备份文件"
    else
        info "保留备份文件：$CLAUDE_SETTINGS.bak"
    fi
fi

echo ""

# ----------------------------------------
# 完成
# ----------------------------------------
echo "=============================="
echo "  卸载完成"
echo "=============================="
echo ""
echo "以下内容未被卸载（属于项目本身，非工具包）："
echo "  - 项目内的 CLAUDE.md 文件"
echo "  - 项目内的 scripts/check_boundaries.py"
echo "  - 项目内的 .git/hooks/pre-commit"
echo "  - 项目内的 .claude/skills/（项目级 skills）"
echo ""
echo "如需清理某个项目内的这些文件，请手动删除。"
echo ""
