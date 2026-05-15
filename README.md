## PerpetualYield

### 功能概述

- ERC20 代幣，代幣餘額在寬限期後會依時間做指數衰減。
- 兼容 ERC3156 Flash Lender，可借出本合約代幣並收取手續費。
- 交易/鑄造/銷毀時會更新帳戶活動時間並結算衰減。

### 主要參數與常數

- `GRACE_PERIOD`：7 days，寬限期內餘額不衰減。
- `DECAY_PER_SECOND_RATE`：每秒衰減比率（以 1e27 為精度）。
- `RATE`：1e27，內部高精度倍率。
- `flashFeeBps`：Flash Loan 手續費，預設 100（1%）。
- `decimals`：18。

### 介面/方法清單

- `totalSupply()`：回傳總供給。
- `balanceOf(account)`：回傳經過衰減後的有效餘額。
- `transfer(to, amount)` / `transferFrom(from, to, amount)`：轉帳並同步更新衰減。
- `approve(spender, amount)` / `allowance(owner, spender)`：標準 ERC20 授權。
- `maxFlashLoan(token)`：僅支援本合約代幣，其他回傳 0。
- `flashFee(token, amount)`：計算 Flash Loan 手續費。
- `flashLoan(receiver, token, amount, data)`：執行 Flash Loan，要求回呼成功且已授權還款。
- `externalMint(to, amount)`：僅 owner 可鑄造。
- `externalBurn(from, amount)`：僅 owner 可銷毀。
- `setFlashFeeBps(newFeeBps)`：僅 owner 可設定手續費，上限 1000 bps（10%）。

### 權限與安全

- `externalMint`、`externalBurn`、`setFlashFeeBps` 受 `onlyOwner` 限制。
- `flashLoan` 使用 `nonReentrant` 防重入。
- 僅允許對本合約代幣進行 Flash Loan；回呼需回傳固定 `CALLBACK_SUCCESS`。
- Flash Loan 必須先 `approve` 足額還款（本金 + 手續費）。

### 函數細節

- `balanceOf` 會即時計算衰減，但實際 `_balances` 與 `_totalSupply` 只在交易/鑄造/銷毀時更新。
- `lastActivity` 只在 `transfer`/`mint`/`burn` 更新，不會因 `approve` 或 `balanceOf` 更新。


