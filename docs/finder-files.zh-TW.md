# Finder 檔案共享

拖入 **Finder → iPad／iPhone → 檔案 → iSH** 的檔案位於 iSH App 的 iOS Documents
目錄。Setup 預設將它掛載到 `/mnt/finder`。這是即時視圖，在此修改或刪除也會影響
Finder 裡的同一份檔案。

## 安裝與選項

Bootstrap 在檢查 chezmoi runtime 前準備掛載。互動式 `chezmoi init --apply`
會詢問 **Mount iSH Finder files**，首次預設 yes。非互動 init 使用
`--promptDefaults`，或以 `--promptBool 'Mount iSH Finder files=false'` 關閉此選項。

在目前版本的來源目錄內，以下指令不需要可運作的 chezmoi：

```sh
sh bootstrap.sh --prepare-finder
ls -lh /mnt/finder
sh bootstrap.sh --prepare-finder --finder off
sh bootstrap.sh --prepare-finder --finder on
```

一般 bootstrap 也接受 `--finder on|off`。選擇儲存在
`~/.local/state/dotfiles-lite/finder`；明確 CLI 或 `DOTFILES_FINDER` 優先，
後續 apply／update 沿用已保存的選擇。SSH 與 Finder 各自獨立，
`--prepare-sshd` 仍然只準備 SSH。`--dry-run` 不寫入；`--config-only` 保存選項，
但不掛載、不安裝 OpenRC 或註冊服務。此選項僅適用 iSH。

## 啟動與既有資料

Setup 補齊 OpenRC，建立一次性的 `/usr/local/libexec/dotfiles-finder` 與
`/etc/init.d/dotfiles-finder`，立即掛載，並將服務加入 default runlevel。
每次 iSH 啟動都重新讀取 `/proc/ish/documents`，不寫死 iOS container 路徑。
開機不需要來源 checkout、chezmoi 或 login shell。

Helper 先查 `/proc/mounts`，已正確手動掛載時直接沿用。其他掛載、子目錄掛載、
symlink，或未掛載但非空的目錄都會保留並回報衝突。其他 Files provider 掛載不受影響。
Helper 與服務都是只建立一次的 seed，保留個人修改。

`--finder off` 只移除往後的自動啟動註冊，保留目前掛載、檔案及工作。
停止服務也不會卸載。若要立即卸載，先離開該目錄並結束使用它的工作，
再自行執行 `umount /mnt/finder`。

## 手動讀取與驗證

在空的掛載點手動建立相同掛載：

```sh
mkdir -p /mnt/finder
mount -t real "$(cat /proc/ish/documents)" /mnt/finder
ls -lh /mnt/finder
```

實驗用 binary 可複製到 Linux 家目錄，壓縮包也可解壓在那裡：

```sh
mkdir -p ~/ish-lab
tar -xzf /mnt/finder/ish-ssh-setup.tar.gz -C ~/ish-lab
```

完整關閉再開啟 iSH 後，檢查已安裝的 helper 與服務：

```sh
/usr/local/libexec/dotfiles-finder status
rc-service dotfiles-finder status
ls -lh /mnt/finder
```

使用者已在 iPad 確認手動掛載成功。維護者隨後透過 SSH 安裝 helper／service、核對
壓縮包 SHA-256、完成掛載，並成功執行 OpenRC start 入口。傳入的 hako、Herdr 雜湊
均符合建置產物。使用者隨後完整重開 iSH，沒有手動掛載；遠端檢查確認掛載與兩個
服務正常、Finder OpenRC 啟動紀錄更新，且 binary 雜湊一致。Finder 已通過一次
完整 App 重開驗證；三次重開計畫中的其餘次數尚未記錄。
自動啟動不會防止 iOS 在背景暫停 iSH。

來源：iSH 的 [theme UI 說明](https://github.com/ish-app/ish/blob/d189985e5cc6d0e70629efeb31505b51a9ce78af/app/ThemesViewController.m#L139)
與 [OpenRC 指南](https://github.com/ish-app/ish/wiki/How-To-Enable-OpenRC-%26-Start-Services-When-iSH-App-Starts)。
另一種 Files picker 掛載使用 `mount -t ios . DIRECTORY`，具有自己的
[bookmark 還原機制](https://github.com/ish-app/ish/blob/d189985e5cc6d0e70629efeb31505b51a9ce78af/app/iOSFS.m)。
