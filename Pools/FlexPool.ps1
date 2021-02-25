using module ..\Modules\Include.psm1

param(
    [PSCustomObject]$Wallets,
    [PSCustomObject]$Params,
    [alias("WorkerName")]
    [String]$Worker,
    [TimeSpan]$StatSpan,
    [String]$DataWindow = "avg",
    [Bool]$InfoOnly = $false,
    [Bool]$AllowZero = $false,
    [String]$StatAverage = "Minute_10"
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

#$Pool_Request = [PSCustomObject]@{}

$Pool_Divisor = 1e18

try {
    $Pool_HashRate = Invoke-RestMethodAsync "https://flexpool.io/api/v1/pool/hashrate" -tag $Name -cycletime 120
    $Pool_Workers = Invoke-RestMethodAsync "https://flexpool.io/api/v1/pool/workersOnline" -tag $Name -cycletime 120
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    Write-Log -Level Warn "Pool API ($Name) has failed. "
    return
}


$PoolBlocks_TotalPages = 0
$PoolBlocks_Page = 0

    while($PoolBlocks_Page -lt $PoolBlocks_TotalPages -or $PoolBlocks_Page -eq 0){
        try {
        $Pool_BlocksResult = Invoke-RestMethodAsync "https://flexpool.io/api/v1/pool/blocks?page=$PoolBlocks_Page" -retry 3 -retrywait 500 -tag $Name -cycletime 120
        }
        catch {
            if ($Error.Count){$Error.RemoveAt(0)}
            Write-Log -Level Warn "Pool Blocks API ($Name) has failed. "
            return
        }
        if($PoolBlocks_Page -eq 0){
            $Pool_Blocks_data = $Pool_BlocksResult.result
            $PoolBlocks_TotalPages = $Pool_BlocksResult.result.total_pages
        }else{
            $Pool_Blocks_data.data += $Pool_BlocksResult.result.data
        }
        $PoolBlocks_Page++;
    }

$Pool_Currency = "ETH"
$Pool_Algorithm = "Ethash"

$Pool_Coin = "ETH"
$Pool_Host = "flexpool.io"
$Pool_Algorithm_Norm = "Ethash"

$timestamp    = [int](Get-Date -UFormat %s)
$timestamp24h = $timestamp - 24*3600

$blocks = @($Pool_Blocks_data.data | Where-Object {$_.timestamp -gt $timestamp24h} | Select-Object timestamp,total_rewards,difficulty)

$blocks_measure = $blocks | Measure-Object timestamp -Minimum -Maximum
$avgTime        = if ($blocks_measure.Count -gt 1) {($blocks_measure.Maximum - $blocks_measure.Minimum) / ($blocks_measure.Count - 1)} else {$timestamp}
$Pool_BLK       = [int]$(if ($avgTime) {86400/$avgTime})
$Pool_TSL       = $timestamp - ($blocks | Measure-Object timestamp -Maximum).Maximum
$reward         = $(if ($blocks) {($blocks | Where-Object total_rewards | Measure-Object total_rewards -Average).Average} else {0})/$Pool_Divisor
$btcPrice       = if ($Global:Rates.$Pool_Currency) {1/[double]$Global:Rates.$Pool_Currency} else {0}

$btcRewardLive   = if ($Pool_HashRate.result.total -gt 0) {$btcPrice * $reward * 86400 / $avgTime / $Pool_HashRate.result.total} else {0}
$Divisor         = 1
$Hashrate        = $Pool_HashRate.result.total

$Stat = Set-Stat -Name "$($Name)_$($_.symbol)_Profit" -Value ($btcRewardLive/$Divisor) -Duration $StatSpan -ChangeDetection $false -HashRate $Hashrate -BlockRate $Pool_BLK -Quiet
if (-not $Stat.HashRate_Live -and -not $AllowZero) {return}

$Pool_Ports = @{
    4444 = $false
    5555 = $true
}


[hashtable]$Pool_RegionsTable = @{
    "us" = "eth-us-east"
    "useast" = "eth-us-east"
    "eu" = "eth-de"
    "asia" = "eth-sg"
    "au" = "eth-au"
    "sa" = "eth-sa"
}

$Pool_Regions = @("us","eu","asia","sa","au")
$Pool_Regions | Foreach-Object {$Pool_RegionsTable.$_ = Get-Region $_}

$Pool_Request.PSObject.Properties.Name | Where-Object {$_ -eq $Pool_Algorithm} | Foreach-Object {
    $Pool_PoolFee = 1.0
    $Pool_User = $Wallets.$Pool_Currency

    if ($Pool_User -or $InfoOnly) {
        foreach($Pool_Region in $Pool_Regions) {
            foreach($Pool_Port in $Pool_Ports) {
                [PSCustomObject]@{
                    Algorithm     = $Pool_Algorithm_Norm
                    Algorithm0    = $Pool_Algorithm_Norm
                    CoinName      = $Pool_Coin.Name
                    CoinSymbol    = $Pool_Currency
                    Currency      = $Pool_Currency
                    Price         = $Stat.$StatAverage #instead of .Live
                    StablePrice   = $Stat.Week
                    MarginOfError = $Stat.Week_Fluctuation
                    Protocol      = "stratum+$(if ($PoolPorts.$PoolPort) {"ssl"} else {"tcp"})"
                    Host          = "$($Pool_RegionsTable.$Pool_Region).$($Pool_Host)"
                    Port          = $Pool_Port
                    User          = "$($Pool_Wallet).{workername:$Worker}"
                    Pass          = ""
                    Region        = $Pool_Regions.$Pool_Region
                    SSL           = $PoolPorts.$PoolPort
                    Updated       = $Stat.Updated
                    PoolFee       = $Pool_PoolFee
                    DataWindow    = $DataWindow
                    Workers       = $Pool_Workers.result
                    Hashrate      = $Pool_HashRate.result
                    BLK           = $Stat.BlockRate_Average
                    TSL           = $Pool_TSL
				    ErrorRatio    = $Stat.ErrorRatio
                    EthMode       = "stratum"
                    Name          = $Name
                    Penalty       = 0
                    PenaltyFactor = 1
                    Disabled      = $false
                    HasMinerExclusions = $false
                    Price_Bias    = 0.0
                    Price_Unbias  = 0.0
                    Wallet        = $Wallets.$Pool_Currency
                    Worker        = "{workername:$Worker}"
                    Email         = $Email
                }
            }
        }
    }
}
