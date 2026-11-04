# BTRON3 OS 仕様編 3.10 TCP/IP マネージャ

> 親Issue: [#42](https://github.com/kitanou/chokanbun/issues/42) / 基準: os_spec/shell/tcpip.html
> 実装: `user/btron/tcpip.mkn`。試験: `描試` の `描試二十八`（9 項目）。

## 概要

ネットワーク装置とスタックが無いので、**行程内のループバックだけ**のソケット層（127.x.y.z と 0.0.0.0 のみ。他の宛先は `EX_HOSTUNREACH`）。28 関数すべてが呼べ、同じ行程のソケット同士で `SOCK_STREAM`（listen / connect / accept）と `SOCK_DGRAM`（bind / sendto / recvfrom）が通る。

## 関数（28/28）

`so_start` `so_finish` `so_socket` `so_bind` `so_listen` `so_accept` `so_connect` `so_close` `so_shutdown` `so_read` `so_write` `so_recv` `so_recvfrom` `so_recvmsg` `so_send` `so_sendto` `so_sendmsg` `so_select` `so_fcntl` `so_ioctl` `so_getsockopt` `so_setsockopt` `so_getsockname` `so_getpeername` `so_gethostbyname` `so_gethostbyaddr` `so_gethostname` `so_sethostname`

誤りコード（原文の `((-n) << 16)`、n = 401〜429）は `tcpip.mkn` で定義した。`EX_FAULT` は `er.mkn` に無いので 0xFFFFFFFFFFFE0022 とした。

## 選んだ設計

- **待たない**: 待つ処理を持たないので、待つはずの `accept`・読み・書きは常に `O_NDELAY` として働き、待つ場面で `EX_WOULDBLOCK` を返す。`O_NDELAY` は保持するが挙動は変わらない。
- ソケット表は行程ごと（0x407F4000、16 個）。行程をまたぐ接続はできない。
- `SOCK_STREAM` は `connect` の時点で `listen` 側の待ち行列（backlog 最大 8）に接続済みソケットを積む。データは 1 本 1024 B の環。`shutdown` と `close` は相手に終わり（読みが 0）を伝え、`close` 後の相手への送信は `EX_CONNABORTED`。
- `SOCK_DGRAM` は bind したポートへ送る。受信待ち行列は 1024 B で `[長さ][送り手のポート][本体]`、1 通 500 B まで（超えると `EX_MSGSIZE`）。宛先ポートが無ければ捨てる（UDP と同じ）。`sendmsg`/`recvmsg` は 1 通にまとめる／分ける。
- `so_gethostbyname` / `so_gethostbyaddr` は `localhost` と自分のホスト名（`so_sethostname`、31 文字まで）、127.x.y.z だけ解決する。
- 値が原文に無い `FIONREAD` は BSD の 0x4004667F。`SIOCATMARK` は常に 0。`SO_KEEPALIVE` は原文どおり未対応（`EX_NOPROTOOPT`）。

## 未対応

実ネットワーク、`SOCK_RAW`・ICMP、MSG_OOB、複数行程の間の接続、`SO_LINGER` などの残りのソケットオプション、`so_select` の待ち時間（常に即時）。
