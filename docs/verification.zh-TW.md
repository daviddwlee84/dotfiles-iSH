# 驗證與維護

在維護主機執行 `just check`：ShellCheck、Bats、雙語 MkDocs strict build。
目標安裝不依賴這些工具。測試隔離 HOME、XDG、chezmoi config 與假套件指令；
只有明確 fixture sentinel 加上相符的暫存 HOME 才接受測試路徑。

測試包含真正 chezmoi 與 sh 的輸出一致性、重跑、保留 SSH／tmux／Git／profile、
舊 iSH helpers、目標判斷、apk／opkg、分支辨識、離線、dry-run、checksum 拒絕與安裝失敗。
CI 另在可拋棄的 x86_64／ARM64 musl container 啟動鎖定的 Linux binary。
版本檢查只證明啟動，不代表 agent 登入、程序隔離、模擬器相容、低記憶體穩定性或真實 session。

## 實機驗收

記錄日期、裝置、OS／build、架構、套件管理器、設定 manager、可用 RAM／空間與工具版本，然後檢查：

1. 首次 bootstrap，重開 login shell，執行 `git --version`、`ssh -V`、`tmux -V`。
2. 重跑兩次，確認既有設定與 local overrides 保留。
3. 正常核對 host key 後 SSH 到已知主機，建立、detach、resume tmux；iSH 另測 app suspend 與取消 Files picker。
4. 有選 chezmoi 時測 diff／apply；iSH 必須重複做真正模擬器測試。
5. OpenWrt 確認路由、Wi-Fi 與既有服務持續正常，量測 Herdr／SpecStory／Codex session 的資源用量。
6. Agent 由你使用個人憑證手動驗收；憑證與私人 prompt 不進 log 或 public repo。
   不藉停用 agent 隔離把不支援的 runtime 宣稱為成功。

**目前狀態（2026-09-07）：**使用者已確認 iSH v3.14 snapshot 的 sh 基本安裝成功。
新版 chezmoi 與 Starship 路徑仍待 iSH 實機驗收。

兩個輕量 repo 的共用 shell core、tests、assets lock 是相同副本，變更共同行為時同步修改。
套件來源與使用者設定維持平台原生；維護工具及 release assets 不自動升級。

chezmoi x86_64 使用明確的 `linux-musl_amd64` asset；upstream 的
`linux_amd64` 是 glibc build 別名，不能直接當成 router 預設 binary。

Git 整合 fixture 另涵蓋 snapshot backup、main tracking、真正 upstream 新 commit
後的普通 chezmoi update／apply、離線失敗，以及既有／自訂 chezmoi config 保留。

啟動 probe 現在於 15 秒後送 SIGKILL，並區分下載／hash／解壓／版本／template 階段。
回歸測試驗證忽略 TERM 的程序仍會被終止；這不代表 iSH 模擬器相容性已驗收。

## SSH 與本機 agent（2026-09-08）

SSH fixtures 覆蓋預設選擇、init／CLI 優先序、獨立復原、只建立一次的設定歸屬、
缺少 key、明確 default runlevel、啟動失敗，以及關閉自動啟動時保留目前 session。
原生 Alpine OpenSSH 接受此 config；iSH CLI guest 也通過 Ed25519 生成及 config
驗證。真正裝置的觀察另記於下方。

使用者首次回報的 iPad 執行在安裝 OpenRC 後、設定服務前，暴露出
`/sbin/rc-status` 路徑錯誤。安裝器與 fixture 已改成 Alpine 的
`/bin/rc-status`。使用者隨後重跑準備成功，包含 key 生成、config 驗證與
default runlevel 註冊。使用者再確認完整重開 app 一次後，可用密碼登入
`ssh localhost -p 22000`。使用者也已從 Mac 用密碼登入，維護者隨後直接以公鑰
登入並執行遠端 shell 命令。實機回報 iSH 1.3.2（494）、Alpine 3.14.3、i686，
OpenRC 位於 default，SSH 已啟動。部分後續連線卡在 banner 前，使用者重開
iSH 後恢復連線；此間歇性問題的原因未確認，iPadOS 版本也尚未記錄。
使用者也確認 hako 可開啟。最初使用原版 std 的 Herdr 重現 server spawn error 22；
後續相容 binary 已安裝到 `~/.local/bin/herdr`，確切大小／hash 與版本均完成核對，
使用者回報可執行。詳細 session／resize 與登入後 agent 工作流程仍待驗收。

後續直連已通過 SSH PTY 輸入輸出與尺寸設定、legacy SCP 上傳／下載逐位元組比對，
以及 SHA-256 驗證的 SSH 壓縮包／binary 傳輸。兩種 SFTP server 都在認證後失敗，
直接啟動定位到缺少 `PR_SET_DUMPABLE`。SFTP 仍不支援，因此不宣稱原本完整的
SSH／SFTP／多次重開關卡已通過。

Finder helper／service 已安裝到 iPad，掛載、OpenRC 註冊及明確 service start 都成功，
hako／Herdr 檔案雜湊符合建置產物。使用者完整重開 iSH、沒有手動 mount 後，
直連確認 Finder 已掛載、兩個服務正常、Finder OpenRC 啟動紀錄更新，SSH 啟動
紀錄由兩次增加到三次，binary 雜湊仍一致。Finder 已通過一次完整 App 重開驗證，
其餘計畫中的重複次數尚未記錄。hako 隔離版號檢查
回傳 v0.2.3。重新編譯的 Rust 最小診斷確認：一般子程序可用，`pre_exec` 回傳
error 22，帶 flags 的 STREAM socketpair 回傳 error 93，SEQPACKET 回傳 error 22。

版本 probe 現在隔離 HOME、XDG 路徑、cwd 與認證環境。hako v0.2.3 在解析
`--version` 前已讀寫狀態；fixture 驗證具有相同行為的 agent 不會改到呼叫者的
home／project 狀態，也不會繼承認證變數，成功及失敗時都會清理暫存資料。

Finder fixtures 覆蓋 setup／init 預設、保存關閉選項、沿用正確手動掛載、重跑、
保留隱藏檔案／symlink／其他掛載、掛載失敗，以及開機 helper 不依賴 checkout
並重新讀取變動的 Documents 路徑。iPad 手動掛載與一次完整 App 重開後的自動
掛載都已獲實機確認。見 [Finder 檔案共享](finder-files.md)。

[SSH 伺服器](ssh-server.md)與[實驗](experiments.md)分開記錄 runtime 和登入後
工作流程的驗收；新 agent installer 在實機通過前維持關閉。
