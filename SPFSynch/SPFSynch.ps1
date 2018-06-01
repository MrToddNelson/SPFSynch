Add-PSSnapin "Microsoft.SharePoint.Powershell"

####################################################################################################################################################
# Local Variables - Update Variables as Needed for Environment

$ProductionDBInstance = "PRODDBINSTANCE,PORT"
$ProductionContentDBName = "ContentDatabase"
$DevelopmentDBInstance = "DEVDBINSTANCE,PORT"
$DevelopmentContentDBName = "ContentDatabase"
$SharedBackupLocation = "NetworkLocation"
$DevelopmentServerName = "DEVServerName"
$DevelopmentWebApplicationURL = "https://developmentsharepoint.yourcompany.com" 
$DevelopmentSiteLogoURL = "/Img/SPTestSiteLogo.png"

# Variables created from above; no need to modify.
$BackupFileNameWithLocation = $SharedBackupLocation + $ProductionContentDBName + ".bak"
$PreRestoreSQL = "Alter Database [" + $DevelopmentContentDBName + "] SET RESTRICTED_USER WITH ROLLBACK IMMEDIATE;"
$UpdateSiteLogoSQL = "UPDATE [" + $DevelopmentContentDBName + "].[dbo].[AllWebs] SET [SiteLogoURl] = '" + $DevelopmentSiteLogoURL + "' WHERE 1=1;"
####################################################################################################################################################

#Backup Production Content Database
Write-Host "Backing Up (Copy-Only) Production Content Database..." 
Backup-SqlDatabase -ServerInstance $ProductionDBInstance -Database $ProductionContentDBName -BackupFile $BackupFileNameWithLocation -CopyOnly -Initialize -Checksum 
c:
Write-Host "Backup of Production Content Database Completed." 

#Dismount Development Content Database
Write-Host "Dismounting Content Database..." 
$ContentDatabase = Get-SPContentDatabase | WHERE {$_.Name -eq $DevelopmentContentDBName}
Dismount-SPContentDatabase -Identity $ContentDatabase.Id -Confirm:$false
Write-Host "Dismounted..." 

#Restore Production (Copy-Only) Content Database Backup to Development
Write-Host "Restoring Production Content Database Backup to Development..." 
Invoke-Sqlcmd -Query $PreRestoreSQL -ServerInstance $DevelopmentDBInstance 
Restore-SqlDatabase -ServerInstance $DevelopmentDBInstance -Database $DevelopmentContentDBName -BackupFile $BackupFileNameWithLocation
c:
Invoke-Sqlcmd -Query $UpdateSiteLogoSQL -ServerInstance $DevelopmentDBInstance 
Remove-Item -Path $BackupFileNameWithLocation
Write-Host "Restore of Production Content Database To Development Completed." 

#Mount Content Database
Write-Host "Mounting Content Database..." 
Mount-SPContentDatabase -Name $DevelopmentContentDBName -DatabaseServer $DevelopmentServerName -WebApplication $DevelopmentWebApplicationURL 
Write-Host "Content Datbase Mounted." 
#Upgrading Content Database
Write-Host "Upgrading Content Database..." 
psconfig -cmd upgrade -inplace b2b wait -cmd applicationcontent -install -cmd installfeatures -cmd secureresources -cmd services -install 
iisreset
Write-Host "Upgraded Content Database." 

#Reset Search Index
Write-Host "Resetting Search Service Application Index (will take a couple minutes to complete)..." 
(Get-SPEnterpriseSearchServiceApplication).reset($true, $true) 

#Reset the Incremental Crawl Schedule
Write-Host "Resetting the Incremental Crawl Schedule..." 
$SSA = Get-SPEnterpriseSearchServiceApplication -Identity "Search Service Application" 
$SPCS = $SSA | Get-SPEnterpriseSearchCrawlContentSource | WHERE {$_.Type -eq "SharePoint"} 
$SPCS | Set-SPEnterpriseSearchCrawlContentSource -ScheduleType Incremental -DailyCrawlSchedule -CrawlScheduleRunEveryInterval 1 -CrawlScheduleRepeatInterval 60 -CrawlScheduleRepeatDuration 720 -CrawlScheduleStartDateTime "5:00 AM" -Confirm:$false 
$SPCS.IncrementalCrawlSchedule 

#Get the Local SharePoint sites content source
$ContentSource = $SSA | Get-SPEnterpriseSearchCrawlContentSource -Identity "Local SharePoint sites" 
 
  #Check if Crawler is not already running
  if($ContentSource.CrawlState -eq "Idle")
        {
            Write-Host "Starting Full Crawl after waiting two minutes for site to startup..." 
            Start-Sleep -s 120
			$ContentSource.StartFullCrawl() 
		}
  else
		{
			Write-Host "Another Crawl is already running!" 
			Write-Host "NAME: ", $ContentSource.Name, " - ", $ContentSource.CrawlStatus 
		}