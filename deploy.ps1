# deploy.ps1
# 此腳本用於讀取 .env 環境變數，並執行 Foundry 部署與 Etherscan 合約驗證

# 確認 .env 檔案是否存在
if (Test-Path ".env") {
    Write-Host "讀取 .env 檔案中..." -ForegroundColor Cyan
    Get-Content .env | ForEach-Object {
        # 忽略註解與空白行
        if ($_ -match '^\s*[^#]' -and $_ -match '^(?<name>[^=]+)=(?<value>.*)$') {
            $name = $Matches.name.Trim()
            $value = $Matches.value.Trim()
            # 設置為目前的 Session 環境變數
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
} else {
    Write-Host "警告: 找不到 .env 檔案！請確保目錄下有 .env，並設定 PRIVATE_KEY, RPC_URL, ETHERSCAN_API_KEY" -ForegroundColor Red
    exit
}

Write-Host "開始部署 PerpetualYield 智能合約..." -ForegroundColor Green

# 執行 Foundry 部署腳本與驗證
forge script script/DeployPerpetualYield.s.sol:DeployPerpetualYield `
    --rpc-url $env:RPC_URL `
    --broadcast `
    --verify `
    --etherscan-api-key $env:ETHERSCAN_API_KEY

Write-Host "部署腳本執行結束。" -ForegroundColor Cyan