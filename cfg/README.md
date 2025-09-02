# cfg/

プラグインの **設定ファイル (.cfg)** を配置します。  
グローバル設定とマップ固有設定を分けて運用します。

## 構成例
```text
cfg/
└─ tas4l4d2/
   ├─ global.cfg          # 全体既定値
   ├─ c1m2_streets.cfg    # マップ固有
   └─ c5m5_bridge.cfg
```

## 典型的な項目
- ConVar 初期値（例：`tas_dist_interval`, `tas_dist_mode`, `tas_setup_autogive`）
- マップ固有パラメータ（開始座標・チェックポイント・閾値など）
- Movement Reader のデータファイルパス

## 記述例（global.cfg）
```cfg
// 表示更新間隔 (秒)
sm_cvar tas_dist_interval 0.25
// 表示モード: 0=off, 1=chat, 2=center, 3=hint
sm_cvar tas_dist_mode 3
```
