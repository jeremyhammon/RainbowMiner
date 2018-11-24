﻿param(
    $Config
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

$Request = [PSCustomObject]@{}

$Payout_Currencies = @()
if ((-not $Config.PoolName.Count -or $Config.PoolName -icontains $Name) -and (-not $Config.ExcludePoolName.Count -or $Config.ExcludePoolName -inotcontains $Name)) {$Payout_Currencies += @($Config.Pools.$Name.Wallets.PSObject.Properties | Select-Object)}
if ((-not $Config.PoolName.Count -or $Config.PoolName -icontains "$($Name)Coins") -and (-not $Config.ExcludePoolName.Count -or $Config.ExcludePoolName -inotcontains "$($Name)Coins")) {$Payout_Currencies += @($Config.Pools."$($Name)Coins".Wallets.PSObject.Properties | Select-Object)}
$Payout_Currencies = $Payout_Currencies | Select-Object Name,Value -Unique | Sort-Object Name,Value

if (-not $Payout_Currencies) {
    Write-Log -Level Verbose "Cannot get balance on pool ($Name) - no wallet address specified. "
    return
}

$Count = 0
$Payout_Currencies | Foreach-Object {
    try {
        $Request = Invoke-RestMethodAsync "https://nlpool.nl/api/walletEx?address=$($_.Value)" -delay $(if ($Count){500} else {0}) -cycletime ($Config.BalanceUpdateMinutes*60)
        $Count++
        if (($Request | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
            Write-Log -Level Info "Pool Balance API ($Name) for $($_.Name) returned nothing. "
        } else {
            [PSCustomObject]@{
                Caption     = "$($Name) ($($Request.currency))"
                Currency    = $Request.currency
                Balance     = $Request.balance
                Pending     = $Request.unsold
                Total       = $Request.unpaid
                Payed       = $Request.total - $Request.unpaid
                Earned      = $Request.total
                Payouts     = @($Request.payouts | Select-Object)
                LastUpdated = (Get-Date).ToUniversalTime()
            }
        }
    }
    catch {
        if ($Error.Count){$Error.RemoveAt(0)}
        Write-Log -Level Warn "Pool Balance API ($Name) for $($_.Name) has failed. "
    }
}
