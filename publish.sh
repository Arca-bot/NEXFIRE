#!/bin/zsh
# ============================================================
# NEXFIRE 自動公開スクリプト
# このフォルダ内のファイルが変更されるたびに、launchd から自動的に呼ばれる。
# 変更があれば GitHub に自動でコミット＆push する。
# 人の手を一切介さず動くことが目的なので、確認プロンプトは出さない。
# ============================================================
export PATH="$HOME/.local/bin:/usr/bin:/bin:/usr/local/bin:$PATH"

DIR="/Users/miyazawareiou/Desktop/Claude-NEXFIRE web"
LOG="$DIR/.publish.log"

cd "$DIR" || exit 1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] チェック開始" >> "$LOG"

# 変更が無ければ何もしない（無駄なコミットを作らない）
if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
  echo "  変更なし。終了" >> "$LOG"
  exit 0
fi

git add -A

# nexfire.html（作業用の元ファイル）が更新されたら、公開用の index.html にも反映する
if [ -f "nexfire.html" ]; then
  cp nexfire.html index.html
  git add index.html
fi

git commit -m "auto: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG" 2>&1

if git push origin main >> "$LOG" 2>&1; then
  echo "  公開に反映しました" >> "$LOG"
else
  echo "  ⚠️ pushに失敗しました。GitHub連携を確認してください" >> "$LOG"
fi
