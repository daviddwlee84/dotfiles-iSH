# 本機 coding agent 實驗

**目前沒有通過驗收、可自動安裝的本機 agent。** Host 建置、container 執行、命令列
模擬器測試，以及 iPhone／iPad 登入後的完整工作流程，是不同驗證層級。
SSH 設定提供測試通道。

## 環境與順序

保留原 filesystem 與備份，先測其 Alpine 3.14 匯入副本；另依
[系統升級指南](system-upgrade.md)測試已校驗的 **x86** Alpine 3.24.1 minirootfs。
不混裝不同分支，也不替換目前可用環境的 feeds。Alpine 3.18 只作歷史 Node 對照。

1. **SSH：**依[SSH 設定](ssh-server.md)操作，測三次完整重開 app、公鑰／密碼登入、
   PTY 輸入與 SFTP。
2. **hako-code：**以固定 C source 建置 32 位元 musl binary，測啟動／TUI，再測雲端
   模型的讀檔、修改與 shell tool；不含本地模型。
3. **Pi，再 Gemini：**先驗證 Node 的檔案 I/O、child process、worker 與 HTTPS。
   滿足整個依賴樹的 Node 版本要求，提供可運作的 32 位元搜尋工具。
   Optional PTY fallback 不代表可以停用 sandbox／隔離。
4. **Herdr：**交叉編譯 Rust 與 Zig/libghostty-vt，依序測啟動、單一 shell pane、
   輸入輸出、resize、socket CLI、detach／attach，最後接入已驗收 agent。
   使用精簡設定，不部署完整 Unix helpers／plugins overlay。

使用可拋棄的測試專案；憑證由使用者在本機設定。報告不包含 tokens、密碼、私人 prompt
或 agent history。通過標準為完成讀檔、指定修改、簡單 shell 命令，以及後續一輪對話。
單純版本檢查不能通過這個驗收關卡。

## 可重跑的檢查

維護者用的 hako recipe 固定 Zig 0.15.2 與 v0.2.3 source commit：

```sh
sh scripts/build-hako.sh --zig /path/to/zig --output /tmp/hako-i586
```

它建立 32 位元靜態產物並印出 hash，不安裝到系統。Zig 下載需先核對官方 checksum。
`--source CHECKOUT` 可重用確切版本且沒有修改的 checkout。

完成可信任的公鑰 SSH 設定後，在 Mac 執行：

```sh
sh scripts/ish-probe.sh --host DEVICE_IP
sh scripts/ish-probe.sh --host DEVICE_IP --case node
sh scripts/ish-probe.sh --host DEVICE_IP --case hako
sh scripts/ish-probe.sh --host DEVICE_IP --case pi
sh scripts/ish-probe.sh --host DEVICE_IP --case gemini
sh scripts/ish-probe.sh --host DEVICE_IP --case herdr
```

Agent cases 只驗證啟動；之後繼續測互動 SSH 工作流程。記錄確切 iSH／iOS／Alpine
版本、source commit、patch、編譯器版本、binary hash、耗時與相關錯誤／opcode。
不略過 checksum 或停用 agent 隔離來製造成功結果。

官方與修補版 iSH 分開記錄。本輪可測修補版的**命令列模擬器**，iOS 簽章與側載另待後續。

## 起始線索

| 候選 | 線索 | 獨立實機工作流程 |
|---|---|---|
| hako-code v0.2.3 | C／libc／pthread 加 curl；使用者確認傳入的 binary 可在 iPad 開啟 | 已回報啟動；登入後工具待驗收 |
| Pi 0.73.1 | Node；須檢查間接版本要求及 ia32 下載器 | 待驗收 |
| Gemini 0.58.0 | Node 與 child-process fallback；仍有間接版本要求 | 待驗收 |
| Herdr v0.8.2 | i586 移植已建置；使用者在 iPad 重現 server spawn error 22 | 卡在 server 啟動 |

2026-09-08 host 結果：hako v0.2.3 分別以 Alpine GCC 10.3、Zig 0.15.2 建置成功，
兩個靜態 binary 都在 iSH 命令列模擬器 commit
`d189985e5cc6d0e70629efeb31505b51a9ce78af` 配合 Alpine 3.24.1 x86 通過 `--version`。
該環境的 `/bin/sh`、`uname` 與讀取 Alpine 版本也通過。這是模擬器 CLI 結果，
不代表 App Store iSH 或登入後的 agent 已驗收。

