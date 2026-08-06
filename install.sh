#!/bin/bash

set -euo pipefail

AGENTS_DIR="$HOME/agents"

# 确保指定路径是一个真实目录，而不是软链接。
ensure_real_directory() {
    local directory="$1"

    if [ -L "$directory" ]; then
        # 只删除软链接本身，不删除它指向的目录。
        unlink "$directory"
    elif [ -e "$directory" ] && [ ! -d "$directory" ]; then
        echo "错误：$directory 已存在，但不是目录。"
        exit 1
    fi

    mkdir -p "$directory"
}

# 删除目标位置的原文件、目录或软链接，然后重新创建软链接。
replace_with_symlink() {
    local source="$1"
    local target="$2"

    if [ ! -e "$source" ]; then
        echo "错误：源路径不存在：$source"
        exit 1
    fi

    # 不要给 target 添加结尾斜杠。
    rm -rf "$target"
    ln -s "$source" "$target"

    echo "$target -> $source"
}

# Claude
mkdir -p "$HOME/.claude"
ensure_real_directory "$HOME/.claude/skills"

replace_with_symlink \
    "$AGENTS_DIR/CLAUDE.md" \
    "$HOME/.claude/CLAUDE.md"

replace_with_symlink \
    "$AGENTS_DIR/skills/app-store-screenshots" \
    "$HOME/.claude/skills/app-store-screenshots"

replace_with_symlink \
    "$AGENTS_DIR/skills/swiftui-performance-audit" \
    "$HOME/.claude/skills/swiftui-performance-audit"

# Codex
mkdir -p "$HOME/.codex"
ensure_real_directory "$HOME/.codex/skills"

replace_with_symlink \
    "$AGENTS_DIR/AGENTS.md" \
    "$HOME/.codex/AGENTS.md"

replace_with_symlink \
    "$AGENTS_DIR/skills/app-store-screenshots" \
    "$HOME/.codex/skills/app-store-screenshots"

replace_with_symlink \
    "$AGENTS_DIR/skills/swiftui-performance-audit" \
    "$HOME/.codex/skills/swiftui-performance-audit"