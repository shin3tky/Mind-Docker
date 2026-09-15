# vendor/

Mind の配布物を置くディレクトリです。ライセンス上の配慮からリポジトリには含めていません
（`.gitignore` 済み）。

## 入手手順

1. [日本語プログラミング言語 Mind ダウンロードページ](https://www.scripts-lab.co.jp/mind/download/download.html) を開く
2. Linux 版 **`mind-for-linux-8.0.08.tgz`** をダウンロードする
   （Linux 版は Version 8 が最新。Version 9 は Windows 専用）
3. このディレクトリにファイル名を変えずに置く

```
vendor/mind-for-linux-8.0.08.tgz
```

別バージョンを使う場合はビルド引数で指定します。

```sh
docker compose build --build-arg MIND_TARBALL=vendor/mind-for-linux-8.0.10.tgz mind
```
