# claude-statusline

Claude Code 的自訂 statusline，風格參考 Powerlevel10k，使用 truecolor 文字色。

```
💛 Opus 5.5 · medium │ 📁 space-form │ ⚡ main ⇡1 +1 ~2 -1 ?2 │ 🧠 █░░░░░░░░░ 7% (72.2k/1.0M) │ 💰 $0.64 │ 🔋 5h 85% (4h45m) · 1w 54% left
⏳ 1m05s… ｜最後一個 prompt 的內容（最多 3 行）
```

## 顯示內容

**第一行**

| 區塊 | 說明 |
|---|---|
| 💛 模型 · effort | 依模型換圖示（Opus 💛 / Sonnet 💠 / Haiku 🌸 / Fable 💜） |
| 📁 專案 | 目前工作目錄名稱 |
| ⚡ git | 分支名（乾淨綠色、有改動金色），後接各類改動的**檔案數**：`⇡` 領先 / `⇣` 落後 upstream、`+` 新增、`~` 修改、`-` 刪除、`?` 未追蹤；5 秒快取 |
| 🧠 context | 使用率進度條與 token 數，<60% 綠 / <80% 金 / 其餘紅 |
| 💰 費用 | 本 session 預估花費 |
| 🔋 用量 | 5 小時與一週額度的**剩餘**百分比與 5h 重置倒數；若 OAuth usage API 有目前模型專屬的週額度則優先顯示（60 秒快取） |

**第二行**

- 最後一個 prompt 的執行時間：執行中 `⏳/⌛` 每秒翻轉並即時計時（金色），完成後顯示 `🏁`（紫色）
- 最後一個 prompt 內容，最多 3 行、每行 80 字

## 安裝（每台電腦）

需求：`bash`、`jq`、`git`、`curl`。macOS 會從 keychain 讀取 Claude Code 的 OAuth token（其他平台讀 `~/.claude/.credentials.json`），用來查詢模型專屬用量；讀不到時自動退回 payload 內的數字。

```sh
git clone https://github.com/Lorex/.claude-statusline.git ~/.claude-statusline
~/.claude-statusline/install.sh
```

`install.sh` 會：

- 把 `~/.claude/statusline.sh` 換成指向 clone 的 symlink（舊檔備份成 `.bak.<時間>`）
- 在 `~/.claude/settings.json` 設定 `statusLine`（含 `refreshInterval: 1`，讓 prompt 計時器每秒更新），修改前會先備份

可以重複執行。clone 放在其他位置也沒問題，symlink 會指向實際所在的目錄。

## 多台電腦同步

- **自動拉取**：statusline 每小時在背景對自己所在的 repo 跑一次 `git pull --ff-only`，所以別台 push 的更新最多一小時內就會出現。本地有未 push 的 commit 或衝突時只會跳過，不會覆蓋。
- **推送修改**：在任一台改完 `statusline.sh` 後，手動 commit + push。
- 想立刻同步：`git -C ~/.claude-statusline pull`

快取與除錯檔案放在 `~/.claude/cache/`（`last_payload.json` 保存最近一次收到的 payload，方便查欄位）。
