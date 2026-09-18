# Mind-Docker

[![Trivy package scan](https://github.com/shin3tky/Mind-Docker/actions/workflows/trivy.yml/badge.svg?branch=main)](https://github.com/shin3tky/Mind-Docker/actions/workflows/trivy.yml)

日本語プログラミング言語 [Mind](https://www.scripts-lab.co.jp/mind/whatsmind.html)（Scripts Lab Inc.）の
Linux 版を macOS 上の Docker で動かします。

Mind 8 for Linux の配布物は **x86 32bit** バイナリです。本リポジトリは
[公式のインストール手順（Linux）](https://www.scripts-lab.co.jp/mind/ver8/doc/operation-1b-Install-linux.html)
に沿って、**64bit OS 上に 32bit の glibc / libgcc を導入する**流れをそのまま Dockerfile にしたものです。

ソースは **UTF-8 のまま**扱えます。Mind 本体は EUC-JP 固定ですが、同梱のラッパー
（`mindc` / `mindrun`）が境界でだけ変換するので、エディタや Git の設定を EUC-JP に
寄せる必要はありません。素の `mind` コマンドもそのまま使えます。

ビルド後に `make selftest` を実行すると、`hello, world` のコンパイルと実行まで一通り確認できます。

最終イメージは専用の `mind` ユーザー（UID/GID 10001）で動作します。ビルド時だけ root を使い、
コンパイラ、生成プログラム、同梱ラッパーは非 root で実行されます。ホスト側のディレクトリを
マウントして成果物を書き戻す場合は、UID 10001 から書き込める権限を与えてください。

---

## 必要なもの

- Docker（Docker Desktop / Docker Engine）
- `vendor/mind-for-linux-8.0.08.tgz` … 公式サイトから各自でダウンロードして配置（[手順](vendor/README.md)）

## セキュリティ検査

GitHub Actions では、最終イメージと同じ Debian パッケージ集合を持つ Dockerfile の `base`
ステージを Trivy で検査します。High / Critical のうち修正版が提供されている脆弱性が見つかると
ワークフローは失敗します。Pull Request、`main` への push、毎週月曜日、および手動実行が対象です。

ベースイメージ `debian:bookworm-slim` は OCI digest で固定しています。Mind の配布物も、公式の
SHA-256 をビルド引数 `MIND_TARBALL_SHA256` の既定値として保持し、展開前に検証します。

Mind の公式配布物は再配布しないため、CI ではそれを必要としない `base` ステージだけをビルドします。
`runtime` ステージは追加の Debian パッケージを導入しないため、OS パッケージの検査範囲は同一です。

> **Linux 版は Version 8 が最新です。** Version 9 は Windows 専用のため、本リポジトリは Version 8 を対象にしています。

---

## 使い方

```sh
# 0) この環境で 32bit x86 バイナリが動くかを先に確認（Apple Silicon では特に推奨）
make doctor

# 1) 配布物が置かれているか確認
make check

# 2) ビルド
make build

# 3) hello, world まで一通り動くか確認
make selftest

# 4) UTF-8 のソースをそのままコンパイルして実行
make hello
```

`make selftest` の出力:

```
=== (1) 公式手順どおり EUC-JP のソースを mind に渡す ===
こんにちは、世界
=== (2) ラッパー経由で UTF-8 のソースをそのまま ===
こんにちは、世界
=== (3) 標準入力も UTF-8 のまま渡せる ===
お名前を入力してください＞世界さん、こんにちは
=== (4) 入力待ちのプロンプトが入力前に表示される ===
プロンプトを確認しました
お名前を入力してください＞世界さん、こんにちは

mind-selftest: OK - この環境で Mind が動作しています
```

`make hello` の出力:

```
日本語プログラミング言語 Ｍｉｎｄ Version 8.07 for UNIX
          Copyright(C) 1985 Scripts Lab. Inc.
コンパイル中 .. 終了
Coping.. /opt/mind/pmind/bin/mindex --> hello
mindc: /tmp/h/hello を生成しました
こんにちは、世界
```

公式手順そのまま（EUC-JP に変換して素の `mind` を叩く）を確認したい場合:

```sh
make hello-raw
```

### コンテナの中で触る

```sh
make shell
```

```sh
# コンテナ内。/work にリポジトリがマウントされている
cd /tmp && cp /work/samples/*.src . && mindc hello.src file && mindrun ./hello
```

| コマンド | 説明 |
|---|---|
| `mind <base> <lib>` | 本物の Mind コンパイラ。EUC-JP のソースを要求する |
| `mindc <src> <lib>` | **UTF-8 のソース**をコンパイルするラッパー |
| `mindrun <exe> [引数]` | 実行ファイルを入出力 UTF-8 で実行するラッパー |
| `mindconv <元> <先>` | 届いたぶんを即座に書き出す文字コード変換フィルタ |
| `mind-inspect` | 配布物の中身（同梱 `.src` / `bin` / `lib`）を調べる |
| `mind-selftest` | 上記が一通り動くかをまとめて確認する |

---

## Dockerfile が公式手順のどこに対応しているか

| 公式手順 | Dockerfile |
|---|---|
| 64bit OS では `glibc.i386` / `libgcc.i386` を確認 | `dpkg --add-architecture i386` → `libc6:i386` `libgcc-s1:i386` |
| 開発環境が無ければ `binutils` / `gcc` / `make` を導入 | `binutils` `gcc` `make` に加え、`CC = gcc -m32` のため `gcc-multilib` |
| `tar xzpf` で展開（`p` オプション必須） | `tar xzpf`（`cgilib/` 配下が 777 を要求するため） |
| `kernel/` で `make clean` / `make all` / `make install` | builder ステージで実行 |
| `PATH` / `MLIBPATH` / `LANG=ja_JP.eucJP` を設定 | `ENV` で設定。`ja_JP.EUC-JP` ロケールを `locale-gen` |
| （手順外） | UTF-8 のまま扱うための `mindc` / `mindrun` / `mindconv` と動作確認用の `mind-selftest` を `/usr/local/bin` に配置 |

インストール先は公式手順の `~/pmind` ではなく **`/opt/mind/pmind`** です。
builder ステージでは `HOME=/opt/mind` を設定しているので、配布物側が `~` を参照しても整合します。

イメージは 2 ステージ構成で、最終イメージ（`runtime`）にはコンパイラ類は残らず、
32bit ランタイムと `/opt/mind/pmind` だけが入ります。

---

## 文字コード — UTF-8 のまま書く仕組み

Mind 8 for Linux は **EUC-JP 固定**です（Windows 版は Shift_JIS）。
一方このリポジトリのソースは UTF-8 で管理したいので、`mindc` / `mindrun` が境界でだけ変換します。

```
samples/hello.src (UTF-8)
  └─ mindc ─┬→ .mindbuild/hello.src (EUC-JP) を作る
            ├→ 本物の mind でコンパイル
            ├→ コンパイラの出力を EUC-JP → UTF-8 に戻して表示
            └→ 実行ファイル・.mco/.sym/.his/.inf を元のディレクトリへ書き戻す

./hello
  └─ mindrun ─┬→ 標準入力を UTF-8 → EUC-JP
              └→ 標準出力・標準エラーを EUC-JP → UTF-8
```

### mindc

```sh
mindc hello.src file      # 拡張子は省略可: mindc hello file
```

- ソースのあるディレクトリの `*.src` をまとめて EUC-JP に変換し、`.mindbuild/` の中でコンパイルします
  （副ソースを読み出す構成でも動くようにするため）
- **すでに EUC-JP で書かれている `.src` はそのまま複写**するので、UTF-8 と EUC-JP が混在していても動きます
- 文法エラーのときは `.inf`（インフォメーションファイル）の中身を UTF-8 で表示し、原本も書き戻します
  - `.inf` は文法エラー時のみ生成されるため、前回の残骸を必ず消してからコンパイルします
- EUC-JP に無い文字（絵文字、`①` など）があると変換時にエラーで止まります。
  Mind のソースとして無効なので、握り潰さずエラーにしています
- ソースのファイル名は ASCII のみ（Mind が実行ファイル名にそのまま使うため）

| 環境変数 | 既定 | 意味 |
|---|---|---|
| `MIND_SRC_ENCODING` | `UTF-8` | ソースの文字コード |
| `MIND_BUILD_DIR` | `<ソースの場所>/.mindbuild` | 変換後のソースを置く場所 |
| `MIND_KEEP_BUILD` | `1` | `0` にすると `MIND_BUILD_DIR` 内に専用の一時ディレクトリを作り、終了時にそれだけを削除する |

`MIND_BUILD_DIR` にシンボリックリンク、ルートディレクトリ、ソースディレクトリ自体は指定できません。
変換後のソースと成果物は一時ファイルから原子的に置き換えるため、既存のシンボリックリンク先を
上書きしません。

### mindrun

```sh
mindrun ./hello
echo "森田" | mindrun ./greet
mindrun ./greet            # 対話実行。プロンプトが出てから入力できる
```

標準入力・標準出力・標準エラーの 3 本すべてを変換します。

### mindconv — なぜ iconv ではないのか

`iconv(1)` は入力をまとめて読んでから変換するため、**改行で終わらないプロンプトが
入力待ちの間 表示されません**。Mind の対話プログラムは

```
「お名前を入力してください＞」を　表示し
文字列入力し　名前に　入れ
```

のようにプロンプトを改行なしで出してから入力を待つので、`iconv` を挟むと
画面に何も出ないまま入力待ちになってしまいます（`stdbuf` でも解決しません。
`nkf` も同様に溜め込みます）。

そこで、読めたぶんをそのまま変換して即座に書き出す小さなフィルタ
[`docker/src/mindconv.c`](docker/src/mindconv.c) を用意し、`mindrun` はこれを使います。
`read(2)` の境界で多バイト文字が切れた場合は次の読み込みまで持ち越します。

```sh
mindconv EUC-JP UTF-8 < euc.txt
```

`mind-selftest` の (4) は、この「入力前にプロンプトが出る」ことを実際に検査します。

変換結果は `iconv -c` と完全に一致します（不正バイトは読み飛ばす、という挙動も含めて）。
イメージ内では `-Werror -Wconversion` や `_FORTIFY_SOURCE` / `fstack-protector-strong` /
RELRO+BIND_NOW / PIE を付けてビルドしています。

### 素の mind を使う場合

ラッパーを使わず公式手順どおりに扱うこともできます。その場合ソースは EUC-JP で用意します。

```sh
iconv -f UTF-8 -t EUC-JP hello.src > /tmp/hello.src
cd /tmp && mind hello file && ./hello | iconv -f EUC-JP -t UTF-8
```

### サンプル

`samples/` の中身は UTF-8 です（`.gitattributes` で改行の自動変換を抑止）。

`samples/hello.src`:

```
メインとは
	「こんにちは、世界」を　表示し　改行する。
```

`samples/greet.src`（標準入力の変換を確認するためのもの）:

```
メインとは
	名前は　文字列　※　変数定義
	「お名前を入力してください＞」を　表示し
	文字列入力し　名前に　入れ
	名前を　表示し
	「さん、こんにちは」を　表示し　改行する。
```

---

## 生成された実行ファイルを動かすとき

Mind が生成する実行ファイルは、起動時に同名のランタイム（`mrunt010` など）を **`PATH` から探します**。
`PATH` に `/opt/mind/pmind/bin` が入っていないと次のエラーになります。

```
Can't execute Mind runtime library(mrunt010)
```

本イメージでは `PATH` / `MLIBPATH` を `ENV` で設定済みなのでそのまま動きますが、
実行ファイルだけを別の場所へ持ち出す場合はランタイムも併せて必要になります。

---

## Apple Silicon（M1/M2/M3…）で使う場合

Docker Desktop の **Settings → General → Virtual Machine Options** で選べる VMM は次の 2 つです。

| VMM | Rosetta 設定 | 本リポジトリでの可否 |
|---|---|---|
| **Docker VMM** | Rosetta 非対応（設定項目そのものが無い） | そのまま動く。amd64 はエミュレーションになるぶん遅い |
| **Apple Virtualization framework** | `Use Rosetta for x86_64/amd64 emulation on Apple Silicon` で切替 | チェックを **外す** こと |

Rosetta は **x86_64 専用**の変換レイヤで、**32bit (i386) のバイナリは翻訳しません**。
そのため「Apple Virtualization framework ＋ Rosetta 有効」の組み合わせでは、amd64 コンテナの中で
Mind の 32bit バイナリを起動できず、`make selftest` が失敗します。

これは Apple のドキュメントからも確認できます。Linux VM で Rosetta を有効にする手順では、
Rosetta を **x86_64 の ELF だけ**を対象とする binfmt ハンドラとして登録しています。

```
sudo /usr/sbin/update-binfmts --install rosetta /tmp/mountpoint/rosetta \
    --magic "\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00" ...
```

`magic` の `\x02`（5 バイト目）は ELF クラス = **64bit**、`\x3e\x00`（19〜20 バイト目）は
マシン種別 = **EM_X86_64** を意味します。32bit の i386 ELF（クラス = `\x01`、マシン種別 = `\x03\x00`）は
このパターンに一致しないため、Rosetta には渡りません。

- [About the Rosetta translation environment](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment) — "Rosetta is a translation process that allows users to run Mac apps that contain x86_64 instructions on Apple silicon."
- [Running Intel Binaries in Linux VMs](https://developer.apple.com/documentation/Virtualization/running-intel-binaries-in-linux-vms) — "Run x86_64 Linux binaries under ARM Linux on Apple silicon."

> **QEMU について**
> 2025 年 8 月に QEMU は **VMM（ハイパーバイザ）の選択肢としては削除**されましたが、
> [非ネイティブアーキテクチャのエミュレーション用途の QEMU は残っています](https://www.docker.com/blog/docker-desktop-for-mac-qemu-virtualization-option-to-be-deprecated-in-90-days/)。
> Rosetta を使わないときの amd64 / i386 コンテナの実行はこちらが担当します。

念のため、ビルドを回す前に `make doctor` で実測できます。
`/lib/ld-linux.so.2` 自身が 32bit ELF なので、これが起動できれば Mind も動きます。

```sh
make doctor
# --- 32bit x86 実行テスト ---
# ld.so (Debian GLIBC ...) stable release version 2.36.
# OK: 32bit x86 バイナリを実行できます
```

---

## Windows（WSL2 + Docker Desktop）で使う場合

Windows は x64 なので `linux/amd64` がネイティブで動きます。エミュレーションが挟まらないぶん、
Apple Silicon より速く、Rosetta まわりの注意も不要です。

### 操作は WSL2 のシェルから

PowerShell には `make` がありません。Docker Desktop の
**Settings → Resources → WSL Integration** で使う WSL ディストリビューションを有効にしたうえで、
WSL2 のシェルから実行してください。`make` が無ければ入れます。

```sh
sudo apt update && sudo apt install -y make
```

### 改行コード（重要）

Windows の Git は既定で `core.autocrlf=true` のため、**指定しないとチェックアウト時に
ファイルが CRLF になります**。そうなると Linux コンテナの中で

```
/usr/bin/env: 'bash\r': No such file or directory
```

となり、`mindc` などのスクリプトが起動できません。本リポジトリは `.gitattributes` で
`* text=auto eol=lf` を指定して LF に固定しているので、通常は意識不要です。

`.gitattributes` が入る前にクローンしていた場合は、作業ツリーを取り直してください。

```sh
git pull
git rm --cached -r .
git reset --hard
```

確認:

```sh
file docker/bin/mindc     # "CRLF" と出なければ OK
```

> Dockerfile 側にも保険として CR を落とす処理を入れてありますが、`Makefile` や
> `Dockerfile` 自体は Git のチェックアウト結果がそのまま効くので、`.gitattributes` が本筋です。

### リポジトリの置き場所

`/mnt/c/...`（NTFS）でも動きますが、バインドマウントが遅くなります。
**WSL2 側のファイルシステム**（`~/Mind-Docker` など）に置くほうが快適です。

```sh
git clone <このリポジトリ> ~/Mind-Docker
cd ~/Mind-Docker
```

### 手順

あとは macOS/Linux と同じです。`vendor/` に配布物を置くのを忘れずに。

```sh
make doctor     # x64 なので通るはず
make check
make build
make selftest
make hello
```

---

## トラブルシュート

| 症状 | 対処 |
|---|---|
| `make doctor` が NG | Apple Virtualization framework なら Rosetta のチェックを外す。Docker VMM に切り替えるのも可。それでも駄目なら `make doctor PLATFORM=linux/386` |
| `exec format error` / `make selftest` が NG | 同上。32bit x86 バイナリを実行できていない |
| `COPY vendor/... not found` | `vendor/*.tgz` が無い。`make check` で確認 |
| `kernel/ が見つかりません` | 配布物が壊れている。`tar tzf vendor/*.tgz \| head` で確認 |
| `make all` が失敗 | ベースを新しくしていないか確認。gcc 14 以降は非対応（下記） |
| 日本語が化ける | コンテナ内で `locale` を確認。`ja_JP.eucJP` になっていること |
| `/usr/bin/env: 'bash\r'` / `'\r': command not found` | Windows で CRLF のままチェックアウトされている。上の「Windows」→「改行コード」を参照 |
| `EUC-JP に変換できませんでした` | ソースに EUC-JP へ変換できない文字（絵文字、`①` など）が含まれている |
| 実行結果が文字化けする | `./hello` を直接叩いていないか。`mindrun ./hello` を使うか `iconv -f EUC-JP -t UTF-8` を通す |
| 入力待ちのプロンプトが出ない | `iconv` を挟んでいないか。`mindrun` 経由なら `mindconv` が使われる（`mind-selftest` の (4) で検査） |

### gcc のバージョンについて

`kernel/makefile` は 1998 年からの C ソースをビルドします。
`-Wint-conversion` / `-Wincompatible-pointer-types` の警告が出るため、
これらを既定でエラーにする **gcc 14 以降ではビルドが通りません**。

- Debian bookworm（gcc 12）… 本リポジトリの既定
- Ubuntu 24.04（gcc 13）… 動作確認済み
- Debian trixie 以降 / Ubuntu 25.04 以降（gcc 14+）… 非対応

どうしても make が通らない場合、配布物には 32bit ELF のビルド済みバイナリが同梱されているので、
それをそのまま使うこともできます。

```sh
docker compose build --build-arg SKIP_KERNEL_MAKE=1 mind
```

### どうしても 64bit 上で 32bit を動かせない場合

最初から 32bit のベースイメージを使う逃げ道もあります（この場合 `gcc-multilib` 相当は不要ですが、
本リポジトリの Dockerfile はそのままで動きます）。

```sh
docker build --platform linux/386 --build-arg BASE_PLATFORM=linux/386 -t mind-docker:386 .
```

---

## 動作確認済みの構成

| ホスト環境 | 確認内容 |
|---|---|
| **Windows 11 Pro** + WSL2 + Docker Desktop（x64） | `make doctor` → `make build` → `make selftest` すべて通過 |
| **macOS**（Apple Silicon）+ Docker Desktop | イメージのビルドと、コンテナ内でのコンパイル・実行を確認 |
| **x86_64 Linux**（glibc 2.39 / gcc 13.3） | 公式手順どおりの導入で `kernel` の make から hello, world まで |

検証の内訳:

- **導入手順** … `dpkg --add-architecture i386` → `libc6:i386` `libgcc-s1:i386` → `gcc-multilib` →
  `make clean` / `make all` / `make install` 成功 → `mind hello file` → `./hello` → `こんにちは、世界`
- **ラッパー** … UTF-8 の `hello.src` を `mindc` → `mindrun` で実行。`greet.src` へ UTF-8 の標準入力を
  渡して往復とも確認。対話時にプロンプトが入力前に出ることも確認
- **mindconv** … `iconv -c` との差分テスト（有効な入力 200 件・不正バイト 200 件・ランダム分割
  ストリーミング 300 件）で完全一致。ASan/UBSan 下でのファズ 1200 回、valgrind でエラー・リークなし

---

## ライセンス

本リポジトリのファイルは Apache License 2.0 です（[LICENSE](LICENSE)）。

Mind 本体は Scripts Lab Inc. の著作物で、フリーソフトウェアとして配布されています。
再配布条件や、Mind で開発したアプリケーションの実行に必要なランタイム（`mruntNNN`）の
取り扱いについては、配布物同梱の `README.txt` に従ってください。
