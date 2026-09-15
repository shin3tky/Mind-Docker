/*
 * mindconv - 文字コードを変換しながら、届いたぶんを即座に書き出すフィルタ
 *
 *   使い方: mindconv <変換元> <変換先>
 *   例:     mindconv EUC-JP UTF-8
 *
 * なぜ iconv(1) ではないのか:
 *   iconv(1) は入力をまとめて読んでから変換するため、改行で終わらないプロンプト
 *   （Mind の「お名前を入力してください＞」など）が入力待ちの間 表示されない。
 *   対話実行を成立させるために、read/write をそのまま使って逐次変換する。
 *
 * 仕様:
 *   ・read(2) の境界で多バイト文字が切れた場合は、次の read まで持ち越す
 *   ・変換できないバイトは読み飛ばす（iconv -c 相当）
 *   ・入力の末尾が中途半端な多バイト文字で終わっていた場合、その数バイトは捨てる
 *   ・下流が閉じた場合は SIGPIPE で終了する（フィルタとして通常の挙動）
 *
 * 終了コード:
 *   0 正常終了 / 1 入出力または変換の失敗 / 2 引数・変換表の問題
 */

#include <errno.h>
#include <iconv.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* 入力: 1 文字あたり最大 4 バイト程度なので 4KiB あれば境界持ち越しは数バイトで済む */
#define INBUF  4096
/* 出力: EUC-JP -> UTF-8 で最大 1.5 倍。E2BIG も処理するので余裕を見た値でよい */
#define OUTBUF 16384

#define EXIT_OK    0
#define EXIT_IO    1
#define EXIT_USAGE 2

/* fd が読み書き可能になるまで待つ。EAGAIN（非ブロッキング fd）対策。 */
static int wait_fd(int fd, short events)
{
    struct pollfd pfd;

    pfd.fd = fd;
    pfd.events = events;
    pfd.revents = 0;

    for (;;) {
        int r = poll(&pfd, 1, -1);
        if (r >= 0) {
            return 0;
        }
        if (errno != EINTR) {
            return -1;
        }
    }
}

/* n バイトを確実に書き切る。成功 0 / 失敗 -1 */
static int write_all(int fd, const char *p, size_t n)
{
    while (n > 0) {
        ssize_t w = write(fd, p, n);

        if (w > 0) {
            p += (size_t)w;
            n -= (size_t)w;
            continue;
        }
        if (w == 0) {
            /* 通常は起きない。無限ループを避けるため失敗扱いにする */
            return -1;
        }
        if (errno == EINTR) {
            continue;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if (wait_fd(fd, POLLOUT) < 0) {
                return -1;
            }
            continue;
        }
        return -1;
    }
    return 0;
}

/* 最大 n バイト読む。読めたバイト数 / 0 = EOF / -1 = 失敗 */
static ssize_t read_some(int fd, char *p, size_t n)
{
    for (;;) {
        ssize_t r = read(fd, p, n);

        if (r >= 0) {
            return r;
        }
        if (errno == EINTR) {
            continue;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            if (wait_fd(fd, POLLIN) < 0) {
                return -1;
            }
            continue;
        }
        return -1;
    }
}

/*
 * 出力エラーの報告。下流が閉じただけ（EPIPE）のときは黙る。
 * 端末に流れる経路なので、終了時に余計な文字を出さない。
 */
static void report_write_error(const char *prog)
{
    if (errno != EPIPE) {
        fprintf(stderr, "%s: 出力を書けません: %s\n", prog, strerror(errno));
    }
}

int main(int argc, char **argv)
{
    const char *prog = (argc > 0 && argv[0] != NULL) ? argv[0] : "mindconv";

    if (argc != 3) {
        fprintf(stderr, "使い方: %s <変換元の文字コード> <変換先の文字コード>\n", prog);
        return EXIT_USAGE;
    }

    iconv_t cd = iconv_open(argv[2], argv[1]);
    if (cd == (iconv_t)-1) {
        fprintf(stderr, "%s: %s から %s への変換を開けません\n", prog, argv[1], argv[2]);
        return EXIT_USAGE;
    }

    char in[INBUF];
    char out[OUTBUF];
    size_t have = 0;     /* in に溜まっている未変換バイト数 */
    int status = EXIT_OK;

    for (;;) {
        ssize_t n = read_some(STDIN_FILENO, in + have, sizeof(in) - have);
        if (n < 0) {
            fprintf(stderr, "%s: 入力を読めません: %s\n", prog, strerror(errno));
            status = EXIT_IO;
            break;
        }
        if (n == 0) {
            break;       /* EOF */
        }
        have += (size_t)n;

        char *ip = in;
        size_t ileft = have;
        int done = 0;

        while (!done && ileft > 0) {
            char *op = out;
            size_t oleft = sizeof(out);
            size_t r = iconv(cd, &ip, &ileft, &op, &oleft);
            int err = errno;

            if (op > out && write_all(STDOUT_FILENO, out, (size_t)(op - out)) < 0) {
                report_write_error(prog);
                status = EXIT_IO;
                done = 1;
                break;
            }
            if (r != (size_t)-1) {
                break;                      /* すべて変換できた */
            }

            switch (err) {
            case E2BIG:
                break;                      /* 出力側が足りないだけ: もう一周 */
            case EINVAL:
                done = 1;                   /* 途中で切れた文字: 次の read を待つ */
                break;
            case EILSEQ:
                ip++;                       /* 変換できないバイトは読み飛ばす */
                ileft--;
                break;
            default:
                fprintf(stderr, "%s: 変換に失敗しました: %s\n", prog, strerror(err));
                status = EXIT_IO;
                done = 1;
                break;
            }
        }

        if (status != EXIT_OK) {
            break;
        }

        memmove(in, ip, ileft);
        have = ileft;

        /*
         * 1 文字が INBUF を超えることはないので、ここで入力バッファが埋まったままに
         * なることは無い。万一そうなったら変換表が想定外なので、進めずに打ち切る。
         */
        if (have == sizeof(in)) {
            fprintf(stderr, "%s: 変換が進みません（入力バッファが埋まりました）\n", prog);
            status = EXIT_IO;
            break;
        }
    }

    if (status == EXIT_OK) {
        /* シフト状態を持つ符号化のための後始末 */
        char *op = out;
        size_t oleft = sizeof(out);

        if (iconv(cd, NULL, NULL, &op, &oleft) == (size_t)-1 && errno != EILSEQ) {
            /* 出力バッファは十分大きいので通常ここには来ない */
            status = EXIT_IO;
        }
        if (op > out && write_all(STDOUT_FILENO, out, (size_t)(op - out)) < 0) {
            report_write_error(prog);
            status = EXIT_IO;
        }
    }

    iconv_close(cd);
    return status;
}
