<#
.SYNOPSIS
  This script will get Azure Backup Jobs status of last 7 days from Recovery Services Vault from Tenants already logged in.

.PRE-CHECKS
  1. Install the Azure Powershell Module - https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-5.2.0
  2. Install ImportExcel Module
  3. Make sure to login Azure subscription before running script
  Example: Connect-AzAccount -Tenant 86xxx1bb-2xxf-4271-b174-bd59dxxx87a3 

.INPUTS
  NA

.OUTPUTS
  Generates output files in both CSV and EXCEL format at "C:\" location

.NOTES
  Version:        1.0
  Author:         Narasimha R Duggu/ duggu.narasimhareddy@gmail.com
  Creation Date:  20210108

.EXAMPLE
 powershell.exe -ExecutionPolicy ByPass -File .\AzDailyBackupJobs.ps1'

.EXAMPLE
.\AzDailyBackupJobs.ps1
#>


$report=@()
$Reporttime=(Get-Date).ToString('yyyy-MM-dd-hh-mm')
$AzSubs = (Get-AzSubscription).Name | ?{$_ -ne 'company_sub_name'} #If you want to exclude any scription
foreach($sub in $AzSubs){
    Select-AzSubscription -Subscription "$sub"
    
    #Get Recovery Services Vault
    $rv = Get-AzRecoveryServicesVault | Select-Object -Property Name,ResourceGroupName,ID,Location
    
    foreach($vault in $rv){
        $rvname = $vault.Name
        $rg = $vault.ResourceGroupName
        $rvid = $vault.ID
        $location = $vault.Location
        
        # Get the Tag Details
        $Tags = Get-AzTag -ResourceId $rvid | Select-Object -Property Properties
        $opco = $Tags.Properties.TagsProperty.opco
        $SAccounts = Get-AzRecoveryServicesBackupContainer -ContainerType AzureStorage -Status Registered -VaultId $rvid
        $Jobs = Get-AzRecoveryServicesBackupJob -Operation Backup -From (Get-Date).AddDays(-7).ToUniversalTime() -VaultId $rvid | select * #Select-Object -Property WorkloadName,Operation,Status,StartTime,EndTime
        
        # Get Storage Account Details
        foreach($sa in $SAccounts){
                       
            $Sharename = (Get-AzRecoveryServicesBackupItem -Container $sa -WorkloadType AzureFiles -VaultId $rvid).FriendlyName
            $saName = $sa.FriendlyName
            
            foreach($FileShare in $Sharename){
                echo $FileShare
                for ($counter=0; $counter -lt $Jobs.Length; $counter++){
                
                    $Operation = $Jobs.Get($counter).Operation
                    $Status = $Jobs.Get($counter).Status
                    $StartTime = $Jobs.Get($counter).StartTime
                    $EndTime = $Jobs.Get($counter).EndTime
                    $JobID = $Jobs.Get($counter).JobId
                    $WorkloadName = $Jobs.Get($counter).WorkloadName

                    if($FileShare -eq $WorkloadName){

                        $data = New-Object PSObject
                        $data | Add-Member NoteProperty opco -Value $opco
                        $data | Add-Member NoteProperty ResourceGroupName -Value $rg
                        $data | Add-Member NoteProperty Location -Value $location
                        $data | Add-Member NoteProperty RecoveryVault -Value $rvname
                        $data | Add-Member NoteProperty StorageAccount -Value $saName
                        $data | Add-Member NoteProperty WorkloadName -Value $WorkloadName
                        $data | Add-Member NoteProperty Operation -Value $Operation
                        $data | Add-Member NoteProperty Status -Value $Status
                        $data | Add-Member NoteProperty StartTime -Value $StartTime
                        $data | Add-Member NoteProperty EndTime -Value $EndTime
                        $report+=$data
                    }
                }
            }
        }
    }
}
$report | Export-Csv -Path C:\OpCo-DailyBackupJobsReport.csv
Import-Csv C:\OpCo-DailyBackupJobsReport.csv | Export-Excel -WorksheetName DailyBackupJobsReport "C:\OpCo-DailyBackupJobsReport-$Reporttime.xlsx" -DisplayPropertySet -TableName ServiceTable `
    -IncludePivotTable `
    -PivotRows 'OpCo','StorageAccount','WorkloadName' `
    -PivotColumns 'Status' `
    -PivotData @{Status='count'}
