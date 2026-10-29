#!/usr/bin/env bash
set -euo pipefail

# git worktree を作り、 メインチェックアウトにある gitignore されたローカルファイル (.env 等) を
# symlink で持ち込む。 worktree は追跡ファイルしか checkout しないので、 そのままだと
# クレデンシャルが見つからずアプリが落ちる問題への対策。
#
# usage:
#   wt add <git worktree add の引数...>   worktree を作ってから seed する
#   wt seed [<worktree dir>]              既存の worktree に seed する (省略時はカレント)
#
# 持ち込む対象はメインチェックアウト直下の .worktreeinclude (gitignore 記法) で決める。
# Claude Code が --worktree / EnterWorktree / サブエージェント用 worktree で読むのと同じファイルなので、
# 1 つ書けば Claude が作る worktree (コピー) と wt で作る worktree (symlink) の両方に効く。
# .worktreeinclude が無いリポジトリでは DEFAULT_PATTERNS を使う。
# どちらの場合も「パターンに一致し、 かつ gitignore されている」ファイルだけが対象 (追跡ファイルは触らない)。
# node_modules/ のように丸ごと ignore されたディレクトリの中身は、 パターンがそのディレクトリ名を
# 明示しているとき (例: secrets/key.json, vendor/**/config.json) だけ拾う。 Claude Code の
# .worktreeinclude と同じ考え方で、 **/.env が node_modules 内の .env まで拾うのを防ぐ。
#
# WT_COPY=1 で symlink の代わりにコピーする (Docker の build context 等、 symlink を辿らない道具向け)。
# 既に worktree 側に同名のファイル/リンクがあれば上書きしない。
#
# 注意: Claude Code の Bash から叩く前提ではない。 Claude が worktree を作るときは EnterWorktree
# (= .worktreeinclude が効く) を使う。 クレデンシャルの持ち込みを Claude 自身にやらせない。

DEFAULT_PATTERNS='**/.env
**/.env.*
**/.envrc
**/.dev.vars'

usage() {
  sed -n 's/^#   //p' "$0" >&2
  exit 2
}

main_checkout_of() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)
  dirname "$common"
}

# $2 の祖先ディレクトリのうち、 丸ごと gitignore されている最上位のものを出力する (無ければ何も出さない)
ignored_ancestor() {
  local main=$1 rel=$2 dir="" rest
  [[ $rel == */* ]] || return 0
  rest=${rel%/*}
  while :; do
    dir=${dir:+$dir/}${rest%%/*}
    if git -C "$main" check-ignore -q "$dir/"; then
      echo "$dir"
      return 0
    fi
    [[ $rest == */* ]] || return 0
    rest=${rest#*/}
  done
}

# include ファイル $1 のパターンが、 ディレクトリ $2 の構成要素をディレクトリとして明示しているか
pattern_names_dir() {
  local include=$1 dir=$2 p first comp
  local -a comps
  IFS=/ read -ra comps <<< "$dir"
  while IFS= read -r p; do
    case $p in '' | '#'* | '!'*) continue ;; esac
    p=${p#/}
    while [[ $p == '**/'* ]]; do p=${p#'**/'}; done
    [[ $p == */* ]] || continue
    first=${p%%/*}
    for comp in "${comps[@]}"; do
      [ "$comp" = "$first" ] && return 0
    done
  done < "$include"
  return 1
}

seed() {
  local wt main include tmp="" n=0 rel src dst anc
  wt=$(git -C "${1:-.}" rev-parse --show-toplevel)
  main=$(main_checkout_of "$wt")
  if [ "$wt" = "$main" ]; then
    echo "wt: $wt はメインチェックアウトです (seed するのは worktree 側)" >&2
    exit 1
  fi

  include="$main/.worktreeinclude"
  if [ ! -f "$include" ]; then
    tmp=$(mktemp)
    printf '%s\n' "$DEFAULT_PATTERNS" > "$tmp"
    include="$tmp"
  fi

  # パターンに一致する未追跡ファイル → そのうち gitignore されているものだけ。
  # ネストした worktree (.claude/worktrees/*) は別リポジトリ扱いで git が降りないので拾わない。
  while IFS= read -r -d '' rel <&3; do
    anc=$(ignored_ancestor "$main" "$rel")
    if [ -n "$anc" ] && ! pattern_names_dir "$include" "$anc"; then
      continue
    fi
    src="$main/$rel"
    dst="$wt/$rel"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    if [ "${WT_COPY:-0}" = 1 ]; then
      cp -p "$src" "$dst"
      echo "wt: copied $rel"
    else
      ln -s "$src" "$dst"
      echo "wt: linked $rel"
    fi
    n=$((n + 1))
  done 3< <(
    git -C "$main" ls-files -z --others --ignored --exclude-from="$include" |
      { git -C "$main" check-ignore -z --stdin || true; }
  )

  [ -n "$tmp" ] && rm -f "$tmp"
  echo "wt: $n file(s) seeded into $wt" >&2
}

add() {
  local before after new
  before=$(git worktree list --porcelain | sed -n 's/^worktree //p' | sort)
  git worktree add "$@"
  after=$(git worktree list --porcelain | sed -n 's/^worktree //p' | sort)
  new=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
  if [ -z "$new" ]; then
    echo "wt: 新しい worktree が見つからないので seed をスキップ" >&2
    exit 1
  fi
  seed "$new"
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
  add) [ $# -gt 0 ] || usage; add "$@" ;;
  seed) seed "${1:-.}" ;;
  *) usage ;;
esac
