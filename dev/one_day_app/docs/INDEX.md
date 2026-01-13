# ドキュメント目次

## 概要

このディレクトリには、ライフサイクル契約(v2)に関するドキュメントが含まれています。

## ドキュメント一覧

### 責務分界・保証範囲

- [SCOPE_AND_LIMITS.md](SCOPE_AND_LIMITS.md)
  - 保証されること／保証しないこと
  - 利用者側の責務
  - 変更時の再検証要件

### 運用・トラブルシュート

- [OPERATIONS.md](OPERATIONS.md)
  - Traceログ有効化の手順
  - よくある症状と対処
  - ログの保管ルール
  - 監査・引き継ぎの観点

### Releaseビルド注意点

- [RELEASE_CHECK.md](RELEASE_CHECK.md)
  - assertが削除されること
  - stopAllTimers()がassert外であるべき理由
  - Release前チェックリスト

### 変更履歴

- [CHANGELOG.md](CHANGELOG.md)
  - v2確定の宣言
  - 今後の変更記録

### 検証結果

- [LIFECYCLE_CONTRACT_V2_VERIFICATION.md](../LIFECYCLE_CONTRACT_V2_VERIFICATION.md)
  - 実測ベースの検証結果
  - 各テストの検証条件・判定ロジック・観測結果

## 関連ドキュメント

### 実装詳細

- [LIFECYCLE_CONTRACT_V2.md](../LIFECYCLE_CONTRACT_V2.md)
  - 実装の詳細
  - v1からの変更点

### メインドキュメント

- [README.md](../README.md)
  - アプリケーションの概要
  - ライフサイクル契約(v2)の概要

## ドキュメントの読み方

### 初めて読む場合

1. [README.md](../README.md)で概要を把握
2. [SCOPE_AND_LIMITS.md](SCOPE_AND_LIMITS.md)で保証範囲を確認
3. [OPERATIONS.md](OPERATIONS.md)で運用方法を理解

### 問題が発生した場合

1. [OPERATIONS.md](OPERATIONS.md)の「よくある症状と対処」を確認
2. [LIFECYCLE_CONTRACT_V2_VERIFICATION.md](../LIFECYCLE_CONTRACT_V2_VERIFICATION.md)で検証結果を確認
3. 必要に応じて[RELEASE_CHECK.md](RELEASE_CHECK.md)を参照

### 変更を行う場合

1. [SCOPE_AND_LIMITS.md](SCOPE_AND_LIMITS.md)の「変更時の再検証要件」を確認
2. [LIFECYCLE_CONTRACT_V2_VERIFICATION.md](../LIFECYCLE_CONTRACT_V2_VERIFICATION.md)に従って再検証
3. [CHANGELOG.md](CHANGELOG.md)に変更内容を記録
