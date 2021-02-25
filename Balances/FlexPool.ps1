using module ..\Modules\Include.psm1

param(
    $Config
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName
$PoolConfig = $Config.Pools.$Name

if (!$PoolConfig.ETH) {
    Write-Log -Level Verbose "Pool Balance API ($Name) has failed - no wallet address specified."
    return
}

if ($Config.ExcludeCoinsymbolBalances.Count -and $Config.ExcludeCoinsymbolBalances -contains "ETH") {return}

$Request = [PSCustomObject]@{}

$Flexpool_Host = "flexpool.io"

$Pool_Divisor = 1e18

$Success = $true
try {
    if (-not ($BalanceRequest = Invoke-RestMethodAsync "https://$($Flexpool_Host)/api/v1/miner/$($PoolConfig.ETH)/balance" -cycletime ($Config.BalanceUpdateMinutes*60))){$Success = $false}
    if (-not ($TotalRequest = Invoke-RestMethodAsync "https://$($Flexpool_Host)/api/v1/miner/$($PoolConfig.ETH)/totalPaid" -cycletime ($Config.BalanceUpdateMinutes*60))){$Success = $false}
}
catch {
    if ($Error.Count){$Error.RemoveAt(0)}
    $Success=$false
}

if (-not $Success) {
    Write-Log -Level Warn "Pool Balance API ($Name) has failed. "
    return
}

if (($BalanceRequest | Get-Member -MemberType NoteProperty -ErrorAction Ignore | Measure-Object Name).Count -le 1) {
    Write-Log -Level Info "Pool Balance API ($Name) returned nothing. "
    return
}

$Payments_TotalPages = 0
$Payments_Page = 0

    while($Payments_Page -lt $Payments_TotalPages -or $Payments_Page -eq 0){
        try {
        $PaymentsResult = Invoke-RestMethodAsync "https://$($Flexpool_Host)/api/v1/miner/$($PoolConfig.ETH)/payments?page=$Payments_Page" -retry 3 -retrywait 500 -tag $Name -cycletime 120
        }
        catch {
            if ($Error.Count){$Error.RemoveAt(0)}
            Write-Log -Level Warn "Pool Blocks API ($Name) has failed. "
            return
        }
        if($Payments_Page -eq 0){
            $Payments_data = $PaymentsResult.result
            $Payments_TotalPages = $PaymentsResult.result.total_pages
        }else{
            $Payments_data.data += $PaymentsResult.result.data
        }
        $Payments_Page++;
    }


[PSCustomObject]@{
        Caption     = "$($Name) (ETH)"
		BaseName    = $Name
        Currency    = "ETH"
        Balance     = [Decimal]$BalanceRequest.result / $Pool_Divisor
        Pending     = ""
        Total       = [Decimal]$BalanceRequest.result / $Pool_Divisor
        Paid        = [Decimal]$TotalRequest.result / $Pool_Divisor
        #Paid24h     = [Decimal]$Request.paid24h
        Earned      = ([Decimal]$BalaceRequest.result + [Decimal]$TotalRequest.result) / $Pool_Divisor
        Payouts     = @(Get-BalancesPayouts $Payments_data.data -Divisor $Pool_Divisor | Select-Object)
        LastUpdated = (Get-Date).ToUniversalTime()
}