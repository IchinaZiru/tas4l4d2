# scripting/

プラグイン実装を補助する **共通のヘッダやユーティリティ** を配置します。  
複数プラグインで再利用する API/定数/stock 関数をまとめます。

## 構成
- `include/` : プロジェクト固有のヘッダ（例：`tas4l4d2.inc`）
  - 共通の `const` / `enum` / stock / forward / native の宣言を配置
  - 外部公開する簡易 API があればここに定義

## 参照例
```cpp
#include <sourcemod>
#include <tas4l4d2>   // scripting/include/tas4l4d2.inc を参照
```

## バージョニング方針
- 破壊的変更は `inc` 側の `#define TAS4L4D2_API_VERSION` を更新し、CHANGELOG に記録
- 互換が切れる変更は SemVer に従いマイナー以上を更新
