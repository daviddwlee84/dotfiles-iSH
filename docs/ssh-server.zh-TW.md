# SSH 伺服器與實機直連測試

iSH 可以執行 SSH server。本 repo 在 iSH 預設準備 OpenSSH 與 OpenRC，
使用獨立的 `dotfiles-sshd` service，預設 **22000 埠**。
此選項不修改 OpenWrt 的 SSH 服務。

## 首次設定

先在匯入的 iSH filesystem 副本操作，保留原環境作為復原點。
在裝置上執行目前 source 的 bootstrap：

```sh
sh bootstrap.sh --prepare-sshd
passwd
```

`--prepare-sshd` 只準備 SSH，不依賴可運作的 chezmoi。一般 bootstrap 也會先準備
SSH，再檢查 chezmoi。`passwd` 是獨立的互動操作：密碼只在裝置上輸入，
不放進 script、對話、shell 參數或 dotfiles。Root 密碼為空或帳號鎖定時，
安裝器會顯示登入設定待完成，不會修改密碼。

若剛安裝 OpenRC，請完全關閉再開啟 iSH。安裝器明確註冊到 **`default` runlevel**，
等該 runlevel 就緒才啟動。不執行 `openrc default`、修改 app 的 boot/login command，
也不啟用其他服務。自訂 boot command 若沒有啟動 OpenRC，需要手動檢查。

在 iSH 檢查：

