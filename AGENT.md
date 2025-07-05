# AGENT.md

このドキュメントは、SwiftGLTF プロジェクトにおける開発支援エージェント（AI／ボット）向けのガイドラインです。
エージェントは以下のルールに従い、課題解決やコードレビュー、ドキュメント更新などを行います。

## 0. 回答言語
- エージェントからの回答はすべて日本語で行ってください。

---

## 1. リポジトリ概要
- SwiftGLTFCore: glTF 2.0 のコアデータ構造定義
- SwiftGLTF: glTF JSON のパースと Model I/O (MDLAsset) への変換
- SwiftGLTFRenderer: Metal を使った PBR/Blinn-Phong レンダリングライブラリ
- MikkTSpace: 法線・タンジェント空間計算 C 実装
- SwiftGLTFSample: iOS/macOS 向けサンプルアプリケーション
- SwiftGLTFTests: XCTest ベースのパーサ・アセットテスト

## 2. 開発フロー
1. Issue やタスクが発行されたら、適切なブランチを作成 (`feature/`, `fix/`, `docs/` など)
2. コード変更・テスト追加・ドキュメント更新を行う
3. 自動テスト（`swift test`）が通過することを確認
4. 問題なければコミットする

## 3. コーディングガイドライン
- インデントはスペース4つ
- 型・メソッド名は PascalCase／camelCase
- 変更は最小限に留め、既存規約に整合性を持たせる

## 4. テスト
- `swift test` で XCTest が全て通過すること
- テスト追加時は `Tests/SwiftGLTFTests` に対応するリソースとテストケースを配置
- テストデータはリソースディレクトリにまとめる

## 5. ドキュメント更新
- `README.md` / `README.jp.md` に機能追加や使い方変更を反映
- コード例やスクリーンショットを適宜更新

## 6. コミットメッセージ規則
- コミットメッセージは英語で記載し、Conventional Commits に準拠（例: `feat:`, `fix:`, `docs:`）
- 1行目に要約を、空行の後に詳細説明を記載

## 7. リリース
- バージョンは Git タグで管理（例: `v1.2.3`）
- `CHANGELOG.md` がある場合は最新の変更点を追記

---
_本ファイルは自動生成・更新してください。_
