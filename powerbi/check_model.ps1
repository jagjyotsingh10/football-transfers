<#
  Football Transfer ROI | check the Power BI model against SQL Server

  Open powerbi\FootballPortfolio.pbip in Power BI Desktop and click Refresh
  first. This script finds the model Power BI Desktop is hosting locally,
  runs DAX measures against it, and compares each with the same number
  calculated in SQL from the rpt views. Every row should say OK.

  Usage:  powershell -File powerbi\check_model.ps1
#>
param([string]$Server = "localhost\SQLEXPRESS")

$ErrorActionPreference = "Stop"
Add-Type -Path "C:\Program Files\Microsoft Power BI Desktop\bin\Microsoft.PowerBI.AdomdClient.dll"

# Power BI Desktop runs a local Analysis Services instance; its port is in the workspace folder
$portFile = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Power BI Desktop\AnalysisServicesWorkspaces\*\Data\msmdsrv.port.txt" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $portFile) { throw "No open Power BI model found. Open FootballPortfolio.pbip in Power BI Desktop first." }
$port = (Get-Content $portFile.FullName -Encoding Unicode -Raw).Trim()

$conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=localhost:$port")
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = 'SELECT [CATALOG_NAME] FROM $SYSTEM.DBSCHEMA_CATALOGS'
$r = $cmd.ExecuteReader(); [void]$r.Read(); $catalog = $r.GetValue(0); $r.Close()
$conn.ChangeDatabase($catalog)

function Dax([string]$expr) {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "EVALUATE ROW(""v"", $expr)"
    $r = $cmd.ExecuteReader(); [void]$r.Read(); $v = $r.GetValue(0); $r.Close()
    return [double]$v
}
function Sql([string]$query) {
    return [double](sqlcmd -S $Server -E -C -d FootballTransferROI -h -1 -W -Q "SET NOCOUNT ON; $query" | Select-Object -First 1)
}

$checks = @(
    @("Portfolio value, June 2026 (EUR)", "[Portfolio Value (latest)]",
      "SELECT SUM(total_value_eur) FROM rpt.vw_club_portfolio WHERE snapshot_year = 2026"),
    @("Growth since June 2020", "[Growth since June 2020]",
      "SELECT SUM(CASE WHEN snapshot_year = 2026 THEN total_value_eur END) / SUM(CASE WHEN snapshot_year = 2020 THEN total_value_eur END) - 1 FROM rpt.vw_club_portfolio"),
    @("Clubs, June 2026", "[Clubs (latest)]",
      "SELECT COUNT(*) FROM rpt.vw_club_portfolio WHERE snapshot_year = 2026"),
    @("Declining exposure, all years", "[Declining Exposure]",
      "SELECT SUM(declining_value_eur) / SUM(value_with_history_eur) FROM rpt.vw_club_portfolio"),
    @("Chelsea net spend (EUR)", "CALCULATE([Net Spend], 'Transfer Balance'[club_name] = ""Chelsea FC"")",
      "SELECT SUM(net_spend_eur) FROM rpt.vw_club_transfer_balance WHERE club_name = 'Chelsea FC'"),
    @("Paid signings", "[Paid Signings]", "SELECT COUNT(*) FROM rpt.vw_signing_appreciation"),
    @("Fee-to-value ratio, all deals", "[Fee-to-Value Ratio]",
      "SELECT SUM(fee_eur) / SUM(market_value_at_transfer_eur) FROM rpt.vw_fee_vs_value WHERE market_value_at_transfer_eur > 0"),
    @("Most valuable squad won the league", "[Title Rate (most valuable squad)]",
      "SELECT 1.0 * SUM(CASE WHEN position = 1 THEN 1 ELSE 0 END) / COUNT(*) FROM rpt.vw_value_vs_points WHERE value_rank = 1"),
    @("Club-seasons in value vs points", "COUNTROWS('Value vs Points')", "SELECT COUNT(*) FROM rpt.vw_value_vs_points")
)

$failed = 0
$rows = foreach ($c in $checks) {
    $pbi = Dax $c[1]; $sql = Sql $c[2]
    $ok = [math]::Abs($pbi - $sql) -le [math]::Max(1e-6, [math]::Abs($sql) * 1e-9)
    if (-not $ok) { $failed++ }
    [pscustomobject]@{ Check = $c[0]; PowerBI = [math]::Round($pbi, 4); SQL = [math]::Round($sql, 4); Result = $(if ($ok) { "OK" } else { "MISMATCH" }) }
}
$rows | Format-Table -AutoSize
$conn.Close()
Write-Output "Model: $catalog on port $port. $($checks.Count - $failed) of $($checks.Count) checks match."
if ($failed) { exit 1 }
