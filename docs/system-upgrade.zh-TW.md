# iSH 升級與 chezmoi 檢查卡住

## 這次實機結果

2026-09-07 的回報環境是 App Store iSH 1.3.2、固定的
`v3.14-2023-05-19` 套件 snapshot。Bash 5.1.16 和 Starship 0.54.0 安裝成功；
chezmoi 2.72.1 i386 檢查等待超過五分鐘，直到 Ctrl+C 才結束。
chezmoi 沒有安裝，家目錄設定也還沒進入 apply 階段。

舊 `timeout 15` 只送 TERM，不能保證程式退出。現在每個唯讀 version／template
probe 都改用 `timeout -s KILL 15`，相容原有 BusyBox 1.33（它沒有 GNU timeout 的 `-k`）。
下載、SHA-256 校驗、解壓、版本和 source-layout 檢查也各自顯示進度。
每個執行檢查各有 15 秒送出終止訊號的期限；下載可用到 180 秒，hash／解壓是另外的階段。
如果整個模擬器 deadlock，timeout 本身也可能停止執行；userspace watchdog 無法保證救回整個 app。

這修正的是安裝器的逾時行為，尚未證明修復了 Go runtime 問題。
[iSH 的 Go 回報](https://github.com/ish-app/ish/issues/1230) 有卡住及依版本／build
而不同的 workaround；架構符合 i386 不等於執行相容。
更新 Alpine 也不會更新 iSH 的 syscall／CPU 模擬器。

## 先使用已裝好的 shell 工具

現有 source snapshot 可以離線套用設定，不重試 chezmoi 或安裝套件：

```sh
sh ~/.local/share/dotfiles-iSH/bootstrap.sh --manager sh --config-only --with starship
. ~/.profile
bash
```

這是明確暫用 sh；repo 預設仍維持 chezmoi。有可用 chezmoi 後，執行預設 bootstrap
即可遷移到 Git source，之後日常 `chezmoi update`。

要再次受控測試，可重新下載目前的 bootstrap 再執行；不要在 version／template
檢查一直等五分鐘。Upstream 曾提出 `GOMAXPROCS=1 sh bootstrap.sh --with starship`
的實驗方向，但不是保證修復，也有回報需要不同的 binary linking 方式。
本 repo 不自動套用全域 runtime workaround。即使這樣能啟動，日常 chezmoi
apply／update 仍須在相同環境下分別驗收。

## 可以升級哪些部分？

| 層次 | 更新方式 | 更新內容 |
|---|---|---|
| iSH app | App Store／可取得的官方 TestFlight build | CPU／syscall 模擬與 iOS 整合 |
| Alpine userspace | 同分支 apk 更新，或另做 release／filesystem 遷移 | musl、BusyBox、Git 等套件 |
| 個人 dotfiles | 安裝完成後 chezmoi update | 來源、設定、缺少的已選裝套件 |

[Alpine release 表](https://alpinelinux.org/releases/) 列出 3.14 已於 2023-05-01 結束支援。
2026-09-07 查得目前 stable 為 3.24.1；Alpine 仍支援該分支，不代表 iSH 1.3.2 已驗收。
[iSH 相容性筆記](https://github.com/ish-app/ish/wiki/iSH-Alpine-Release-Issues)
列有 3.19／3.20 的 sudo、procps、coreutils、Vim 等問題。它以前建議的 3.18
也已 EOL，不能當成現在的安全更新建議。

`apk update` 只是更新 index；`apk upgrade` 只升級已設定 feed 能提供的套件。
你的 iSH feed 是有日期的 snapshot，所以單靠這兩個指令不會從 3.14 跨到新版。
iSH 的[套件來源說明](https://ish.app/blog/default-repository-update) 解釋了固定版本的原因。

## 建議：先建立獨立 filesystem

1. 在 iSH 齒輪選單進入 **Filesystems**，選目前的 filesystem 並 export 到 Files 備份；
   同時保留原本的 filesystem 項目。
2. 從 [Alpine downloads](https://alpinelinux.org/downloads/) 選 **Mini Root Filesystem → x86**。
   目前 stable 在這裡是測試候選，不是保證相容的工作環境替代品。
3. 選 **Filesystems → Import**，匯入 archive、取不同名稱，再選
   **Boot From This Filesystem**，重新開啟 iSH。
4. 先檢查 `cat /etc/alpine-release`、`uname -m`、套件下載、Git、Bash 和 Starship，
   再搬個人檔案。在這個測試 filesystem 嘗試原生 `apk add chezmoi`，
   接著 `timeout -s KILL 15 chezmoi --version`，再測真正 init／diff／apply／update。
   只有版本檢查成功還不夠。
5. 新環境開不起來或必要工具失敗時，回到 Filesystems 選原環境再開啟。
   新環境驗收完成前，保留原本可用的 filesystem。

流程依據 iSH 的[替代 filesystem 指南](https://github.com/ish-app/ish/wiki/Install-%26-Activate-Alternate-Filesystems)。
該指南也提到部分 image 因 init／login 相容性而無法開機。
dotfiles bootstrap 不會執行 filesystem 或套件來源遷移。

## 原地升級 release

[iSH 升級指南](https://github.com/ish-app/ish/wiki/Upgrading-to-a-new-release)
也提供原地升級方向：備份、視情況停止服務、選擇同一版本的官方 Alpine main／community
feed、upgrade／fix 套件，再重新開啟環境。建議先在目前 filesystem 的匯入副本操作。
沒有一個簡單的套件 downgrade 可以把舊環境完整還原。

[套件來源指南](https://github.com/ish-app/ish/wiki/Using-Alpine-Linux-repositories)
另說明 iSH 自動覆寫 feeds 和 `/ish` metadata 的機制。修改 feeds 前先理解該行為；
本 repo 不會刪除 `/ish`、混用 release 分支或代你選擇新的系統版本。
