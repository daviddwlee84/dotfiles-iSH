# iOS 終端機

本 companion 負責 iSH 安裝，完整 Unix repo 不部署到 iSH。
iSH 提供模擬的 32 位元 x86 Alpine userspace；iPhone 處理器是 ARM，
不代表其中可以執行 Linux ARM64 asset。

## 本機與遠端

iSH 用於 Git、SSH、少量編輯及 Files／Obsidian 同步；Herdr、SpecStory、coding agents
透過 SSH 到 Unix 主機使用。支援邊界依工具發行檔與模擬器實際行為判斷，
不再用「所有 iOS app 永遠不能執行某類工具」概括。

Herdr、SpecStory 目前發行 64 位元 Linux asset，本 repo 沒有 iSH／i386 installer。
Node／Rust／Go 工作負載有歷史 SIGILL、deadlock、syscall 回報；它們依版本而異，
不代表用這些語言寫的每個 binary 都不可能運作。chezmoi 有 i386 asset，
本 repo 預設實驗性 chezmoi，同時提供明確的 sh 復原選項。

原始研究指出，CPUID 即使宣告 SSE2，特定指令仍可能撞上尚未實作的 emulator gadget。
不要只憑 CPU feature 推論能否執行；排錯時保留 opcode／錯誤與確切版本。
兩篇遷入的歷史紀錄見 [pitfalls 索引](https://github.com/daviddwlee84/dotfiles-iSH/tree/main/pitfalls)。

## 終端行為

精簡 tmux seed 使用標準 Ctrl+b prefix 然後 1..9，不要求 extended keys 或滑鼠擷取。
歷史 iSH／hterm 回報包括 Ctrl+2／6 變成舊式 control bytes、觸控事件不進 tmux；
`TERM=xterm-256color` 不足以證明鍵盤能力。Clipboard 保留 tmux OSC 52，仍需測你的 iSH build。

iOS 可能在 app 離開前景後暫停 iSH；持久 session 留在遠端主機。
Keepalive 只能發現斷線，無法防止 suspend；real 掛載在 app 重啟後需要重建，
預設的 [Finder 服務](finder-files.md) 負責恢復 `/mnt/finder`。
Files provider 掛載則使用 iSH 自己的 bookmark 機制。
字型可測 Nerd Font Mono，但仍以實際終端的字寬結果為準。

其他 mobile terminal 可評估 Blink 的 SSH／mosh，Git／Files 專用流程可評估 Working Copy。
鍵盤、訂閱與整合能力會改變，切換前查當時的 app。iSH 內 mosh 有歷史 socket／suspend 問題，
本版不安裝也不宣稱支援。Claude Remote Control 是另一個遠端 agent 選項，
但客製 API base URL／proxy 設定可能影響可用性。

## Alpine 與遷移

你提供的 2026-09-07 實機紀錄確認舊 bootstrap 在 iSH v3.14 snapshot 完成；
它沒有測試新 bootstrap 或 chezmoi。新版已能辨識 snapshot URL，不會遷移分支。
舊文件的 v3.18 建議是歷史紀錄，不是目前的安全或相容性推薦；舊 Alpine 分支可能已 EOL。
要換分支，先備份 iSH filesystem，並在可拋棄 filesystem 分開測試。

原 Unix bootstrap URL 與 playbook 已移除，改用本 repo 的 [安裝](setup.md)。
舊 inline helpers 保留，依 [工具](tools.md) 說明自行明確遷移。
原始研究仍可由 [Unix commit 4073f220](https://github.com/daviddwlee84/dotfiles/blob/4073f2207afb0c865b58321f46c2edfb16c7819c/docs/playbooks/ios-terminals.zh-TW.md) 查閱。

來源：[iSH](https://github.com/ish-app/ish)、[歷史 Go 回報](https://github.com/ish-app/ish/issues/1230)、
[歷史 Node 回報](https://github.com/ish-app/ish/issues/1564)、[chezmoi releases](https://github.com/twpayne/chezmoi/releases)。

後續 iSH 1.3.2 回報：Bash／Starship 已安裝，chezmoi 檢查卡住超過五分鐘。
逾時修正、先恢復 shell 設定及獨立 filesystem 測試見[系統升級](system-upgrade.md)。

## 本機直連測試

預設開啟的 [SSH 伺服器設定](ssh-server.md) 可讓 Mac 連入 iSH 進行實驗。
[本機 agent 研究](experiments.md) 分別追蹤 hako、Pi／Gemini 與 Herdr；
沒有已支援的 installer，不代表所有本機 agent 都不能執行。歷史 SIGILL pitfall 已更正。
