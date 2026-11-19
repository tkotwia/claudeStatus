# ClaudeStatus

macOS 選單列上的 Claude Code 狀態圖示。同時開很多個 session 時，一眼看出有幾個正在跑、哪些在等你。

```
✳ 2  ✋ 1  ✓ 3
```

| 顯示 | 意義 |
|---|---|
| `✳ 2` | 2 個 session 正在執行（Claude 在思考或跑工具） |
| `✋ 1` | 1 個 session 被擋住，等你確認權限或回答問題（橘色） |
| `✓ 3` | 3 個 session 跑完了，等你下一個指令 |
| `✳ ?` | 讀不到 session 資料，見[疑難排解](#疑難排解) |

數字為 0 的項目不顯示，所以全部閒置時只有一個 `✳`。

## 涵蓋範圍

| 來源 | 支援 |
|---|---|
| Claude Code CLI | ✓ |
| Claude Code VS Code 擴充 | ✓ |
| Claude Desktop 的 Code 分頁 | ✓ |
| Claude Desktop 的一般聊天、Cowork | ✗ |

一般聊天的回覆在雲端產生，Cowork 在 VM 裡執行，兩者在本機都沒有可讀的狀態。

## 安裝

需要 macOS 14.4 以上，以及 Xcode（或 Swift 工具鏈）來編譯。

```bash
./scripts/build-app.sh            # 產生 build/ClaudeStatus.app
open build/ClaudeStatus.app       # 啟動
```

要在登入時自動啟動：

```bash
./scripts/login-item.sh install     # 安裝並立刻啟動
./scripts/login-item.sh uninstall   # 移除並停止
```

這會在 `~/Library/LaunchAgents/local.claude-status.plist` 寫入一個 LaunchAgent，內容是 app 的絕對路徑。以下兩種情況要重新執行一次 `install`：

- 專案資料夾搬了位置
- 重新編譯之後（執行中的還是舊版，重新安裝會換成新版）

## 使用

點圖示會展開清單，依狀態分組列出 session，每一列顯示資料夾名稱和來源：

```
被擋住
  ✋ my-app · VS Code — 等權限確認
執行中
  ● api-server · CLI
跑完
  ✓ docs · Desktop
────────────
清除跑完的 session
結束
```

- **點某個 session**：跳到它所在的視窗。如果它在「跑完」裡，同時視為已看過，從清單移除。
- **清除跑完的 session**：一次清掉目前所有「跑完」的項目。只在有跑完的 session 時出現。
- **結束**：關閉 ClaudeStatus，到下次登入才會再啟動。

閒置的 session 不會列在清單裡。

### 「跑完」的規則

- **出現**：ClaudeStatus 執行期間，看到某個 session 從執行中或被擋住變成閒置。
- **消失**：你對它送出下一個指令、關閉它、在清單裡點它，或按「清除跑完的 session」。

ClaudeStatus 啟動時已經閒置的 session 不算跑完，所以開著沒用過的面板不會出現在清單裡。

### 跳轉的精準度

| 來源 | 會跳到 |
|---|---|
| VS Code | 正確的視窗和 session 分頁 |
| iTerm2 裡的 CLI | 正確的視窗和分頁 |
| 其他終端機裡的 CLI | 該終端機 app |
| Claude Desktop | Claude app |

第一次跳到 iTerm2 時，macOS 會詢問是否允許 ClaudeStatus 控制 iTerm2，請允許。

## 運作方式

Claude Code 會替每個執行中的 session 維護一個 `~/.claude/sessions/<pid>.json`，狀態一變就更新。ClaudeStatus 只讀這個目錄：

| 檔案裡的 `status` | 歸類 |
|---|---|
| `busy` | 執行中 |
| `waiting` | 被擋住 |
| `idle`、`shell`、其他 | 閒置 |

- 用 FSEvents 監看目錄，變化後約 0.2 秒更新；另外每 5 秒掃一次。
- 行程已經不存在的檔案會被忽略。比對行程啟動時間，避免把重用同一個 PID 的其他行程誤認成 session。
- 不使用 Claude Code hooks，不修改 `~/.claude/settings.json`。
- 不讀取同目錄下的 `.key` 檔。

## 已知限制

- 按 Esc 中斷的 session 也會被歸到「跑完」，因為狀態檔分不出中斷和正常結束。
- Claude Desktop 只能切到 app，無法定位到特定 session。
- 「跑完」的標記存在記憶體裡，ClaudeStatus 重啟後會清空。
- 背景 session（`claude --bg`）沒有實際測試過。
- `~/.claude/sessions/` 的檔案格式沒有官方文件，Claude Code 更新後可能改變。

## 疑難排解

| 現象 | 原因與處理 |
|---|---|
| 圖示顯示 `✳ ?` | 讀不到 `~/.claude/sessions/`。確認這個目錄存在；至少執行過一次 Claude Code 才會有。 |
| 清單最上方出現「⚠ 無法讀取 N 個 session 檔」 | 有檔案持續解析失敗，多半是 Claude Code 更新後格式變了。 |
| 數字和實際不符 | 執行 `claude agents --json` 對照，它讀的是同一份資料。 |
| 選單列出現兩個圖示 | 同時開了兩份。執行 `./scripts/login-item.sh install` 會清掉多的那份。 |

## 開發

```bash
swift test                 # 單元測試
./scripts/build-app.sh     # 編譯並打包
```

```
Sources/ClaudeStatusCore/        純邏輯，不依賴 UI，由單元測試涵蓋
  Session.swift                  session 檔的資料模型與狀態分類
  SessionLoader.swift            解析目錄內容，處理寫到一半的檔案
  SessionTracker.swift           「跑完」標記的狀態機
Sources/ClaudeStatus/            選單列 app
  main.swift                     進入點
  SessionReader.swift            讀取與監看目錄、行程存活檢查
  StatusItemController.swift     圖示與下拉清單
  Jumper.swift                   跳轉到各來源的視窗
Tests/ClaudeStatusCoreTests/     單元測試
Resources/Info.plist             app bundle 設定
scripts/build-app.sh             編譯、打包、簽章
scripts/login-item.sh            安裝或移除登入時啟動
```
