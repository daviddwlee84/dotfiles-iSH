# 本機 coding agent 實驗

**目前沒有通過驗收、可自動安裝的本機 agent。** Host 建置、container 執行、命令列
模擬器測試，以及 iPhone／iPad 登入後的完整工作流程，是不同驗證層級。
SSH 設定提供測試通道。

2026-09-08 更新：程序／休眠相容版 Rust 標準庫已在 **iPad 原版 App 通過 18/18 項**。
重新建置的 Herdr 已通過 CLI server、pane、shell I/O、detach 及相同 pane reattach。
CLI host resize 傳遞與 iPad 原版 App 的 Herdr 工作流程仍待驗收。

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
| Herdr v0.8.2 | 相容 std 通過 18/18 項實機測試；重建版 CLI session 支援 pane I/O 與 reattach | iPad 原版 App session 與 resize 待驗收 |

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

Herdr 初期建置結果：使用 Rust 自帶 linker 與 self-contained libraries 成功連結
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
| 原版 Rust `pre_exec`／SEQPACKET | Error 22，與原本的 Herdr 阻礙一致 |
| 程序／休眠相容版 Rust std | 原版 App 通過 18/18 項；完整 Herdr session 仍待驗收 |
| 帶 flags 的 raw STREAM socketpair | Error 93；普通 STREAM 可用 |

SFTP 失敗與認證前的 banner 停頓是不同問題，見 [SSH 傳檔](ssh-server.md)。
Rust 最小診斷以 Rust 1.96.1 從 repo 原始碼重新建置，傳入後驗證雜湊並限時執行。
未在裝置安裝修補版 iSH kernel 或替換系統 libraries。

## Chezmoi 管理器檢查

裝置目前記錄 `manager=sh`，也沒有安裝 chezmoi 執行檔。這解釋了
`-ash: chezmoi: not found`：sh 部署及 SSH／Finder 準備流程不會安裝它，
重新載入 `.profile` 也無法補上缺少的執行檔。

鎖定的 chezmoi v2.72.1 i386 候選檔在暫存目錄通過 archive／binary SHA-256
檢查。版號命令正常結束，但 source-layout 模板印出 `supported` 後未結束。
裝置上的 15 秒 SIGKILL wrapper 未能在 Mac 的 120 秒期限前返回；其後 SSH
拒絕連線。使用者回報 App 閃退並重開；之後 SSH 恢復，manager=sh 與
SSH／Finder 選項都保留。閃退的確切機制尚未確認。

