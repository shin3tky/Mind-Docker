# 日本語プログラミング言語 Mind を Docker で動かす
#
#   make doctor    … この環境で 32bit x86 バイナリが動くかを先に確認する
#   make check     … 配布物 (vendor/*.tgz) が置かれているか確認
#   make build     … イメージをビルド
#   make selftest  … ビルドしたイメージで hello, world まで一通り動くか確認する
#   make hello     … UTF-8 のまま samples/hello.src をコンパイルして実行（ラッパー経由）
#   make greet     … 標準入力も UTF-8 で扱えることの確認（対話実行）
#   make hello-raw … 公式手順そのまま（EUC-JP に変換して素の mind を叩く）
#   make inspect   … 配布物の中身（同梱 .src / bin / lib）を調べる
#   make shell     … コンテナのシェルに入る
#   make clean     … コンパイル生成物を削除
#   make distclean … イメージごと削除

COMPOSE  ?= docker compose
DOCKER   ?= docker
TARBALL  ?= vendor/mind-for-linux-8.0.08.tgz
PLATFORM ?= linux/amd64

.PHONY: help doctor check build selftest hello greet hello-raw inspect shell clean distclean

help:
	@grep -E '^#   ' $(MAKEFILE_LIST) | sed 's/^#   //'

# ld-linux.so.2 自身が 32bit ELF なので、これが動けば 32bit x86 を実行できる環境。
doctor:
	@$(DOCKER) build --platform $(PLATFORM) --build-arg BASE_PLATFORM=$(PLATFORM) --target base -t mind-docker-base . >/dev/null
	@echo "--- 32bit x86 実行テスト ---"
	@$(DOCKER) run --rm --platform $(PLATFORM) mind-docker-base /lib/ld-linux.so.2 --version \
	  && echo "OK: 32bit x86 バイナリを実行できます" \
	  || { echo "NG: 32bit x86 バイナリを実行できません。README のトラブルシュートを参照してください。"; exit 1; }

check:
	@test -f $(TARBALL) || { \
	  echo "ERROR: $(TARBALL) がありません。vendor/README.md の手順で配置してください。"; \
	  exit 1; }
	@test -f $(TARBALL).sha256 || { \
	  echo "ERROR: $(TARBALL).sha256 がありません。vendor/README.md の手順で配置してください。"; \
	  exit 1; }
	@cd $(dir $(TARBALL)) && shasum -a 256 -c $(notdir $(TARBALL)).sha256

build: check
	$(COMPOSE) build mind

selftest: build
	@$(COMPOSE) run --rm -T mind mind-selftest

hello: build
	@$(COMPOSE) run --rm mind bash -c '\
	  mkdir -p /tmp/h && cp /work/samples/hello.src /tmp/h/ && cd /tmp/h && \
	  mindc hello.src file && mindrun ./hello'

greet: build
	@$(COMPOSE) run --rm mind bash -c '\
	  mkdir -p /tmp/g && cp /work/samples/greet.src /tmp/g/ && cd /tmp/g && \
	  mindc greet.src file && mindrun ./greet'

hello-raw: build
	@$(COMPOSE) run --rm mind bash -c '\
	  mkdir -p /tmp/hr && iconv -f UTF-8 -t EUC-JP /work/samples/hello.src > /tmp/hr/hello.src && \
	  cd /tmp/hr && mind hello file && ./hello | iconv -f EUC-JP -t UTF-8'

inspect: build
	@$(COMPOSE) run --rm -T mind mind-inspect

shell: build
	$(COMPOSE) run --rm mind bash

clean:
	@find ./samples -name '.mindbuild' -type d -prune -exec rm -rf {} + 2>/dev/null || true
	@find ./samples -type f \( -name '*.mco' -o -name '*.sym' -o -name '*.his' -o -name '*.inf' \) -delete 2>/dev/null || true
	@echo "cleaned"

distclean: clean
	-$(COMPOSE) down --rmi local --remove-orphans
	-$(DOCKER) rmi mind-docker-base 2>/dev/null || true
