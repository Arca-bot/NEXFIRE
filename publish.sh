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
# 反映確認は最大160秒かかるため、必ずバックグラウンドに逃がす。
# ここで待つと、待っている間に置かれたファイルの変更イベントを
# launchd(WatchPaths) が取りこぼす（2026-09-09に実際に発生し、
# item2〜8 の公開が遅れた）。前面では待たないこと。
# ------------------------------------------------------------
LIVE="https://nexfire.netlify.app/"
# Netlifyは公開時にHUDスクリプトを1行自動注入するため、その行を除いて比較する
WANT=$(sed '/\/\.netlify\/scripts\//d' index.html | md5 -q)

{
  for i in 1 2 3 4 5 6 7 8; do
    sleep 20
    GOT=$(curl -sf -H 'Cache-Control: no-cache' "$LIVE?cb=$RANDOM" | sed '/\/\.netlify\/scripts\//d' | md5 -q)
    if [ "$GOT" = "$WANT" ]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')]   ✅ 公開サイトへ反映を確認しました（${i}回目）" >> "$LOG"
      exit 0
    fi
  done
  echo "[$(date '+%Y-%m-%d %H:%M:%S')]   ⚠️ pushは成功したが、公開サイトに反映されていません（約3分待機）" >> "$LOG"
  echo "     → Netlifyのデプロイが止まっている可能性。Deploysタブを確認すること" >> "$LOG"
  osascript -e 'display notification "pushはできましたが公開サイトに反映されていません。Netlifyのデプロイを確認してください" with title "NEXFIRE 未反映"' 2>/dev/null
} >/dev/null 2>&1 &
disown 2>/dev/null

# push直後に増えた変更を取りこぼさないよう、その場で拾い直す。
# 深さを制限して無限ループを防ぐ。
DEPTH=${NEXFIRE_DEPTH:-0}
if [ -n "$(git status --porcelain)" ] && [ "$DEPTH" -lt 5 ]; then
  echo "  さらに変更を検知。続けて処理します（depth=$((DEPTH+1))）" >> "$LOG"
  NEXFIRE_DEPTH=$((DEPTH+1)) exec "$0"
fi