CLI 對照也失敗：七項以模擬器 SIGSEGV 結束，一項出現 Go runtime 錯誤後逾時。
將 Go 限制為單處理器或停用非同步搶佔，都未得到正常結束的程序。候選檔未安裝，
未持久化執行參數，保留原本可用的 sh 管理方式。結果見
`experiments/chezmoi/results.json` 與
[逾時 pitfall](https://github.com/daviddwlee84/dotfiles-iSH/blob/main/pitfalls/chezmoi-probe-waits-past-timeout.md)。
鎖定候選檔能完整通過檢查後，才適合由完整 setup 遷移；只有印出結果不足以通過。

舊版 package 也不是安全 fallback。官方 i386 版 2.9.1、2.20.0、2.40.0
分別出現 signal-stack／GC 錯誤、逾時或 SIGSEGV。Alpine 3.14 內建的
2.0.16-r3 在限制單處理器或停用非同步搶佔時，偶爾能完成版號命令；但重複執行
version、template、help 仍會崩潰，而且它早於 2.9.1 才加入的
`.chezmoi.workingTree` 能力。

另以 iSH upstream 尚未合併的 SIGURG 與 futex-bitset 修正
（[PR 2744](https://github.com/ish-app/ish/pull/2744)、
[PR 2775](https://github.com/ish-app/ish/pull/2775)）重建隔離 CLI，2.72.1 與
Alpine 2.0.16 仍不穩定。因此 `apk add chezmoi` 只能證明檔案可安裝，不能證明
這個 App 上的 manager 可用。維持 `manager=sh`；完整矩陣見
`experiments/chezmoi/version-matrix.json`。

## iSH 專用 Rust 標準庫實驗

獨立建置的 Rust 1.96.1 已涵蓋子程序啟動與相對休眠的相容性缺口。擴充版在
**iPad 原版 App 通過 18/18 項**（iSH 1.3.2（494）、Alpine 3.14.3），包含
信號中斷休眠與並行建立子程序；每項期限 30 秒，SSH exit 0。相同的 macOS
編譯器產物也在 CLI 通過全部 18 項。實機對照組仍顯示原版 std 的 `pre_exec`
回報 EINVAL、相對休眠出現 `Bad system call`。先前只修改程序通道的 14 項
結果保留為獨立歷史版本。完整 Herdr session 仍待驗收；詳見
`experiments/rust-std/results.json`。

`experiments/patches/` 內有兩個 patch：

- `rust-1.96.1-ish-process-pipe.patch` 只在 `ish_compat` 下選擇原有的
  CLOEXEC pipe 錯誤通道，保留全部 child callbacks。明確要求 pidfd 時回報
  `Unsupported`，這是刻意比 upstream 的建議性 pidfd 選項更嚴格的行為。
- `rust-1.96.1-ish-thread-sleep.patch` 因 iSH 缺少 `clock_nanosleep`，選用
  原有的相對 `nanosleep` fallback。測試允許超時休眠，不聲稱 iSH 已完整實作
  被信號中斷時的 nanosleep 語意。

使用獨立的 Rust 1.96.1 sysroot 與相符且已校驗的 rust-src，不替換 host toolchain
或裝置 libraries。該 component 的 SHA-256 為
`b343b6553bc772225f6a2b5be5055017f29794dcf4e08020366b27a0a40fc1c2`。
從 source root（`lib/rustlib/src/rust`）套用兩個 patch。iSH cfg 限定 32 位元
x86 Linux musl，其他建置不啟用相容分支。維護者 container 以 Rust 自帶 linker
配合原有的 Herdr i586 移植建置：

```sh
export PATH=/toolchain/bin:$PATH
export RUSTC_BOOTSTRAP=1
export RUSTFLAGS='--cfg ish_compat --check-cfg=cfg(ish_compat) -C linker-flavor=ld.lld -C linker=/toolchain/lib/rustlib/aarch64-unknown-linux-gnu/bin/rust-lld -C link-self-contained=yes'
cargo build -Z build-std=std,panic_unwind --locked --offline --release \
  --target-dir /target --target i586-unknown-linux-musl --bin herdr -j1
```

`/target` 必須是 host 預先建立並掛入的全新空目錄。修改 rust-src 後重用舊
Cargo target 曾連到舊 std，即使 source 已更新；每個 std patch 版本都重新建置。
上例保留 release 設定，採單工建置以減少 Herdr 大型編譯的記憶體壓力。

macOS 維護者也可用獨立的 Rust 1.96.1 `aarch64-apple-darwin` compiler／host std，
搭配相同 i586 target 與 source patches。將上例 Linux-host linker 改為該工具鏈
自帶的 `aarch64-apple-darwin/bin/rust-lld`，並使用 macOS Zig 0.15.2，即可避開
小型 Docker VM 的記憶體上限；輸出仍是 Linux ELF32 執行檔。Component 來源與
runtime 結果記於 `experiments/rust-std/results.json`。

先前 macOS 建置遇到 Zig 0.15.2 build runner 無法連結系統符號，因此在 i586
移植之後套用 `herdr-i586-prebuilt-ghostty.patch`，加入明確且驗證
target／大小／SHA-256 的 `HERDR_ISH_GHOSTTY_ARCHIVE`。最初 1,224,644-byte
archive（`2420a175…e9196`）僅保留來源紀錄；它的 i386 結構值傳遞 ABI 有誤，
不可安裝。目前 guard 只接受另一個 iSH 相容 archive：1,237,632 bytes，SHA-256
`a8c7123d6e8e6df0cab93cd54f21d060953fa628b0474b74a510463167ea2222`。
預設建置仍呼叫 Zig；archive path 只能由維護者明確指定。

`RUSTC_BOOTSTRAP` 只為這個實驗啟用不穩定建置功能，不是 upstream 支援的替代
工具鏈。Cargo 的 [build-std 文件](https://doc.rust-lang.org/cargo/reference/unstable.html#build-std)
說明此功能，正常要求 nightly。Herdr 原始 lockfile、32 位元 FFI assertions、
vendored PTY 初始化與 scalar libghostty 建置都保留，未開啟自動安裝。

`experiments/rust-process-compat-probe.rs` 提供 `--list` 與 `--case NAME`。
以重建後的 std 加上 `--cfg ish_pidfd_probe`，可加入兩項專用 pidfd 拒絕測試；
每項以外部 30 秒強制終止期限執行。原版 std 的 pidfd 契約不同，對照建置不加此 cfg。

## Herdr ABI 與 PTY 檢查

最小 C／Zig 測試確認 Zig 0.15.2 會錯誤處理五個 i386 結構值參數，即使
memory-layout assertions 都相符。C wrapper 保留公開原型，並在 Linux 通過全部
127 項 assertions。只開啟 Ghostty 原有 libc allocator 時，iSH 的五組 terminal
測試會逾時。`ghostty-vt-libc-option.patch` 新增僅限 x86 Linux musl 的 iSH flag，
讓 terminal page backing 也改用 page-aligned libc allocation 並明確清零；這個
archive 在 Linux binfmt 與 iSH CLI 都通過 127 項。詳見
`experiments/zig-i386-abi/` 與 `experiments/ghostty-allocator/results.json`。

Herdr 另需 local socket 相容路徑：iSH 使用 Rust UnixListener／UnixStream，且把
不支援或無效的 socket receive-timeout 設定視為 best-effort；其他 build 保留
`interprocess`。最終 CLI binary（`3ede5a4a…d9809`）可啟動 server 與 pane、完成
client handshake、通過 shell 輸入輸出、detach，並 reattach 到同一 pane 與 shell
PID。Host PTY 從 44x132 改為 55x172 後，pane 仍為 43x105，resize 未傳遞；owned
server 仍正常停止。因 SSH 在暫存上傳前逾時，iPad 原版 App 測試待續，沒有安裝。
詳見 `experiments/herdr/results.json`。

另以實際 vendored `portable-pty` 與相符的相容 std，在全新的 Alpine 3.14.10
CLI guest 執行 `experiments/portable-pty-probe.rs`。預設模式收到正確輸出與
terminal size 後，阻塞等待 EOF，於 30 秒逾時；`--wait-after-output` 改在收到
已知完成標記後 wait／回收子程序，24 ms 通過。未修改 library 初始化，PTY
開啟、spawn、輸出與等待子程序均通過。Herdr 使用非阻塞 PTY 讀取，因此這個
阻塞 EOF 限制無法解釋啟動失敗；最後輸出是否完整讀完及 pane 清理仍須驗收。

## 並行的 SEQPACKET 核心原型

`experiments/patches/ish-seqpacket.patch` 實作記憶體內的 AF_UNIX 訊息傳輸，
而不是將 Darwin 不支援的 socket type 直接轉送。以 iSH
`d189985e5cc6d0e70629efeb31505b51a9ce78af` 為基底，先套用既有的
`ish-socketpair-host-args.patch`，再套新 patch。包含 socketpair、listener、
訊息邊界、EOF／shutdown、nonblocking readiness、timeout，以及一般檔案／pipe
描述符傳遞。C probe 與機器可讀結果放在 `experiments/seqpacket/`。

原生 Linux 對照通過 46/46 項，修補後的 macOS CLI 通過 45/46。
未通過的是 SCM_RIGHTS 傳遞 socket 描述符；在完成 Unix socket 引用循環回收前，
此功能明確回傳 EOPNOTSUPP。原版 Rust std 的程序測試可在此核心通過，證明它能
獨立解除最初的 spawn 依賴。該次使用原版 std 的 Herdr 隨後遇到缺少
`clock_nanosleep`；上文的 std 休眠 patch 已涵蓋這個獨立缺口，無須修改裝置核心。

這**尚非完整 Linux 支援**。共用描述符的並行 close 生命週期、完整 autobind／
credentials 規則、其他 options／ioctl 與 edge-triggered epoll 行為仍待處理。
這些有限測試的通過不代表上述路徑已驗證。雖已加入 Xcode source entries，尚未
執行 Xcode 建置、簽署、側載或替換 iPad 核心。核心原型維持在 CLI 實驗環境；
標準庫實驗則可在原版 App 執行。
