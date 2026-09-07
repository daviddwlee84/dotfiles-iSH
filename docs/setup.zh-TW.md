# 安裝與管理

**iSH 和 OpenWrt 都預設使用 chezmoi。** bootstrap 負責首次安裝／舊版遷移，
平常更新設定直接使用 chezmoi。初始目標環境只需要 `/bin/sh`（BusyBox ash）和 HTTPS 下載器。

## 首次安裝或從舊版 sh 遷移

即使已有舊 bootstrap，也先在裝置下載目前的入口：

```sh
wget -O bootstrap.sh https://raw.githubusercontent.com/daviddwlee84/dotfiles-iSH/main/bootstrap.sh
sh bootstrap.sh
. ~/.profile
```

之後使用熟悉的指令：

```sh
chezmoi diff
chezmoi apply
chezmoi update
```

`chezmoi update` 先以 `git pull --ff-only` 更新來源，再透過原生 apk／opkg
補齊缺少的基本／已選裝套件，最後套用家目錄設定。不升級已存在的套件或可用 binary。
Pull 失敗就停止，不進入 apply。分歧 commit 或衝突的 source 修改會保留，
由你解決；updater 不自動 stash、commit 或 push。

獨立入口先取得安裝用的 source snapshot，備妥必要工具後建立真正的 Git checkout，
放在 `~/.local/share/dotfiles-iSH`，追蹤 `origin/main`。
既有 snapshot 連同自訂 source 檔案完整保存在顯示的相鄰 backup 路徑；
新的作用中來源是 upstream checkout。有意保留的 source 客製請從 backup 比對搬回。
已存在的 Git checkout 只沿用、不替換。使用新版入口時，舊 sh 安裝會遷移到 chezmoi。
舊 `--update-source` 旗標仍可用於 snapshot refresh，但日常更新不需要它。

已有 curl 時可用 `curl -fLsS -o bootstrap.sh URL`；OpenWrt 也可用
`uclient-fetch -O bootstrap.sh URL`。保持 TLS 憑證驗證。
`DOTFILES_REF` 可改指定 tag／commit；這會產生 detached checkout，
需要回到追蹤中的 branch 才能日常使用 `chezmoi update`。

## 選項與離線使用

```sh
sh bootstrap.sh --with starship
sh bootstrap.sh --with dev,starship
sh bootstrap.sh --dry-run
sh bootstrap.sh --doctor
sh bootstrap.sh --manager sh --config-only
```

預設 manager 是 `chezmoi`；`auto` 保留為相同意思的相容別名。
已安裝且相容的 chezmoi 會沿用，否則下載鎖定的官方 binary，校驗 hash 並限時測試能力。
失敗就停止並提示可明確改用 `--manager sh`，不悄悄切換。
Alpine 3.14 的原生 chezmoi 2.0.16 不支援本 repo 的 source layout；
鎖定的現代 i386 版本在真正 iSH 驗收前仍屬實驗性。

`--manager sh` 是可明確選擇的精簡替代方式，部署同一份家目錄設定。
之後再次執行預設 bootstrap 會改用 chezmoi。
`--config-only` 跳過套件、工具下載和 Git 遷移；從已複製的來源執行可離線套用。
離線 snapshot 可以 apply，但要先完成一次線上 bootstrap 建立 Git，才能 `chezmoi update`。
`--dry-run` 只預覽 manifest、不寫入；真正差異使用 `chezmoi diff`。

選裝記在 `~/.local/state/dotfiles-lite/options`。未給 `--with` 就沿用，
給清單則替換選擇但不移除任何套件。OpenWrt 另接受 `herdr,specstory,codex`。
選裝失敗會保留可用基本設定並回傳非零；基本套件失敗則在設定前停止。
套件安裝不是原子交易，已成功加入的套件會留下。

## 來源與套件的連線方式

`--source-network inherit|direct|proxy` 控制 Git 和工具下載；proxy 需要 OpenWrt
已啟用且有驗證的 Nikki。`--package-network inherit|direct` 獨立控制原生套件下載。
兩者預設都是 inherit。成功 setup 後會儲存這些**不含機密的選擇**，
讓普通 `chezmoi update` 沿用；proxy 憑證只在執行時讀取，不寫進 dotfiles。

`DOTFILES_SOURCE_NETWORK`／`DOTFILES_PACKAGE_NETWORK` 可針對一次指令覆寫選擇。
要永久調整，從 source 執行 bootstrap 並指定旗標。
既有自訂 `[update]` 設定會保留；沒有該 section 時才自動加上此 updater。
GitHub 初次下載的連線處理請參考 OpenWrt network 文件。

## chezmoi 管理什麼

`.chezmoiroot` 只選取 `home/`，repo metadata 與 scripts 留在來源目錄。
`~/.config/chezmoi/chezmoi.toml` 記錄 checkout 位置和更新 script。
同一來源的舊 config 只補上 update section，並保留 backup；不接管其他 repo 的 chezmoi source。

`~/.profile` 是登入 shell 的入口。安裝器保留原有內容，只增加一段載入
`~/.config/dotfiles-lite/profile.sh` 的區塊。該 fragment 加入 `~/.local/bin` PATH、
設定預設 EDITOR／PAGER、載入互動 alias 和 prompt，最後載入你自己的
`~/.config/dotfiles-lite/local.sh`。個人覆寫值可放在這裡；它不會被建立或納管。
開啟 shell 不會下載、安裝套件或自動執行 chezmoi update。

SSH、tmux、Starship config 是只建立一次的 seed；Git 身分與憑證由你管理。
ash 與 Bash 的差別見 [Shell 與 Starship](shell.md)。

已經有相容 chezmoi 且 Git／網路可用時，也支援直接初始化，使用相同套件／apply hooks：

```sh
chezmoi init --apply https://github.com/daviddwlee84/dotfiles-iSH.git
```

工具 binary 升級仍是明確操作：維護者一起更新 `config/assets.lock` 的版本、URL、
hash、member 和大小並通過 CI；既有可用版本會保留。
Herdr 升級應在 pane 外依 upstream 保留 session 的程序執行。