[hako 回報](https://github.com/ish-app/ish/discussions/2801)、
[Pi 下載器](https://github.com/badlogic/pi-mono/blob/v0.73.1/packages/coding-agent/src/utils/tools-manager.ts)、
[Gemini 依賴](https://github.com/google-gemini/gemini-cli/blob/v0.58.0/packages/core/package.json)、
[Herdr 建置](https://github.com/herdrdev/herdr/blob/v0.8.2/build.rs)。

[Node 20.8.1 workaround](https://github.com/ish-app/ish/issues/2335#issuecomment-2264331674)
有後續 [ada-libs 補充](https://github.com/ish-app/ish/issues/2335#issuecomment-4034378900)，
但不滿足這次調查之 agent 使用的 Undici 7.x 要求（Node 20.18.1）。
[Fork 回報](https://github.com/ish-app/ish/issues/2604#issuecomment-3448630596)
表示新增 `cvtdq2pd` 後 Node 能執行，沒有證明完整 Gemini session 成功。
[Tokio 問題](https://github.com/ish-app/ish/issues/2447)同時出現在 i586 與 i686 回報，
只改 target 並不足夠。

只有具可重現安裝產物且完成實機驗收的工具，才接入 `--with hako,pi,gemini,herdr`；
此前安裝器會拒絕在 iSH 安裝。未來資產須一起鎖定版本、URL、架構、大小與 SHA-256；
已安裝且可運作的版本維持 install-only。

補充 CLI 結果：hako 能顯示首次啟動的 provider 選單，尚未完成登入後的對話。
Node 24.18.1 版本檢查通過，但這次 CLI 建置執行最小 JavaScript 失敗：release
出現 SIGSEGV，debug 逾時；`cvtdq2pd` patch 未解決此案例。Pi／Gemini 仍卡在
runtime 驗收。Herdr 的 libghostty-vt 已完成 i586 交叉編譯，Rust 主程式與 runtime
須分別驗證。

Herdr 最終建置結果：使用 Rust 自帶 linker 與 self-contained libraries 成功連結
i586 執行檔，兩個 CLI guest 版本都通過 `--version`。啟動 named session 時失敗：
`failed to spawn herdr server: Invalid argument (os error 22)`。
Rust 1.96.1 的 Linux `pre_exec` 路徑需要 `SOCK_SEQPACKET`，這次調查的 iSH 尚未支援。
Session／PTY 與實機驗收未通過，因此不開啟 Herdr installer。

## 使用者回報的 iPad 結果（2026-09-08）

已成功用 `mount -t real "$(cat /proc/ish/documents)" /mnt/finder` 讀取 Finder
傳入的檔案。使用者回報傳入的 hako binary 可正常開啟；尚未回報登入、模型對話與
讀檔／修改／shell tools 通過。傳入的 Herdr binary 則出現
`herdr: failed to spawn herdr server: Invalid argument (os error 22)`，
與上述 CLI 症狀一致，未建立 session。

SSH 設定從 iSH Alpine 3.14 snapshot 安裝 OpenRC 0.43.3-r3 後，停在
`SSH prerequisite missing: /sbin/rc-status`。安裝器和 fixture 的路徑都寫錯：
Alpine 套件實際安裝的是 `/bin/rc-status`。修正後使用者在實機重跑成功：
Ed25519 host key 已生成、config 驗證通過，`dotfiles-sshd` 已加入 default runlevel，
程式提示完整重開 app。後續使用者確認完整重開一次後，可用密碼登入
`ssh localhost -p 22000`。使用者接著確認 Mac 密碼登入成功，維護者也直接用
公鑰登入並執行 shell 命令，辨識為 iSH 1.3.2（494）、Alpine 3.14.3、i686。
部分後續連線在收到 SSH banner 前逾時；使用者重開 iSH 後，直連測試繼續進行。
多次重開及 iPadOS build 仍待驗收／記錄。

[Finder 掛載](finder-files.md) 現在是獨立且預設開啟的 setup 選項，使用每次重讀
路徑的 OpenRC helper。安裝、掛載、default runlevel 註冊及明確 service start
都已在 iPad 通過。一次完整重開 App、沒有手動掛載後，也通過遠端服務／掛載與
binary 雜湊檢查；其餘重複次數尚未記錄。

hako 的[初始化順序](https://github.com/mithraeums/hako-code/blob/452291112f8a639aac5059070fb933e2d5bbb28b/hako.c#L11218)
在解析 `--version` 前已經讀寫使用者狀態。因此版本 probe 使用空的暫存 HOME／project，
並清除認證環境，以驗證啟動而不觸碰使用者 hako 設定或替模型登入。

## 直連 runtime 結果（2026-09-08）

| 檢查 | 實機結果 |
|---|---|
| SSH 公鑰認證與遠端命令 | 通過 |
| SSH PTY 輸入輸出與尺寸設定 | 通過 |
| SSH 壓縮包／binary 傳輸與 SHA-256 驗證 | 通過 |
| Legacy SCP（`scp -O`）上傳／下載 | 逐位元組比對通過 |
| 內建與外部 SFTP | 失敗；缺少啟動保護要求的 `PR_SET_DUMPABLE` 支援 |
| Finder helper 安裝與 OpenRC start | 通過，包含一次完整 App 重開且沒有手動掛載 |
| 傳入的 hako／Herdr 雜湊 | 符合建置產物 |
| hako v0.2.3 隔離版號 probe | 通過；登入後工作流程待驗收 |
| Rust 一般子程序 | 通過 |
| Rust `pre_exec`／SEQPACKET | Error 22，與 Herdr 阻礙一致 |
| 帶 flags 的 raw STREAM socketpair | Error 93；普通 STREAM 可用 |

SFTP 失敗與認證前的 banner 停頓是不同問題，見 [SSH 傳檔](ssh-server.md)。
Rust 最小診斷以 Rust 1.96.1 從 repo 原始碼重新建置，傳入後驗證雜湊並限時執行。
未在裝置安裝修補版 iSH kernel 或替換系統 libraries。
