# 日本語プログラミング言語 Mind Version 8 (for Linux) を Docker で動かすイメージ。
#
# 公式のインストール手順に従う:
#   https://www.scripts-lab.co.jp/mind/ver8/doc/operation-1b-Install-linux.html
#
#   ・Mind 8 for Linux の配布物は x86 32bit (little endian) コード
#   ・64bit OS 上で動かすため glibc / libgcc の 32bit 版を導入する
#     （公式手順の glibc.i386 / libgcc.i386 = Debian では libc6:i386 / libgcc-s1:i386）
#   ・ソースおよびコンパイラの入出力は EUC-JP
#
# ビルド前に vendor/mind-for-linux-8.0.08.tgz を置くこと（vendor/README.md 参照）。

ARG DEBIAN_TAG=bookworm-slim
# 64bit を前提にした構成。どうしても 64bit 上で 32bit を動かせない環境向けの
# 逃げ道として linux/386 も指定できる。
ARG BASE_PLATFORM=linux/amd64

# ---------------------------------------------------------------------------
# base: 64bit OS + 32bit ランタイム + EUC-JP ロケール
# ---------------------------------------------------------------------------
FROM --platform=${BASE_PLATFORM} debian:${DEBIAN_TAG} AS base

ENV DEBIAN_FRONTEND=noninteractive \
    MIND_HOME=/opt/mind \
    MIND_ROOT=/opt/mind/pmind

# 公式手順の環境変数。LANG=ja_JP.eucJP は glibc のコードセット正規化で
# ja_JP.EUC-JP ロケールに解決される。
ENV MLIBPATH=${MIND_ROOT}/lib \
    PATH=${MIND_ROOT}/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=ja_JP.eucJP \
    JLESSCHARSET=japanese

# 「64bit OS の場合は glibc.i386 / libgcc.i386 を確認」に対応する手順
RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libc6:i386 \
        libgcc-s1:i386 \
        locales; \
    sed -i -E 's/^# *(ja_JP\.EUC-JP EUC-JP)/\1/' /etc/locale.gen; \
    sed -i -E 's/^# *(ja_JP\.UTF-8 UTF-8)/\1/'   /etc/locale.gen; \
    sed -i -E 's/^# *(en_US\.UTF-8 UTF-8)/\1/'   /etc/locale.gen; \
    locale-gen; \
    rm -rf /var/lib/apt/lists/*; \
    test -e /lib/ld-linux.so.2

# UTF-8 で書いたソースをそのまま扱うためのラッパー。
# Mind 本体は EUC-JP 固定なので、境界でだけ変換する（README「文字コード」参照）。
COPY docker/bin/ /usr/local/bin/
RUN set -eux; \
    sed -i 's/\r$//' \
        /usr/local/bin/mindc \
        /usr/local/bin/mindrun \
        /usr/local/bin/mind-inspect \
        /usr/local/bin/mind-selftest; \
    chmod 0755 \
        /usr/local/bin/mindc \
        /usr/local/bin/mindrun \
        /usr/local/bin/mind-inspect \
        /usr/local/bin/mind-selftest

# ---------------------------------------------------------------------------
# builder: 配布物を展開し、kernel を make する
# ---------------------------------------------------------------------------
FROM base AS builder

# 「開発環境がない場合は binutils, gcc, make 等をインストール」に対応する手順。
# kernel/makefile が CC = "gcc -m32" 固定なので 64bit 側では gcc-multilib が要る。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        binutils \
        gcc \
        gcc-multilib \
        make; \
    rm -rf /var/lib/apt/lists/*

# 配布物の Makefile が ~ を参照しても壊れないよう HOME を合わせる
ENV HOME=${MIND_HOME}

ARG MIND_TARBALL=vendor/mind-for-linux-8.0.08.tgz
COPY ${MIND_TARBALL} /tmp/mind.tgz

# 公式手順どおり tar の p オプション必須（cgilib 配下が 777 を要求するため）
RUN set -eux; \
    mkdir -p /tmp/mindx "${MIND_HOME}"; \
    tar xzpf /tmp/mind.tgz -C /tmp/mindx; \
    kerneldir="$(find /tmp/mindx -maxdepth 3 -type d -name kernel | head -n 1)"; \
    if [ -z "${kerneldir}" ]; then \
        echo "ERROR: 配布物の中に kernel/ が見つかりません。" >&2; \
        find /tmp/mindx -maxdepth 2 >&2; \
        exit 1; \
    fi; \
    mv "$(dirname "${kerneldir}")" "${MIND_ROOT}"; \
    rm -rf /tmp/mindx /tmp/mind.tgz

# カーネルのメイク（公式手順: make clean / make all / make install）
#
#   kernel/makefile は OSDEFINE=LINUX が既定、CC = "gcc -m32"、CFLAGS = "-O6 -funsigned-char -ansi"。
#   1998 年からの C ソースで -Wint-conversion / -Wincompatible-pointer-types の警告が出るため、
#   これらを既定でエラーにする gcc 14 以降ではビルドが通らない。
#   bookworm (gcc 12) を固定しているのはそのため（gcc 13 でも通ることは確認済み）。
ARG SKIP_KERNEL_MAKE=0
RUN set -eux; \
    if [ "${SKIP_KERNEL_MAKE}" = "1" ]; then \
        echo "SKIP_KERNEL_MAKE=1: 同梱のビルド済みバイナリをそのまま使います"; \
    else \
        cd "${MIND_ROOT}/kernel"; \
        make clean || true; \
        make all; \
        make install; \
    fi; \
    test -x "${MIND_ROOT}/bin/mind"

# 対話実行のための逐次変換フィルタ mindconv をビルドする。
# iconv(1) は入力をまとめて読むため、改行で終わらないプロンプトが入力待ちの間
# 表示されない（docker/src/mindconv.c 参照）。
COPY docker/src/ /usr/local/src/mind/
RUN gcc -std=c11 -O2 \
        -Wall -Wextra -Werror -Wpedantic -Wconversion -Wsign-conversion -Wformat=2 \
        -D_FORTIFY_SOURCE=2 -fstack-protector-strong -fPIE -pie -Wl,-z,relro,-z,now \
        -o /usr/local/bin/mindconv /usr/local/src/mind/mindconv.c

# ---------------------------------------------------------------------------
# runtime: Mind のコンパイルと実行ができる最小イメージ
#
#   動作確認は `mind-selftest`（= make selftest）でおこなう。
# ---------------------------------------------------------------------------
FROM base AS runtime

COPY --from=builder /opt/mind /opt/mind
COPY --from=builder /usr/local/bin/mindconv /usr/local/bin/mindconv
COPY samples/ ${MIND_HOME}/samples/

WORKDIR /work
CMD ["bash"]
