# Zellij レイアウト設計

> プロジェクトごとに Claude Code + シェルペインを事前定義し、起動一発で開発環境を構築する。

## 課題

毎朝の開発開始時に、複数プロジェクトのディレクトリを開き、Claude Code を起動し、dev サーバーを立ち上げるのに時間がかかっていた。

## 解決策

Zellij の KDL レイアウトファイルで、プロジェクトごとにタブ・ペインを事前定義。`zellij --layout work.kdl` で全てが立ち上がる。

## レイアウト一覧

### work.kdl — メインの開発レイアウト

10タブ構成で、各プロジェクトに Claude Code を割り当て:

```
┌─────────────────────────────────────────────────────────────┐
│ Alchemy │ English │ Widget │ Sort │ Menu │ Croupier │ ...   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────┐       │
│  │  claude-zellij "Alchemy" --dangerously-skip...  │ ← expanded
│  ├─────────────────────────────────────────────────┤       │
│  │  nr dev                                         │ ← stacked (suspended)
│  └─────────────────────────────────────────────────┘       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**特徴**:
- `claude-zellij` ラッパーでタブ名キャッシュを自動設定
- `start_suspended true` で起動時にリソースを消費しない
- `stacked=true` で Claude Code と dev サーバーをスタック表示
- `-c` フラグで会話を継続

**タブ構成**:

| タブ名 | プロジェクト | ペイン構成 |
|-------|------------|----------|
| Alchemy | alchemy | Claude + `nr dev` (stacked) |
| English | learn-english-app | Claude |
| Widget | web-progressive | Claude |
| Sort | wevox | Claude |
| Menu | web-progressive | Neovim |
| Croupier | croupier | Claude + `nr dev` (stacked) |
| Analytics | web-progressive | Claude |
| dotfiles | dotfiles | Claude |
| DesignSystem | atrae-ui | Claude + shell (stacked) |
| Logo | wevox-logo-generator | Claude |

### cockpit.kdl — 4x2 グリッドの指揮レイアウト

複数プロジェクトの Claude Code を同時に表示し、全体を俯瞰する:

```
┌─────────────────────────┬─────────────────────────┐
│  Claude (wevox)         │  Shell (free)           │
│  --remote-control       │                         │
├─────────────────────────┼─────────────────────────┤
│  Claude (web-prog)      │  Shell (free)           │
│  --remote-control       │                         │
├─────────────────────────┼─────────────────────────┤
│  Claude (rest-bff)      │  Shell (free)           │
│  --remote-control       │                         │
├─────────────────────────┼─────────────────────────┤
│  Claude (wevox-front)   │  Claude (dotfiles)      │
│  --remote-control       │  --remote-control       │
└─────────────────────────┴─────────────────────────┘
```

**特徴**:
- 左列: プロジェクト別 Claude Code（`--remote-control` 付き）
- 右列: 自由に使えるシェルペイン
- 各ペインは `stacked=true` で複数のペインを切り替え可能
- `start_suspended true` で必要なプロジェクトだけ起動

## セットアップ

### レイアウトファイルの配置

Nix Home Manager で `~/.config/zellij/layouts/` に自動配置:

```nix
xdg.configFile."zellij/layouts" = {
  source = ./programs/zellij/layouts;
  recursive = true;
};
```

### レイアウトの起動

```bash
# work レイアウトで起動
zellij --layout work

# cockpit レイアウトで起動
zellij --layout cockpit
```

### Zellij の自動起動

zsh の initContent で、ターミナル起動時に Zellij を自動起動:

```bash
if [[ -z "$ZELLIJ" && -z "$VSCODE_INJECTION" ]]; then
  eval "$(zellij setup --generate-auto-start zsh)"
fi
```

## KDL レイアウトの書き方

### 基本構造

```kdl
layout {
    cwd "/Users/username"  // ベースディレクトリ

    tab name="TabName" {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar"  // タブバー
        }
        pane command="claude-zellij" cwd="Projects/my-project" {
            args "TabName" "--dangerously-skip-permissions"
            start_suspended true  // 手動で起動するまで待機
        }
        pane size=1 borderless=true {
            plugin location="zellij:status-bar"  // ステータスバー
        }
    }
}
```

### スタックペイン

```kdl
pane stacked=true {
    pane command="claude" expanded=true {
        // メインペイン（デフォルトで展開）
    }
    pane command="nr" {
        args "dev"
        start_suspended true
        // サブペイン（折りたたみ）
    }
}
```

### グリッドレイアウト

```kdl
pane split_direction="horizontal" {
    pane split_direction="vertical" {
        pane { /* 左上 */ }
        pane { /* 左下 */ }
    }
    pane split_direction="vertical" {
        pane { /* 右上 */ }
        pane { /* 右下 */ }
    }
}
```

## 主要ファイル

| ファイル | 役割 |
|---------|------|
| [`nix/home-manager/programs/zellij/layouts/work.kdl`](../../nix/home-manager/programs/zellij/layouts/work.kdl) | メイン開発レイアウト |
| [`nix/home-manager/programs/zellij/layouts/cockpit.kdl`](../../nix/home-manager/programs/zellij/layouts/cockpit.kdl) | 指揮レイアウト |

## カスタマイズ

### タブを追加する

`work.kdl` に新しいタブを追加:

```kdl
tab name="NewProject" hide_floating_panes=true {
    pane size=1 borderless=true {
        plugin location="zellij:tab-bar"
    }
    pane command="claude-zellij" cwd="Projects/new-project" {
        args "NewProject" "--dangerously-skip-permissions"
        start_suspended true
    }
    pane size=1 borderless=true {
        plugin location="zellij:status-bar"
    }
}
```

### dev サーバー付きタブ

```kdl
tab name="MyApp" {
    pane size=1 borderless=true { plugin location="zellij:tab-bar" }
    pane stacked=true {
        pane command="claude-zellij" cwd="Projects/my-app" expanded=true {
            args "MyApp" "--dangerously-skip-permissions"
            start_suspended true
        }
        pane command="nr" cwd="Projects/my-app" {
            args "dev"
            start_suspended true
        }
    }
    pane size=1 borderless=true { plugin location="zellij:status-bar" }
}
```

## Tips & 注意点

- **`start_suspended true`**: ペインは起動時に待機状態になり、Enter を押すとコマンドが実行される。10タブ全てが同時起動するとリソースが逼迫するため必須
- **`hide_floating_panes=true`**: フローティングペインを非表示にして、メインのペインに集中できるようにする
- **`--remote-control`**: Cockpit レイアウトでは Claude Code を remote-control モードで起動。外部からプロンプトを送信できる
- **cwd の指定**: レイアウトの `cwd` はベースディレクトリ、各ペインの `cwd` は相対パスで指定
- **new_tab_template**: 新しいタブを作成した時のデフォルトテンプレートを定義できる
