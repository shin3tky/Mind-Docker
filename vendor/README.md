# vendor/

Mind の配布物を置くディレクトリです。ライセンス上の配慮からリポジトリには含めていません
（`.gitignore` 済み）。

## 入手手順

1. [日本語プログラミング言語 Mind ダウンロードページ](https://www.scripts-lab.co.jp/mind/download/download.html) を開く
2. Linux 版 **`mind-for-linux-8.0.08.tgz`** とチェックサム
   **`mind-for-linux-8.0.08.tgz.sha256`** をダウンロードする
   （Linux 版は Version 8 が最新。Version 9 は Windows 専用）
3. このディレクトリにファイル名を変えずに置く

```
vendor/mind-for-linux-8.0.08.tgz
vendor/mind-for-linux-8.0.08.tgz.sha256
```

`make check` は、ビルド前に配布物の SHA-256 を検証します。Dockerfileも展開前に同じ値を
独立して検証するため、`make check` を経由しない直接ビルドでも不一致時は失敗します。

別バージョンを使う場合は、配布物と公式チェックサムの両方を指定します。

```sh
MIND_SHA256="$(awk '{print $1}' vendor/mind-for-linux-8.0.10.tgz.sha256)"
docker compose build \
  --build-arg MIND_TARBALL=vendor/mind-for-linux-8.0.10.tgz \
  --build-arg MIND_TARBALL_SHA256="${MIND_SHA256}" \
  mind
```