```sh
rc-status
rc-service dotfiles-sshd status
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

首次測試保持 iSH 在前景。從 iOS 設定取得 iPhone／iPad 的 Wi-Fi IPv4 位址；
若系統詢問，允許 iSH 存取區域網路。在 Mac 執行：

```sh
ssh -p 22000 root@DEVICE_IP
ssh-copy-id -p 22000 root@DEVICE_IP
ssh -p 22000 root@DEVICE_IP
sftp -P 22000 root@DEVICE_IP
```

首次連線請核對裝置顯示的 host-key fingerprint。`ssh-copy-id` 透過密碼登入後
複製你的**公鑰**；私鑰留在 Mac。Filesystem 副本最初可能沿用原環境的 host keys，
測不同身分時應使用獨立 known-hosts 項目，不自動覆寫變更的 host key。

## 選項與設定歸屬

互動式 `chezmoi init --apply` 會詢問 **Enable iSH SSH server**，首次預設 yes。
非互動初始化使用 `chezmoi init --promptDefaults --apply`，或
`--promptBool 'Enable iSH SSH server=false'`。重新 init 可明確改選；
一般 apply／update 讀取已儲存選項，不重新詢問。

```sh
sh bootstrap.sh --sshd off
sh bootstrap.sh --sshd on
sh bootstrap.sh --prepare-sshd --sshd off
sh bootstrap.sh --prepare-sshd --dry-run
```

非機密選項放在 `~/.local/state/dotfiles-lite/sshd`，兩種 manager 共用。
明確的 `--sshd` 或 `DOTFILES_SSHD` 優先；chezmoi 初始化資料只在尚無 state 時採用。
SSH 專用入口會先保存選項，即使之後 chezmoi probe 失敗也保留。
`--config-only` 會保存選項並套用 home files，但不執行 SSH 系統操作。

安裝器只建立一次自己的兩個 seed：

- `/etc/ssh/dotfiles-lite/sshd_config`
- `/etc/init.d/dotfiles-sshd`

保留 `/etc/ssh/sshd_config`、現有 host keys、authorized keys 及既有 server。
只補齊自己的 config 使用的 Ed25519 key，避免在模擬器生成不需要的 RSA／DSA keys。
新設定允許 root 公鑰／密碼登入、拒絕空密碼，並宣告 `internal-sftp`
（實測裝置不支援，見下方傳檔說明）。
預設監聽 IPv4 的 22000 埠，不配置路由或防火牆轉發。Seed 的個人修改會保留，
手動變更埠或登入規則前，請自行檢查設定。

每次準備先驗證 config，再啟用服務；已在執行的服務不重啟。
`--sshd off` 只移除本服務的自動啟動註冊，不停止目前 server／session，
不移除套件、config 或 keys。要明確停止服務，使用 `rc-service dotfiles-sshd stop`。

## 排錯與驗證

查詢 Mac 連線要用的位址：在 **iPad 設定 → Wi-Fi**，點目前已連線網路右側的
**ⓘ**；見 [Apple 網路設定說明](https://support.apple.com/guide/ipad/connect-to-the-internet-ipad2db29c3a/ipados)。
讀取 IPv4 區塊的 **IP 位址／IP Address**，再於同一網路的 Mac 執行
`ssh -p 22000 root@DEVICE_IP`。路由器位址是另一個欄位。

使用者的 iSH 執行 `ifconfig` 時回報：

```text
ifconfig: /proc/net/dev: No such file or directory
ifconfig: ioctl 0x8912 failed: Not a tty
```

這些網路介面查詢錯誤不會阻止 SSH socket 運作；裝置位址可從 iPadOS 設定讀取。
`localhost:22000` 成功代表本機 server 可登入；Mac 連入仍需要 iPad 的 Wi-Fi IP。

後續連線若停在 `Connection timed out during banner exchange`，先讓 iSH 保持
前景、iPad 螢幕未鎖定，再重試。此時尚未進入 SSH 認證或 SFTP 協商，不能只根據
此訊息認定 SFTP 失敗或更改認證設定。首次 Mac 直連已成功用公鑰登入，後續連線
則卡在此階段。使用者重開 iSH 後，命令通道恢復；間歇性停頓的確切原因仍未確認。
iSH 的 **Keep Screen Turned On** 可防止前景自動熄屏，但不能讓背景 App 持續執行。

### 實測 iSH 版本的傳檔方式

SSH 命令及 PTY 輸入輸出可用，但兩種 SFTP server 模式都在認證後關閉。
直接啟動回報 `unable to make the process undumpable`：iSH 缺少 OpenSSH
啟動保護所需的 `PR_SET_DUMPABLE`。見[診斷紀錄](https://github.com/daviddwlee84/dotfiles-iSH/blob/main/pitfalls/sftp-connection-closed.md)
與[上游回報](https://github.com/ish-app/ish/issues/2153)。

具 SSH shell 權限的帳號可使用 [SCP 的 `-O` 選項](https://man.openbsd.org/scp#O)：

```sh
ssh -p 22000 root@DEVICE_IP 'mkdir -p /root/ish-lab'
scp -O -P 22000 ./local-file root@DEVICE_IP:/root/ish-lab/
scp -O -P 22000 root@DEVICE_IP:/root/ish-lab/local-file ./returned-file
```

Legacy SCP 上傳／下載已通過逐位元組比對。SSH stdin 串流也成功傳入 setup 壓縮包
與 binary，並核對 SHA-256。此版本的 SFTP 記為不支援，保留 server 的保護檢查。

### 安裝失敗

若早期傳輸包停在 `SSH prerequisite missing: /sbin/rc-status`，原因是寫錯
Alpine OpenRC 的路徑；實際執行檔為 `/bin/rc-status`。此時尚未建立服務或
註冊自動啟動，只重開 iSH 不會完成設定。換用新版包，或修正已解壓的副本後重跑：

```sh
cd ~/ish-ssh-setup
sed -i 's|/sbin/rc-status|/bin/rc-status|g' scripts/sshd.sh
sh setup-sshd.sh
```

已用 `passwd` 設好的密碼會保留。準備成功後若提示重開 iSH，就依提示操作，
再用 `rc-service dotfiles-sshd status` 確認狀態。

啟動失敗先看 `/var/log/dotfiles-sshd.log`。埠衝突不會觸發停止其他 server。
無效 config 或同名 service 衝突會使 SSH 設定失敗並回報原因；一般 bootstrap
仍可保留已完成的 home baseline，最後另外回報 SSH 失敗。

公鑰登入失敗時，檢查帳號狀態、home 擁有者與 `.ssh` 權限。
不要全面修改擁有者或自動套用 password-hash workaround。
[官方 SSH 指南](https://github.com/ish-app/ish/wiki/Running-an-SSH-server)
記錄了相關症狀；本安裝器把帳號修改留給使用者。

自動啟動是指 iSH boot 時啟動，不代表 iOS 暫停 app 後仍能持續執行。
[背景指南](https://github.com/ish-app/ish/wiki/Running-in-background)的定位保活不會自動啟用。
[OpenRC 指南](https://github.com/ish-app/ish/wiki/How-To-Enable-OpenRC-%26-Start-Services-When-iSH-App-Starts)
說明首次啟動的 runlevel 與硬體服務限制。

完成公鑰登入及 known-hosts 核對後，在 Mac 執行維護者 probe：

```sh
sh scripts/ish-probe.sh --host DEVICE_IP
sh scripts/ish-probe.sh --host DEVICE_IP --case node --output /tmp/ish-node-report.txt
```

Probe 只連到明確指定的主機，使用已核對 host key、公鑰登入、連線期限與限時 runtime
檢查；遠端沒有 `/proc/ish` 就拒絕執行。報告是私人本機檔案，分享前先檢查。
它不安裝工具，也不替 agent 登入。另見[實驗](experiments.md)。

實機驗收須完整重開 iSH 三次後都能重新連線，並測公鑰／密碼登入、PTY 輸入與 SFTP。
Host fixtures 不代表已通過實機驗收。
