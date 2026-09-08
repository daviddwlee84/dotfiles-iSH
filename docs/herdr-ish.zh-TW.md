# iSH 上的 Herdr

Herdr 已有實驗性的 iSH／i386 相容建置。經核對的 v0.8.2 binary 已安裝到一台
iPad 原版 App 的 `~/.local/bin/herdr`，並透過 SSH 確認確切版本、大小與 SHA-256。
這證明該裝置可安裝及啟動。Resize、長時間 session 與真正 coding-agent 工作流程
仍須驗收，之後才會向所有使用者開放 bootstrap 安裝。

此 iSH build 由本 repo 維護，因為 upstream Herdr release 目前只提供 64 位元
Linux 資產，而 iSH 執行 32 位元 x86 userspace。相容建置另需限制範圍的 Rust
標準庫、local socket、Ghostty ABI／allocator patches。下一個產物鎖定 upstream
[Herdr v0.9.0](https://github.com/herdrdev/herdr/releases/tag/v0.9.0)。目前的
24,286,088-byte candidate 已建置成功，並通過 CLI named session、pane I/O、detach
與 reattach，SHA-256 為
`fe35d6587f524626512f6897d3113825717d2cdf3bdc791161988f8b084672af`。
CLI host resize 尚未解決，原版 iPad 傳輸仍待續。

## 目前裝置上的安裝

已測試的 v0.8.2 產物如下：

| 欄位 | 值 |
|---|---|
| 路徑 | `~/.local/bin/herdr` |
| 版本 | `herdr 0.8.2` |
| Bytes | `21556492` |
| SHA-256 | `3ede5a4aed39470a67a66453b305f086bf51275c03d7bd0c16c513beb3dd9809` |

納管的 profile 會把 `~/.local/bin` 加入 `PATH`。手動安裝後開新的 login shell，
或重新載入：

```sh
. ~/.profile
command -v herdr
herdr --version
```

既有檔案採 install-only：在使用者明確選擇新的鎖定 release 前，bootstrap 與
update hook 都會保留可用 binary。

## 提供給使用者的方式

通過驗收的 iSH build 會放在本 repo 的 GitHub Releases。像
`herdr-ish-v0.9.0-r1` 的 release tag 可區分 upstream 版本與本相容包的 revision。
每個 release 包含 ELF32 binary、SHA-256 檔、build manifest 與 patch checksums。

確切 release 產物完成原版實機驗收後，維護者把生成的 row 加入
`config/assets.lock`、開啟 iSH `herdr` 選項並補 installer fixtures。使用者即可執行：

```sh
sh bootstrap.sh --manager sh --with herdr
```

Release row 尚未存在時，iSH 會刻意拒絕 `--with herdr`，避免 bootstrap 依賴未發布
產物，也避免把 host 建置／版本檢查誤當成實機驗收。

## 可重現的 v0.9.0 建置

在 x86_64 Linux 維護主機上，先查看完全鎖定的計畫；此指令不連網、不產生輸出檔：

```sh
sh scripts/build-herdr-ish.sh --print-plan
```

把已審查版本建置到新的輸出目錄：

```sh
sh scripts/build-herdr-ish.sh \
  --version v0.9.0 \
  --release-revision r1 \
  --output /tmp/herdr-ish
```

`config/herdr-build.lock` 固定 upstream tag commit、Rust／rust-src、Zig、bytes 與
SHA-256。Script clone 確切 commit、套用該版本與共用相容 patches、建置 i586 musl
binary、核對版本，並產生：

- `herdr-v0.9.0-ish-i386`
- `herdr-v0.9.0-ish-i386.sha256`
- `manifest.json`
- `patches.sha256`
- `assets-lock-row.txt`

GitHub Actions 的 `Herdr iSH artifact` workflow 每週檢查 upstream 是否有新版。
若出現新 tag，檢查會失敗並提示 review，不會自動建置未知程式碼。手動執行會建置並
保留 Actions artifact；要發布還必須明確確認這個確切 binary 已通過原版實機驗收。

每個 upstream 新版都要更新 lock，並建立已審查的
`experiments/patches/herdr-VERSION-ish.patch`。Patch 套用、lock 驗證、建置與實機
驗收必須全部通過。這能明確呈現 upstream API、IPC 與 vendored Ghostty 的變更，
避免舊 iSH 假設被靜默沿用。

## 發布前驗收

透過可信任 SSH，在 iSH 原版 App 測試最終產物的確切 SHA-256：

1. 核對傳輸大小、SHA-256 與 `herdr --version`。
2. 啟動 named session 與 shell pane，檢查輸入輸出。
3. Detach 後 reattach 到相同 pane 與程序。
4. Resize SSH PTY，確認 pane 收到新尺寸。
5. 執行有期限的真實 agent 工作流程，結束時只停止測試建立的 session。
6. 重開 iSH，不替換使用者設定，再重做啟動／session 檢查。

把驗證層級記入 manifest 與[實驗結果](experiments.md)。
