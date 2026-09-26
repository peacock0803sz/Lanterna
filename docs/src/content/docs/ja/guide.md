---
title: ガイド
description: Lanternaを選ぶ理由、動作環境、インストール手順
---

## Lanternaを選ぶ理由

システムの切り替え画面やAltTab、Contextsと比べたLanternaの特徴です。

- サムネイルなしのリスト表示です。アプリアイコンとウィンドウタイトルだけのContexts風リストなので、切り替え画面が一瞬で出て、キャプチャ用のメモリをほぼ使いません。
- ウィンドウ単位で、最近使った順に切り替えます。入力による絞り込み検索とショートカットヒントに対応しています。
- 必要な権限はアクセシビリティと入力監視だけです。ウィンドウタイトルはアクセシビリティ情報から取るため、画面収録は不要です。
- Apple Silicon専用で、TahoeのLiquid Glassに対応しています。Dockアイコンなしのメニューバーアプリとして動作します。

## 動作環境

- macOS 26（Tahoe）以降
- Apple Silicon（arm64）のみ

## インストール

### ディスクイメージから

1. GitHub Releasesページから`Lanterna-X.Y.Z.dmg`をダウンロードします。アルファ版はプレリリースとして公開されます。
2. ディスクイメージを開き、`Lanterna.app`を`/Applications`にドラッグします。

### Homebrewで

```bash
brew tap peacock0803sz/lanterna https://github.com/peacock0803sz/Lanterna
brew install --cask peacock0803sz/lanterna/lanterna
```

更新するには次のコマンドを使います。

```bash
brew upgrade --cask peacock0803sz/lanterna/lanterna
```

## 初回起動と権限

初回起動時に次の2つの権限を求められます。どちらも許可してください。

- アクセシビリティ
- 入力監視

Lanternaはアクセシビリティ情報でウィンドウの一覧表示と切り替えを行います。画面収録は必要ありません。
