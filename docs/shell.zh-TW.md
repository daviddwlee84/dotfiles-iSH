# Shell 與 Starship

預設 login shell 維持 ash。互動 ash 使用 shell 內建功能顯示彩色兩行 prompt，
不在每次 prompt 執行外部 binary，也不要求 Nerd Font；非互動 shell 不輸出提示字元。
個人 local.sh 最後載入，仍能覆寫 PS1。

```sh
sh bootstrap.sh --with starship
. ~/.profile
bash
```

Starship 使用官方支援的 Bash 初始化，不把 Bash init 塞進 ash。
選裝會加入 Bash 與精簡 Starship preset：使用者、主機、目錄、狀態字元，
不掃描語言／runtime。輸入 `bash` 進入、`exit` 回到 ash；不執行 chsh 或自動替換 shell。
既有 `~/.config/starship.toml` 是 seed，會保留；`.bashrc` 只增加標準 managed source block。
`DOTFILES_PROMPT=plain bash` 可略過 Starship。

OpenWrt 使用鎖定的 ARM64／x86_64 musl release；iSH 使用目前 Alpine feed 的套件，
不假設現代 Rust binary 一定能在模擬器執行。v3.14 community index 確實有 Starship 0.54.0
與 chezmoi 2.0.16；有套件不等於實機驗證，iSH 的 Starship／chezmoi 在實測前仍屬實驗性。
即使選裝 binary 失敗，ash prompt 仍可使用。

更新既有 snapshot 時，先重新下載新版獨立 bootstrap，再執行
`sh bootstrap.sh --update-source --with starship`，更新旗標須放第一個。
舊 snapshot 會完整保存在顯示的相鄰 backup 路徑。Git checkout 不替換，請自行 `git pull --ff-only`。

iSH 首次顯示 `Configuration manager: sh` 是原設計：auto 沿用已選的 sh。
要明確改用 chezmoi，可執行 `sh bootstrap.sh --manager chezmoi`；installer 會使用
相容的鎖定 i386 binary。Alpine 3.14 的舊套件早於本 repo 使用的 source features，
現在不會只因 `--version` 成功就誤認為能管理這份來源。

參考：[Starship guide](https://starship.rs/guide/)、
[Starship releases](https://github.com/starship/starship/releases)、
[Alpine v3.14 community x86 index](https://dl-cdn.alpinelinux.org/alpine/v3.14/community/x86/APKINDEX.tar.gz)。
