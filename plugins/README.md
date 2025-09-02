# plugins/

**SourceMod プラグインのソース (.sp) とビルド済みバイナリ (.smx)** を格納するフォルダです。  
Left 4 Dead 2 向けの TAS 支援プラグイン（HUD・記録再生ブリッジ・セットアップ補助など）が入ります。

## 収録物の例
- `tas_distance_hud.sp` / `tas_distance_hud.smx` : 距離可視化
- `tas_replay_bridge.sp` : Movement Reader 連携
- `tas_setup_assistant.sp` : 環境セットアップ補助
- `common/` : 複数プラグインで共有する stocks / ヘッダ等（任意）

## 命名規約
- プレフィックスは `tas_` を推奨（機能が一目で分かる短い名前を続ける）

## ロード・デバッグ（参考）
- 配置先：`left4dead2/addons/sourcemod/plugins/`
- 読み込み：`sm plugins load <name>` / 再読込：`sm plugins reload <name>`
- ログ：`addons/sourcemod/logs/errors_*.log`（エラー確認）

## リリース運用
- GitHub Releases に `.smx` と対応 `.sp` を同梱することを推奨
- 互換：SourceMod 1.11+（推奨 1.12+）、Left 4 DHooks Direct（最新）
