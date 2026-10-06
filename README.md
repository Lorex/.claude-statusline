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

## 安裝

需求：`bash`、`jq`、`git`、`curl`；macOS 會從 keychain 讀取 Claude Code 的 OAuth token（其他平台讀 `~/.claude/.credentials.json`）以查詢模型專屬用量，讀不到時自動退回 payload 內的數字。

```sh
curl -fsSL https://raw.githubusercontent.com/Lorex/.claude-statusline/main/statusline.sh -o ~/.claude/statusline.sh
```

在 `~/.claude/settings.json` 加入：

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/statusline.sh\"",
    "refreshInterval": 1
  }
}
```

`refreshInterval: 1` 讓 prompt 計時器在執行中每秒更新；不需要的話可以拿掉，statusline 仍會在事件發生時刷新。

快取與除錯檔案放在 `~/.claude/cache/`（`last_payload.json` 保存最近一次收到的 payload，方便查欄位）。
