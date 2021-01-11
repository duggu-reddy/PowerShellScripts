<#
.SYNOPSIS
  This script will get Azure Storage accounts File Share Sync Status from Tenants already logged in.

.PRE-CHECKS
  1. Install the Azure Powershell Module - https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-5.2.0
  2. Install ImportExcel Module
  3. Make sure to login Azure subscription before running script
    Example: Connect-AzAccount -Tenant 86xxx1bb-2xxf-4271-b174-bd59dxxx87a3 

.INPUTS
  NA

.OUTPUTS
  Generates output files in both CSV and HTML format at "C:\" location

.NOTES
  Version:        2.0
  Author:         Narasimha R Duggu/ Narduggu@in.ib.com
  Creation Date:  20201212

.EXAMPLE
 powershell.exe -ExecutionPolicy ByPass -File .\AzureSyncStatus.ps1'

.EXAMPLE
.\AzureSyncStatus.ps1'
#>

$Reporttime=(Get-Date).ToString('yyyy-MM-dd-hh-mm')
$report=@()
$AzSubs = (Get-AzSubscription).Name | ?{$_ -ne 'KT-SHARED-StorSimpleGL'}
foreach($sub in $AzSubs){
    Select-AzSubscription -Subscription "$sub"
    $listss = Get-AzResource -ResourceType Microsoft.StorageSync/storageSyncServices | Select-Object -Property Name,ResourceGroupName
    foreach($line in $listss){
        echo $line
        $ss = $line.Name
        $rgName = $line.ResourceGroupName
        $ssg = Get-AzStorageSyncGroup -ResourceGroupName $rgName -StorageSyncServiceName $ss | Select-Object -Property SyncGroupName
        foreach($isg in $ssg){
            $sg = $isg.SyncGroupName
            
            # Get Registered Server End point with LocalPath Details
            $SyncData = Get-AzStorageSyncServerEndpoint -ResourceGroupName $rgName -StorageSyncServiceName $ss -SyncGroupName $sg
            $path = $SyncData.ServerLocalPath
            $provisionStatus = $SyncData.ProvisioningState
            $ServerName = $SyncData.FriendlyName
            $CloudTiering = $SyncData.CloudTiering
            $VolumeFreeSpacePercent = $SyncData.VolumeFreeSpacePercent
            
            #Get Sync Status with details
            $SStatus = (Get-AzStorageSyncServerEndpoint -ResourceGroupName $rgName -StorageSyncServiceName $ss -SyncGroupName $sg).SyncStatus
            $TotalUploadActivity = [math]::Round($SStatus.UploadActivity.TotalBytes/1GB,2)
            $AppliedUploadActivity = [math]::Round($SStatus.UploadActivity.AppliedBytes/1GB,2)
            $SyncActivity = $SStatus.SyncActivity
            if($SyncActivity -eq $null) 
                {
                    $SyncActivity = 'Completed'        
                }
            elseif (($SyncActivity -eq 'Upload' -or $SyncActivity -eq 'UploadAndDownload') -and $TotalUploadActivity -ne 0 )
                {
                    $SyncActivity = 'Upload In Progress'
                }
            elseif (($SyncActivity -eq 'Upload' -or $SyncActivity -eq 'UploadAndDownload') -and $TotalUploadActivity -eq 0 )
                                {
                    $SyncActivity = 'Download In Progress'
                }
            $PendingUploadActivity = $TotalUploadActivity - $AppliedUploadActivity
            $LastSync = $SStatus.LastUpdatedTimestamp
            
            # Get Storage account and Azure File Share details
            $StorageDetails = Get-AzStorageSyncCloudEndpoint -ResourceGroupName $rgName -StorageSyncServiceName $ss -SyncGroupName $sg
            $FileShare = $StorageDetails.AzureFileShareName
            $StorageAccount = $StorageDetails.StorageAccountResourceId.Split("/")[8]
            
            ## Get Tagging Details
            $Tags = Get-AzTag -ResourceId $StorageDetails.StorageAccountResourceId | Select-Object -Property Properties
            $opco = $Tags.Properties.TagsProperty.opco
            $data = New-Object PSObject
            $data | Add-Member NoteProperty OpCo -Value $opco
            $data | Add-Member NoteProperty ServerName -Value $ServerName
            $data | Add-Member NoteProperty StorageAccount -Value $StorageAccount
            $data | Add-Member NoteProperty ResourceGroupName -Value $rgName
            $data | Add-Member NoteProperty StorageSyncServiceName -Value $ss
            $data | Add-Member NoteProperty StorageSyncGroupName -Value $sg
            $data | Add-Member NoteProperty ServerLocalPath -Value $path
            $data | Add-Member NoteProperty AzureFileShareName -Value $FileShare
            $data | Add-Member NoteProperty ServerEndPointHealth -Value $provisionStatus
            $data | Add-Member NoteProperty SyncActivity -Value $SyncActivity
            $data | Add-Member NoteProperty LastUploadedTimestamp -Value $LastSync.ToString()
            $data | Add-Member NoteProperty TotalUploadActivity -Value $TotalUploadActivity
            $data | Add-Member NoteProperty AppliedUploadActivity -Value $AppliedUploadActivity
            $data | Add-Member NoteProperty PendingUploadActivity -Value $PendingUploadActivity
            $data | Add-Member NoteProperty CloudTiering -Value $CloudTiering
            $data | Add-Member NoteProperty VolumeFreeSpacePercent -Value $VolumeFreeSpacePercent
            $report+=$data
        }
    }
}
$report | Export-Csv -Path C:/output.csv
<# Incase if the sync report requires in HTML Format (Summary is not included)
$htmlformat  = '<title>Table</title>'
$htmlformat += '<style type="text/css">'
$htmlformat += 'BODY{background-color:#fff000;color:black;font-family:Arial Narrow,sans-serif;font-size:17px;}'
$htmlformat += 'TABLE{border-width: 3px;border-style: solid;border-color: black;border-collapse: collapse;}'
$htmlformat += 'TH{border-width: 1px;padding: 3px;border-style: solid;border-color: black;background-color:white}'
$htmlformat += 'TD{border-width: 1px;padding: 8px;border-style: solid;border-color: black;background-color:white}'
$htmlformat += '</style>'
$bodyformat = '<h1>Table</h1>'
Import-Csv -Delimiter ',' 'C:/output.csv' |ConvertTo-Html -Head $htmlformat -Body "<h1>Sync Report</h1>`n<h5>Generated on $(Get-Date)</h5>" | Out-File C:\htmlfile.html
#>

# Prepare Pivot Table
Import-Csv C:\output.csv | Export-Excel -WorksheetName SyncReport "C:\OpCo-SyncReport-$Reporttime.xlsx" -DisplayPropertySet -TableName ServiceTable `
    -IncludePivotTable `
    -PivotRows 'OpCo','ServerName' `
    -PivotColumns 'SyncActivity' `
    -PivotData @{SyncActivity='count'}