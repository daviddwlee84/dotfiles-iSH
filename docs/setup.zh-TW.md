# 安裝與管理

本 repo 管理精簡的個人 shell 環境。bootstrap 使用 `/bin/sh`（BusyBox ash），
目標機不用先裝 Bash、Python、Ansible 或 just。

## 首次安裝

在目標裝置執行：

```sh
wget -O bootstrap.sh https://raw.githubusercontent.com/daviddwlee84/dotfiles-iSH/main/bootstrap.sh
sh bootstrap.sh
```

已有 curl 時可用 `curl -fLsS -o bootstrap.sh URL`；OpenWrt 沒有 wget 時用
`uclient-fetch -O bootstrap.sh URL`。下載器需支援 HTTPS 並信任伺服器憑證，
不要停用驗證。沒有下載器或網路時，先把解壓後的 checkout 複製到裝置，再執行
其中的 `bootstrap.sh`。單檔入口將 GitHub source snapshot 放到
`~/.local/share/dotfiles-iSH`；若來源已存在就沿用，不覆蓋客製 checkout。
首次下載可設定 `DOTFILES_REF` 指定 tag 或 commit，預設是 `main`。

## 選擇管理方式

```sh
sh bootstrap.sh --dry-run
sh bootstrap.sh --manager sh
sh bootstrap.sh --manager chezmoi
sh bootstrap.sh --config-only --manager sh
sh bootstrap.sh --doctor
```

預設 `auto`：iSH 使用 sh；OpenWrt 使用可執行的 chezmoi，或嘗試下載鎖定的
官方 binary。OpenWrt 首次無法取得 chezmoi 時，才在寫設定前改用 sh。
明確指定 `--manager chezmoi` 時，失敗就停止。成功選擇記在
`~/.local/state/dotfiles-lite/manager`，後續 auto 沿用；切換需明確指定。
設定套用失敗不會悄悄改用另一個 manager。

`--config-only` 跳過套件與下載，支援離線部署設定。`--dry-run` 只列出 manifest
預覽，不是逐行 diff；chezmoi 安裝完成後可用 `chezmoi diff` 看真正差異。
sh 遇到受管理檔案的客製變更會保留並停止，請先比對來源與目標再重跑。

已有 chezmoi 時也可直接使用：

```sh
chezmoi init --apply https://github.com/daviddwlee84/dotfiles-iSH.git
```

已有 curl 與網路時，支援官方的一行安裝；此入口由 chezmoi 主導，沒有 sh 備援：

```sh
GITHUB_USERNAME=daviddwlee84
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply "https://github.com/$GITHUB_USERNAME/dotfiles-iSH.git"
```

官方 installer 跟隨 upstream；本 repo 的 bootstrap 則校驗鎖定的 chezmoi asset。
bootstrap 不接管其他 repo 的既有 chezmoi 設定；可改用 sh，或自行明確遷移 source。

## 設定歸屬與更新

`.chezmoiroot` 只選取 `home/`；sh 透過 `config/files.list` 部署同一份來源。
README、歷史、skills、scripts、locks 與 backlog 都不會部署到家目錄。
`.profile` 只增加 source 精簡 fragment 的區塊；SSH、tmux 只在首次建立，
Git 身分與憑證由你管理。自訂值放在 `~/.config/dotfiles-lite/local.sh`，
這個檔案不會自動建立或納入管理。

安裝不升級已存在的套件或可用 binary。Git checkout 用 `git pull --ff-only`
明確更新來源；snapshot 則下載新版 bootstrap 並使用 --update-source，在替換前將舊來源保存在相鄰 backup。
設定更新與 binary 升級分開處理。維護者更新 `config/assets.lock` 時要一起更新
版本、URL、hash、member 和大小，再通過 CI；需要升級時才明確替換舊 binary。
Herdr 升級必須在 Herdr pane 外依 upstream 的 session 保留流程進行。

選裝使用 `--with dev` 或 `--with starship`；OpenWrt 另接受 `herdr,specstory,codex`，可重複給旗標。
未提供 `--with` 時沿用上次選擇；提供清單則替換記錄，不解除安裝任何工具。
選裝失敗會保留基本設定並回傳非零；基本套件失敗則在套用設定前停止。
套件安裝不是完整的原子交易，已安裝成功的套件會留下。

ash prompt、選裝 Bash、chezmoi 套件相容性與 snapshot 更新方式見 [Shell 與 Starship](shell.md)。

`--package-network direct`（或 `DOTFILES_PACKAGE_NETWORK=direct`）只在套件管理器呼叫內
清除 app proxy 變數；binary／source 下載仍沿用外層環境。預設 inherit，不會偷偷改道。
