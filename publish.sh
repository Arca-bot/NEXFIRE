#!/bin/zsh
# ============================================================
# NEXFIRE 自動公開スクリプト（まとめて公開版）
#
# このフォルダ内のファイルが変更されるたびに launchd から呼ばれる。
# ただし即座には公開せず、変更が止まるのを待ってから1回だけ公開する。
#
# なぜ待つのか:
#   Netlifyは1デプロイあたり約30クレジット消費する。以前は「1保存=1デプロイ」
#   だったため、画像を置いて高さを2回調整しただけで3デプロイ(90)が走っていた。
#   2026-09-09は1日で19デプロイ＝約570クレジットを消費した。
#   変更が落ち着くまで待ってまとめれば、同じ作業が1デプロイ(30)で済む。
#
# 待機中はこのスクリプト自身がフォルダを再スキャンするので、
# launchdのイベントを取りこぼしても影響しない（重要）。
# ============================================================
export PATH="$HOME/.local/bin:/usr/bin:/bin:/usr/local/bin:$PATH"

DIR="/Users/miyazawareiou/nexfire-site"
LOG="$HOME/Library/Logs/nexfire-autopublish/publish.log"
LOCK="$HOME/.nexfire/publish.lock"

# --- 調整用 -------------------------------------------------
QUIET=180      # 最後の変更から何秒静かなら公開するか（3分）
INTERVAL=15    # 何秒ごとに様子を見るか
MAXWAIT=1800   # 保存し続けた場合でも、最長これだけ待ったら公開する（30分）
# ------------------------------------------------------------

mkdir -p "$(dirname "$LOG")" "$(dirname "$LOCK")"
cd "$DIR" || exit 1

say(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# フォルダの状態を1つの文字列にまとめる（追加・削除・更新すべてを検知）
snapshot(){
  find . -maxdepth 1 -not -name '.git' -not -name '.' \
    -exec stat -f '%N %m %z' {} \; 2>/dev/null | sort | md5 -q
}

# 変更が無ければ何もしない
if [ -z "$(git status --porcelain)" ]; then
  exit 0
fi

# --- 二重起動の防止 ---
# すでに待機中のインスタンスがあれば任せて終了する。
# 待機中インスタンスは自分で再スキャンするため、ここで諦めても取りこぼさない。
if ! mkdir "$LOCK" 2>/dev/null; then
  # 異常終了で取り残されたロックは掃除する（30分以上古いもの）
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
    say "古いロックを掃除しました"
    rmdir "$LOCK" 2>/dev/null
  fi
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

say "変更を検知。落ち着くまで待機します（${QUIET}秒静かになったら公開）"

# --- 静かになるまで待つ ---
quiet=0
waited=0
last=$(snapshot)
while [ $quiet -lt $QUIET ] && [ $waited -lt $MAXWAIT ]; do
  sleep $INTERVAL
  waited=$((waited + INTERVAL))
  now=$(snapshot)
  if [ "$now" = "$last" ]; then
    quiet=$((quiet + INTERVAL))
  else
    quiet=0            # まだ作業中。タイマーをリセット
    last="$now"
  fi
done

# 待っている間に全部元に戻された場合は何もしない
if [ -z "$(git status --porcelain)" ]; then
  say "  変更が元に戻されたため、公開しません"
  exit 0
fi

say "  変更が落ち着きました（待機${waited}秒）。まとめて公開します"

git add -A

# nexfire.html（作業用の元ファイル）が更新されたら、公開用の index.html にも反映する
if [ -f "nexfire.html" ]; then
  cp nexfire.html index.html
  git add index.html
fi

git commit -m "auto: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG" 2>&1

if ! git push origin main >> "$LOG" 2>&1; then
  say "  ⚠️ pushに失敗しました。GitHub連携を確認してください"
  osascript -e 'display notification "GitHubへのpushに失敗しました" with title "NEXFIRE 公開エラー"' 2>/dev/null
  exit 1
fi
say "  GitHubへpushしました"

# ------------------------------------------------------------
# 反映確認は最大160秒かかるため、必ずバックグラウンドに逃がす。
# 前面で待つとロックを掴んだままになり、次の変更の公開が遅れる。
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
  echo "[$(date '+%Y-%m-%d %H:%M:%S')]   ⚠️ pushは成功したが、公開サイトに反映されていません" >> "$LOG"
  osascript -e 'display notification "pushはできましたが公開サイトに反映されていません。Netlifyのデプロイを確認してください" with title "NEXFIRE 未反映"' 2>/dev/null
} >/dev/null 2>&1 &
disown 2>/dev/null
