# くるぴろサイネージ（Raspberry Pi デジタルサイネージ）

Raspberry Pi 4B（8GB）を使って、バス時刻表などの Web コンテンツをサイネージ表示するための構成です。  
HDMI でディスプレイに出力し、指定した時間で自動起動・自動シャットダウンします。

ネットワーク障害時にも「接続エラー画面を出さず、ローカルのオフライン画面を常に表示する」ことを重視しています。

---

## 📦 システム構成概要

- **Raspberry Pi 4B 8GB**
- **Raspberry Pi OS (64bit / Desktop)**
- **Chromium キオスクモード**
- **nginx（ローカル Web サーバ）**
    - 上流の本番サイトに proxy
    - 接続失敗時は `offline.html` を返す（エラー画面を出さない）
- **GitHub からの起動時 `git pull` 更新**
- **毎日 8:00 に電源 ON（コンセントタイマー）**
- **毎日 21:57 に自動シャットダウン**
- **22:00 にコンセントが OFF**
- **USB キーボード・マウス禁止（usbhid 無効化）**
- **Tailscale 経由で SSH 管理**
- **Mackerel エージェントを導入（任意）**

---

## 🗂 ディレクトリ構成（推奨）
```
/opt/kurupiro
├─ scripts/
│ ├─ update.sh # 起動時の git pull
│ ├─ kiosk.sh # Chromium キオスク起動
│ ├─ reload.sh # 軽いリロード（xdotool F5）
│ └─ common.sh # 共通設定読み込み
├─ www/
│ ├─ offline.html # オフライン時に表示する画面
│ └─ offline.png # 必要なら
├─ .env.sample # URL などの設定サンプル
├─ .env # 手動作成（Gitに含めない）
└─ README.md
```

---

## 🔧 セットアップ手順

### 1️⃣ Raspberry Pi OS の準備
- Raspberry Pi OS（64bit / Desktop）をインストール
- 初期セットアップを完了
- タイムゾーンを日本に設定  
  ```bash
  sudo raspi-config
  sudo mkdir -p /opt/kurupiro
  sudo chown pi:pi /opt/kurupiro
  cd /opt/kurupiro
  git clone https://github.com/xxxxxx/kurupiro.git .
  ```