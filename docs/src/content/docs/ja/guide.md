---
title: ガイド
description: Lanternaを選ぶ理由、動作環境、インストール手順
---

## Lanternaを選ぶ理由

システムの切り替え画面やAltTab, Contextsと比べたLanternaの特徴です。

- サムネイルを撮らず、アプリアイコンとウィンドウタイトルだけをContexts風のリストで並べます。そのため切り替え画面が一瞬で出て、キャプチャ用のメモリもほとんど使いません。
- ウィンドウを最近使った順に切り替えます。文字入力による絞り込みとショートカットヒントにも対応しています。
- 必要な権限はアクセシビリティと入力監視だけです。ウィンドウタイトルはアクセシビリティ情報から取るため、画面収録は不要です。
- Apple Silicon専用で、Tahoe以降のLiquid Glassに対応しています。Dockアイコンなしのメニューバーアプリとして動作します。

## 動作環境

- macOS 26 (Tahoe)以降
- Apple Silicon (arm64)のみ

## インストール方法

### ディスクイメージから

1. GitHub Releasesページから`Lanterna-X.Y.Z.dmg`をダウンロード
2. ディスクイメージを開き、`Lanterna.app`を`/Applications`にドラッグ

### Homebrewで

```bash
brew tap peacock0803sz/lanterna https://github.com/peacock0803sz/Lanterna
brew install --cask peacock0803sz/lanterna/lanterna
brew upgrade --cask peacock0803sz/lanterna/lanterna  # 更新
```

## 初回起動と権限

初回起動時に次の2つの権限を求められるので、どちらも許可してください。

- アクセシビリティ
- 入力監視

:::note
Lanternaはアクセシビリティ情報をもとにウィンドウを一覧し、切り替えます。画面収録は必要ありません。
:::
