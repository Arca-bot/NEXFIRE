#!/bin/zsh
# ============================================================
# NEXFIRE 自動公開スクリプト
# このフォルダ内のファイルが変更されるたびに、launchd から自動的に呼ばれる。
# 変更があれば GitHub に自動でコミット＆push する。
# 人の手を一切介さず動くことが目的なので、確認プロンプトは出さない。
# ============================================================
export PATH="$HOME/.local/bin:/usr/bin:/bin:/usr/local/bin:$PATH"

DIR="/Users/miyazawareiou/nexfire-site"
# ログは監視対象フォルダの外（自分の書き込みで再発火するのを防ぐため）
LOG="$HOME/Library/Logs/nexfire-autopublish/publish.log"
mkdir -p "$(dirname "$LOG")"

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

if ! git push origin main >> "$LOG" 2>&1; then
  echo "  ⚠️ pushに失敗しました。GitHub連携を確認してください" >> "$LOG"
  osascript -e 'display notification "GitHubへのpushに失敗しました" with title "NEXFIRE 公開エラー"' 2>/dev/null
  exit 1
fi
echo "  GitHubへpushしました" >> "$LOG"

# ------------------------------------------------------------
# ここまでは push が通っただけ。実際に公開サイトへ反映されたかを確認する。
# （Netlifyのデプロイが止まっていても push は成功するため、
#   「pushできた＝公開された」と思い込まないための検証）
# ------------------------------------------------------------
LIVE="https://nexfire.netlify.app/"
WANT=$(md5 -q index.html)

for i in 1 2 3 4 5 6 7 8; do
  sleep 20
  GOT=$(curl -sf -H 'Cache-Control: no-cache' "$LIVE?cb=$RANDOM" | md5 -q)
  if [ "$GOT" = "$WANT" ]; then
    echo "  ✅ 公開サイトへ反映を確認しました（${i}回目）" >> "$LOG"
    exit 0
  fi
done

echo "  ⚠️ pushは成功したが、公開サイトに反映されていません（約3分待機）" >> "$LOG"
echo "     → Netlifyのデプロイが止まっている可能性。Deploysタブを確認すること" >> "$LOG"
osascript -e 'display notification "pushはできましたが公開サイトに反映されていません。Netlifyのデプロイを確認してください" with title "NEXFIRE 未反映"' 2>/dev/null
