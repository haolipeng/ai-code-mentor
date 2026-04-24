#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_ROOT=".claude-mentor-backup"

usage() {
    echo "用法:"
    echo "  $0 install  <目标文件夹>   安装 ai-code-mentor 配置"
    echo "  $0 restore  <目标文件夹>   从备份恢复原有配置"
    exit 1
}

resolve_target() {
    local raw="${1:?}"
    local resolved
    resolved="$(cd "$raw" 2>/dev/null && pwd)" || {
        echo "错误: 目标文件夹 '$raw' 不存在"
        exit 1
    }
    if [ "$SCRIPT_DIR" = "$resolved" ]; then
        echo "错误: 目标文件夹不能是本项目自身"
        exit 1
    fi
    echo "$resolved"
}

do_install() {
    local TARGET_DIR
    TARGET_DIR="$(resolve_target "$1")"

    NEED_BACKUP=false
    if [ -f "$TARGET_DIR/CLAUDE.md" ] || [ -d "$TARGET_DIR/.claude/commands" ]; then
        NEED_BACKUP=true
        echo "检测到目标文件夹已存在以下内容:"
        [ -f "$TARGET_DIR/CLAUDE.md" ] && echo "  - CLAUDE.md"
        [ -d "$TARGET_DIR/.claude/commands" ] && echo "  - .claude/commands/"
        read -rp "是否覆盖？已有文件将先备份到 $BACKUP_ROOT/  (y/N): " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            echo "已取消"
            exit 0
        fi
    fi

    # 备份
    if [ "$NEED_BACKUP" = true ]; then
        local BACKUP_DIR="$TARGET_DIR/$BACKUP_ROOT/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        [ -f "$TARGET_DIR/CLAUDE.md" ] && cp "$TARGET_DIR/CLAUDE.md" "$BACKUP_DIR/"
        [ -d "$TARGET_DIR/.claude/commands" ] && mkdir -p "$BACKUP_DIR/.claude" && cp -r "$TARGET_DIR/.claude/commands" "$BACKUP_DIR/.claude/"
        echo "已备份到 $BACKUP_DIR"
    fi

    # 安装
    cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
    mkdir -p "$TARGET_DIR/.claude/commands"
    cp "$SCRIPT_DIR/.claude/commands/"*.md "$TARGET_DIR/.claude/commands/"

    echo "安装完成! 已配置到 $TARGET_DIR"
}

do_restore() {
    local TARGET_DIR
    TARGET_DIR="$(resolve_target "$1")"
    local BACKUP_BASE="$TARGET_DIR/$BACKUP_ROOT"

    if [ ! -d "$BACKUP_BASE" ]; then
        echo "没有找到备份目录 ($BACKUP_BASE)"
        exit 1
    fi

    # 列出所有备份，按时间倒序
    local backups=()
    while IFS= read -r d; do
        backups+=("$d")
    done < <(ls -1rd "$BACKUP_BASE"/*/ 2>/dev/null)

    if [ ${#backups[@]} -eq 0 ]; then
        echo "备份目录为空，没有可恢复的备份"
        exit 1
    fi

    echo "可用备份:"
    for i in "${!backups[@]}"; do
        local name
        name="$(basename "${backups[$i]}")"
        # 展示备份中包含的内容
        local contents=""
        [ -f "${backups[$i]}/CLAUDE.md" ] && contents="CLAUDE.md"
        [ -d "${backups[$i]}/.claude/commands" ] && contents="${contents:+$contents, }.claude/commands/"
        echo "  [$((i+1))] $name  ($contents)"
    done

    local choice
    read -rp "选择要恢复的备份编号 [1]: " choice
    choice="${choice:-1}"

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
        echo "无效选择"
        exit 1
    fi

    local selected="${backups[$((choice-1))]}"

    # 恢复 CLAUDE.md
    if [ -f "$selected/CLAUDE.md" ]; then
        cp "$selected/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
        echo "已恢复 CLAUDE.md"
    else
        rm -f "$TARGET_DIR/CLAUDE.md"
        echo "已移除 CLAUDE.md (原项目中不存在)"
    fi

    # 恢复 .claude/commands/
    rm -rf "$TARGET_DIR/.claude/commands"
    if [ -d "$selected/.claude/commands" ]; then
        cp -r "$selected/.claude/commands" "$TARGET_DIR/.claude/commands"
        echo "已恢复 .claude/commands/"
    else
        echo "已移除 .claude/commands/ (原项目中不存在)"
        # 如果 .claude/ 目录为空则一并清理
        [ -d "$TARGET_DIR/.claude" ] && rmdir "$TARGET_DIR/.claude" 2>/dev/null || true
    fi

    echo "恢复完成! (备份来源: $(basename "$selected"))"
}

# 主入口
ACTION="${1:-}"
TARGET="${2:-}"

case "$ACTION" in
    install)
        [ -z "$TARGET" ] && usage
        do_install "$TARGET"
        ;;
    restore)
        [ -z "$TARGET" ] && usage
        do_restore "$TARGET"
        ;;
    *)
        usage
        ;;
esac
