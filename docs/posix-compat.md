# POSIX互換方針（草案）

## 目標
独自機械漢文APIを第一級とし、POSIX互換はユーザーランドとsyscallの境界で段階的に提供する。

## 段階
1. ファイルディスクリプタ、read/write/open/close相当
2. 行程、exec、wait、pipe相当
3. fork、シグナル、端末制御
4. POSIX適合性試験（適合を主張する前に範囲と版を明記）

## 注意
POSIX準拠とPOSIX風APIは異なる。初期段階でPOSIX準拠を宣言しない。

`fork` 相当（`分行程`、漢令 23）は実装済み（全複製、copy-on-write なし）。シグナルと端末制御は未着手。

## 設計判断
[design-process-exec.md](design-process-exec.md) §13（Issue #104）に、BTRON3 との対応範囲・`pipe`/`exec`/`wait`/`fork` の方針と段階別の試験を記録した。
