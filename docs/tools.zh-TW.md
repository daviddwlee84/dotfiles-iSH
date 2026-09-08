# 工具與支援

預設從目前 Alpine repositories 安裝 `git openssh-client tmux nano vim curl ca-certificates`。
`--with dev` 從相同來源加裝 `jq less rsync python3`。Python 版本跟隨該分支，
不承諾現代 wheel 或 LSP 相容。

使用 ash 與精簡 profile；完整 Unix zsh、mise、Ansible、Node agents、SpecStory
不在本機支援範圍。Herdr 已有裝置專用的實驗性 i386 build，但完成其餘驗收前不開放
一般 installer。chezmoi 有鎖定的 i386 binary，但 `--manager chezmoi` 在 iSH
模擬器上仍屬實驗性。目標安裝不編譯原始碼，也不遷移 Alpine 分支。

`ovault [SUBDIR]` 必要時開啟 iOS Files picker，然後進入 vault。
`OBSIDIAN_MNT` 預設 `/mnt/dq/Obsidian`，可在 local.sh 覆寫。
`ovsync [REPO] [MESSAGE]` 會明確 stage 全部變更、commit、rebase、push；
bootstrap 永遠不會呼叫它。請自行設定 Git 身分與 SSH keys。
掛載判斷採空目錄 heuristic：已掛載但空的資料夾可能再次顯示 picker；app 重啟需重新掛載。
safe.directory 只加入選取的確切 Git 目錄，不使用 wildcard。

舊 `ish-bootstrap (obsidian)` inline helpers 會保留；只有找不到 `ovault` 時才載入新版。
要採新版 helpers，請先比對並手動移除舊 marker 區塊，同時保留客製掛載路徑。
SSH、tmux 只 seed 新設定；tmux 用 Ctrl+b 然後 1..9，不配置 extended keys 或滑鼠。
既有 tmux 設定保持原樣。

Agent 工作請 SSH 到 Unix 主機，在遠端 attach Herdr，再於專案中執行
`specstory run codex` 或其他已安裝 agent。Session 與歷史留在該主機。
[iSH 上的 Herdr](herdr-ish.md)另記本機相容產物與 release 流程；目前支援的遠端
工作方式見 [iOS 終端機](ios-terminals.md)。

內建 ash prompt 與 `--with starship` 見 [Shell 與 Starship](shell.md)。
