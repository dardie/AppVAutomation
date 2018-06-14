﻿function Get-MSICMD {
Param($XML)

    $MSIFile = $XML.Application.Type.MSIFile
    $TRANSFORMS = $XML.Application.Type.Transforms
    $REBOOT = $XML.Application.Type.RebootSuppression
    If ($REBOOT -eq "Force") { $RequiresReboot = $True } Else {$RequiresReboot = $False}
    If ($XML.Application.Type.Context -eq "System" ) {
        $LogfilePath = "C:\Windows\AppLog\$($XML.Application.Name)-Install.log"
        $AppExecutionContext = "System"
        $RequiresUserInteraction = $False
    } Else {
        $LogfilePath = "%temp%\$($XML.Application.Name)-Install.log"
        $AppExecutionContext = "User"

    }
    If ($XML.Application.Type.Logfile -eq "Enabled") { 
        $Switches = "/l* ""$LogfilePath"""
    }
    Switch ($XML.Application.Type.Interface) {
        Silent { $Switches = "$Switches /qn" }
        Basic { $Switches = "$Switches /qb"; }
        Default { $Switches = "$Switches";}
    }
    Switch ($XML.Application.Type.RequiresUserInteraction) {
        True { $RequiresUserInteraction = $True }
        False { $RequiresUserInteraction = $False }
        Default { $RequiresUserInteraction = $False }
    }
    Switch ($XML.Application.Type.RequiresLogon) {
        True { $RequiresLogon = $True }
        False { $RequiresLogon = $False }
        Default { $RequiresLogon = $null }
    }
    $InstallCommand = "msiexec /i ""$MSIFile"" TRANSFORMS=""$TRANSFORMS"" REBOOT=$REBOOT $Switches"

    If ($XML.Application.Type.Context -eq "System" ) {
        $LogfilePath = "C:\Windows\AppLog\$($XML.Application.Name)-Uninstall.log"
    } Else {
        $LogfilePath = "%temp%\$($XML.Application.Name)-Uninstall.log"
    }
    If ($XML.Application.Type.Logfile -eq "Enabled") { 
        $Switches = "/l* ""$LogfilePath"""
    }
    Switch ($XML.Application.Type.Interface) {
        Silent { $Switches = "$Switches /qn" }
        Basic { $Switches = "$Switches /qb" }
        Default { $Switches = "$Switches" }
    }
    $ProductCode = $XML.Application.Type.ProductCode
    $UninstallCommand = "msiexec /x $ProductCode REBOOT=$REBOOT $Switches"
    $Context = 
    $MSIObject = New-Object -TypeName psobject -Property @{
        'InstallCommand' = $InstallCommand
        'UninstallCommand' = $UninstallCommand
        'RequiresLogon' = $RequiresLogon
        'RequiresReboot' = $RequiresReboot
        'ExecutionContext' = $AppExecutionContext
        'ProductCode' = $XML.Application.Type.ProductCode
        'RequiresUserInteraction' = $RequiresUserInteraction
    }
    return $MSIObject
}




    function New-Collection {
    Param(
        $Type,
        $ColName,
        $ADGroup,
        $AppName,
        $WKSLimitingCollectionName='All USC Managed Computers',
        $USRLimitingCollectionName='All USC Staff and Student Users',
        $Domain='USC'
    )
    
        function Get-UserAppVUninstallQ {
        Param($AppName,$ADGroup,$Domain)
            return "select SMS_R_USER.ResourceID,SMS_R_USER.ResourceType,SMS_R_USER.Name,SMS_R_USER.UniqueUserName,SMS_R_USER.WindowsNTDomain from SMS_R_User inner join SMS_G_System_AppClientState  on SMS_R_USER.UniqueUserName = SMS_G_System_AppClientState.UserName  where SMS_G_System_AppClientState.AppName=""$AppName"" and G_System_AppClientState.ComplianceState = 1 and SMS_R_USER.UniqueUserName not in (select distinct SMS_R_USER.UniqueUserName from SMS_R_User where UserGroupName = ""$Domain\\$ADGroup"")"
        }

        function Get-MachineAppVUninstallQ {
        Param($AppName,$ADGroup,$Domain)
            return "select SMS_R_SYSTEM.ResourceID from SMS_R_SYSTEM inner join SMS_G_System_AppClientState  on SMS_R_SYSTEM.ResourceID = SMS_G_System_AppClientState.ResourceId  where SMS_G_System_AppClientState.AppName=""$AppName"" and SMS_G_System_AppClientState.ComplianceState = 1 and SMS_R_SYSTEM.ResourceID not in (select distinct SMS_R_SYSTEM.ResourceID from SMS_R_SYSTEM where SystemGroupName = ""$Domain\\$ADGroup"")"
        }

        $StartLoc = Get-Location
        Set-Location SC1:\
        $DailySchedule = New-CMSchedule -RecurCount 1 -RecurInterval Days -Start (Get-Date "Friday, 25 October 2013 3:05:00 AM") -DurationInterval Days -DurationCount 0
        $HourlySchedule = New-CMSchedule -RecurCount 1 -RecurInterval Hours -Start (Get-Date "Friday, 25 October 2013 3:05:00 PM") -DurationInterval Days -DurationCount 0
            
        Switch ($Type) {
            "WKS" {
                $Query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.SystemGroupName = ""$Domain\\$ADGroup"""
                $Collection = Get-CMDeviceCollection -Name $ColName
                If (!$Collection) {
                    Write-Output "Creating collection $ColName"
                    $Collection = New-CMCollection -CollectionType Device -Name "$ColName" -LimitingCollectionName $WKSLimitingCollectionName #-RefreshType Continuous
                    If ($? -eq $False) { Write-Output "Failed to Create Collection"; return 1}
                    Write-Output "Created collection $ColName"
                }
                Write-Output "Sleeping..."
                Start-Sleep -Seconds 10
                Write-Output "Checking membership rule for collection $ColName"
                $ColQuery = $Collection.CollectionRules
                If (!$ColQuery -and $ADGroup) {
                    #Add Membership Rule
                    Write-Output "Adding membership rule to collection $ColName"
                    $ColQuery = Add-CMDeviceCollectionQueryMembershipRule -CollectionId $Collection.CollectionID -QueryExpression $Query -RuleName $Type
                    If ($? -eq $False) { Write-Output "Failed to add Query rule"; return 1}
                    Write-Output "Created query for $($Collection.Name) collection"
                }
            }
            "USR" {
                $Query = "select SMS_R_USER.ResourceID,SMS_R_USER.ResourceType,SMS_R_USER.Name,SMS_R_USER.UniqueUserName,SMS_R_USER.WindowsNTDomain from SMS_R_User where SMS_R_User.UserGroupName = ""$Domain\\$ADGroup"""
                $Collection = Get-CMUserCollection -Name $ColName
                If (!$Collection) {
                    Write-Output "Creating user collection $ColName limited to $USRLimitingCollectionName"
                    $Collection = New-CMCollection -CollectionType User -Name "$ColName" #-RefreshType Continuous -LimitingCollectionName $USRLimitingCollectionName
                    If ($? -eq $False) { Write-Output "Failed to Create Collection"; return 1}
                    Write-Output "Created collection $ColName"
                }
                Write-Output "Sleeping..."
                Start-Sleep -Seconds 10
                Write-Output "Checking membership rule for collection $ColName"
                $ColQuery = $Collection.CollectionRules
                If (!$ColQuery -and $ADGroup) {
                    #Add Membership Rule
                    Write-Output "Adding membership rule to collection $ColName"
                    $ColQuery = Add-CMUserCollectionQueryMembershipRule -CollectionId $Collection.CollectionID -QueryExpression $Query -RuleName $Type
                    If ($? -eq $False) { Write-Output "Failed to add Query rule"; return 1}
                    Write-Output "Created query for $($Collection.Name) collection"
                }
            }
            "USR-Uninstall" {
                $Query = (Get-UserAppVUninstallQ -AppName $AppName -ADGroup $ADGroup -Domain $Domain)
                New-Alias -Name AddRule -Value Add-CMUserCollectionQueryMembershipRule -Force #-Scope Global -Force
                $Collection = Get-CMUserCollection -Name $ColName
                If (!$Collection) {
                    Write-Output "Creating collection $ColName"
                    $Collection = New-CMUserCollection -Name "$ColName" -RefreshSchedule $DailySchedule -LimitingCollectionName $USRLimitingCollectionName
                    If ($? -eq $False) { Write-Output "Failed to Create Collection"; return 1}
                    Write-Output "Created collection $ColName"
                }
                Write-Output "Sleeping..."
                Start-Sleep -Seconds 10
                Write-Output "Checking membership rule for collection $ColName"
                $ColQuery = $Collection.CollectionRules
                If (!$ColQuery -and $ADGroup) {
                    #Add Membership Rule
                    Write-Output "Adding membership rule to collection $ColName"
                    $ColQuery = Add-CMUserCollectionQueryMembershipRule -CollectionId $Collection.CollectionID -QueryExpression $Query -RuleName $Type
                    If ($? -eq $False) { Write-Output "Failed to add Query rule"; return 1}
                    Write-Output "Created query for $($Collection.Name) collection"
                }
            }
            "WKS-Uninstall" {
                $Query = (Get-MachineAppVUninstallQ -AppName $AppName -ADGroup $ADGroup -Domain $Domain)
                $Collection = Get-CMDeviceCollection -Name $ColName
                If (!$Collection) {
                    Write-Output "Creating collection $ColName"
                    $Collection = New-CMDeviceCollection -Name "$ColName" -RefreshSchedule $DailySchedule -LimitingCollectionName $WKSLimitingCollectionName
                    If ($? -eq $False) { Write-Output "Failed to Create Collection"; return 1}
                    Write-Output "Created collection $ColName"
                }
                Write-Output "Sleeping..."
                Start-Sleep -Seconds 10
                Write-Output "Checking membership rule for collection $ColName"
                $ColQuery = $Collection.CollectionRules
                If (!$ColQuery -and $ADGroup) {
                    #Add Membership Rule
                    Write-Output "Adding membership rule to collection $ColName"
                    $ColQuery = Add-CMDeviceCollectionQueryMembershipRule -CollectionId $Collection.CollectionID -QueryExpression $Query -RuleName $Type
                    If ($? -eq $False) { Write-Output "Failed to add Query rule"; return 1}
                    Write-Output "Created query for $($Collection.Name) collection"
                }
            }
        }
    Set-Location $StartLoc
    }

    function New-AppFromTemplate {
        [CmdLetBinding()]
        Param($Name,$Publisher,$Version,$SiteCode='SC1',$Description)
        
        $StartLoc = $PWD
        #Check if a template exists
        Set-Location -Path ${SiteCode}:\
        $SourceApp = Get-CMApplication -Name "$Name Template"
        If ($SourceApp) {
            # Get bits from the source application to save into the new 
            Set-Location $StartLoc
            $TempIcon = New-Item -Path $Env:Temp -Name "$(Get-Random).png" -ItemType File
            $App = [xml]($SourceApp.SDMPackageXML)
            [IO.File]::WriteAllBytes($TempIcon,
                    [convert]::FromBase64String($App.AppMgmtDigest.Resources.Icon.Data))
            $Tags = $App.AppMgmtDigest.Application.DisplayInfo.Info.Tags.Tag
            $LinkText = $App.AppMgmtDigest.Application.DisplayInfo.Info.InfoURLText
            $UserDocumentation = $App.AppMgmtDigest.Application.DisplayInfo.Info.InfoURL
            $Description = $App.AppMgmtDigest.Application.DisplayInfo.Info.Description
            $PrivacyURL = $App.AppMgmtDigest.Application.DisplayInfo.Info.PrivacyURL
            $SupportContact = $App.AppMgmtDigest.Application.Contacts.User.Id
            $Owner = $App.AppMgmtDigest.Application.Owners.User.Id
            $OptionalReference = $App.AppMgmtDigest.Application.CustomId.'#text'
            # Build Hash Table for PS Blatting
            $AppSettings = @{
                'Description' = $SourceApp.LocalizedDescription
                'IconLocationFile' = $TempIcon
                'Keyword' = $Tags
                'LinkText' = $LinkText
                'LocalizedDescription' = $Description
                'LocalizedName' = "$Name $Version"
                'Name' = "$Name $Version"
                'Owner' = $Owner
                'PrivacyUrl' = $PrivacyUrl
                'Publisher' = $SourceApp.Manufacturer
                'ReleaseDate' = Get-Date
                'SoftwareVersion' = $Version
                'SupportContact' = $SupportContact
                'UserDocumentation' = $UserDocumentation
                'OptionalReference' = $OptionalReference
            }
            $ValidAppSettings = @{}
            $AppSettings.Keys | ForEach-Object {
                If ($AppSettings[$_]) {
                    $ValidAppSettings.Add($_,$AppSettings[$_])
                }
            }
            Set-Location ${SiteCode}:\
            Write-Host "Creating $Name $Version from Template App"
            $NewApp = New-CMApplication @ValidAppSettings
            Set-Location $StartLoc
        } Else {
            Write-Host "No template found, creating from scratch"
            $NewApp = New-CMApplication -Publisher $Publisher `
                -Name "$Name $Version" `
                -SoftwareVersion $Version `
                -Description $Description
        }
        return $NewApp
    }

    function New-Appv5Package {
        Param($Source,$Publisher,$Name,$Version,$Description,$PackageDest,$SiteCode='SC1')
        If (!(Test-Path -Path "$PackageDest\$($Source.Name)")) {
            Write-Output "Copying source to Package store"
            Copy-Item -Path $Source.FullName -Destination $PackageDest -Force -Recurse
        }

        $StartLoc = $PWD
        #"$PackageDest\$($Source.Name)" 
        $AppVFile = Get-ChildItem -Path "$PackageDest\$($Source.Name)" -Filter *.appv -Recurse
        If ($AppVFile) {
            Set-Location -Path ${SiteCode}:\
            $Application = Get-CMApplication -Name "$Name $Version"
            Set-Location -Path $StartLoc
            If (!$Application) {
                Write-Output "Creating application $Name $Version"
                $Application = New-AppFromTemplate -Publisher $Publisher -Name $Name -Version $Version -Description $Description -SiteCode $SiteCode
                Write-Output "Created application $Name $Version"
            }
            Write-Output "Sleeping..."
            Start-Sleep -Seconds 10
            Set-Location -Path ${SiteCode}:\
            $Deployment = Get-CMDeploymentType -ApplicationName $Application.LocalizedDisplayName
            If (!$Deployment) {
                Write-Output "Adding deployment type APPV5 for $($Application.LocalizedDisplayName) for file $($AppVFile.FullName)"
                Add-CMAppv5XDeploymentType -ApplicationName $Application.LocalizedDisplayName -Comment "AppV 5 Converted" `
                    -ContentLocation $AppVFile.FullName -FastNetworkDeploymentMode DownloadContentForStreaming `
                    -SlowNetworkDeploymentMode DownloadContentForStreaming 
                <#Add-CMDeploymentType -ApplicationName $Application.LocalizedDisplayName -AppV5xInstaller -ForceForUnknownPublisher $True `
                    -InstallationFileLocation $AppVFile.FullName -AdministratorComment "AppV 5 Converted"
                Write-Output "Setting application for Streaming"
                Set-CMApplicationXML -ApplicationName $Application.LocalizedDisplayName -OnFastNetwork DownloadContentForStreaming #>
                Write-Output "Created deployment type for $Name $Version"
                Write-Output "Setting Application default security scopes $Name $Version"
                Add-CMObjectSecurityScope -Name "Client Services" -InputObject (Get-CMApplication -Name "$Name $Version")
                Try {
                    Remove-CMObjectSecurityScope -Name "Default" -InputObject (Get-CMApplication -Name "$Name $Version") -Force
                } Catch {
                    Write-Output "Security scopes might already be set"
                }

            }
        } Else {
            Write-Output "Could not find APPVFile"
        }

    }

        function New-MSIPackage {
        Param($Source,$Publisher,$Name,$Version,$Description,$PackageDest,$Descriptor)
        If (!(Test-Path -Path "$PackageDest\$($Source.Name)")) {
            Write-Output "Copying source to Package store"
            Copy-Item -Path $Source.FullName -Destination $PackageDest -Force -Recurse
        }

        $MSIFile = "$PackageDest\$($Source.Name)\$($Descriptor.Application.Type.MSIFile)"
        Write-Output $MSIFile
        #$UninstallCMD = $XML.Application.Type.UninstallCMD

        Set-Location -Path SC1:\
        $Application = Get-CMApplication -Name $Name
        If (!$Application) {
            Write-Output "Creating application $Name"
            $Application = New-AppFromTemplate -Name $Name -Publisher $Publisher -Version $Version -Description $Description
            Write-Output "Created application $Name"
        }
        Write-Output "Sleeping..."
        Start-Sleep -Seconds 10
        $Deployment = Get-CMDeploymentType -ApplicationName $Application.LocalizedDisplayName
        If (!$Deployment) {
            Write-Output "Adding deployment type MSI for $($Application.LocalizedDisplayName)"
            ### TODO ###
            # Update with newer add-cmmsideploymenttype cmdlet. May make
            # Set-CMApplicationXML redundant
                Add-CMMsiDeploymentType - ApplicationName $Application.LocalizedDisplayName `
                    -ContentLocation $MSIFile `
                    -AdministratorComment "Imported with APPVPackage XML" `
                    -ForceForUnknownPublisher $True -DeploymentTypeName "$Name MSI"
                Set-CMApplicationXML -ApplicationName $Application.LocalizedDisplayName -XMLUpdate (Get-MSICMD -XML $Descriptor)
        }
    }

    <#
took some input for this script from http://blogs.msdn.com/b/one_line_of_code_at_a_time/archive/2012/01/17/microsoft-system-center-configuration-manager-2012-package-conversion-manager-plugin.aspx

This script can change some basic settings for ConfigMgr 2012 Applications or their DeploymentTypes.
In this version I can set some basic stuff regarding content behaviour.

You can, as an alternative, always try the Set-CMDeploymentType, but that one has a bug regarding the Fallback to unprotected DPs.

#>
function Set-CMApplicationXML {
    param(
    [string]$SiteCode="SC1",
    [string]$MPServer="wsp-ConfigMgr01",
    [string]$ApplicationName,
    [string]$OnFastNetwork,
    $XMLUpdate
    )

    function Get-ExecuteWqlQuery($siteServerName, $query)
    {
      $returnValue = $null
      $connectionManager = new-object Microsoft.ConfigurationManagement.ManagementProvider.WqlQueryEngine.WqlConnectionManager
  
      if($connectionManager.Connect($siteServerName))
      {
          $result = $connectionManager.QueryProcessor.ExecuteQuery($query)
      
          foreach($i in $result.GetEnumerator())
          {
            $returnValue = $i
            break
          }
      
          $connectionManager.Dispose() 
      }
  
      $returnValue
    }

    function Get-ApplicationObjectFromServer($appName,$siteServerName)
    {    
        $resultObject = Get-ExecuteWqlQuery $siteServerName "select thissitecode from sms_identification" 
        $siteCode = $resultObject["thissitecode"].StringValue
    
        $path = [string]::Format("\\{0}\ROOT\sms\site_{1}", $siteServerName, $siteCode)
        $scope = new-object System.Management.ManagementScope -ArgumentList $path
    
        $query = [string]::Format("select * from sms_application where LocalizedDisplayName='{0}' AND ISLatest='true'", $appName.Trim())
    
        $oQuery = new-object System.Management.ObjectQuery -ArgumentList $query
        $obectSearcher = new-object System.Management.ManagementObjectSearcher -ArgumentList $scope,$oQuery
        $applicationFoundInCollection = $obectSearcher.Get()    
        $applicationFoundInCollectionEnumerator = $applicationFoundInCollection.GetEnumerator()
    
        if($applicationFoundInCollectionEnumerator.MoveNext())
        {
            $returnValue = $applicationFoundInCollectionEnumerator.Current
            $getResult = $returnValue.Get()        
            $sdmPackageXml = $returnValue.Properties["SDMPackageXML"].Value.ToString()
            [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($sdmPackageXml)
        }
    }


     function Load-ConfigMgrAssemblies()
     {
        If (Test-Path -Path 'C:\Program Files (x86)') {
            $ProgramFiles = 'C:\Program Files (x86)'
        } Else {
            $ProgramFiles = 'C:\Program Files'
        }
         $AdminConsoleDirectory = "$ProgramFiles\Microsoft Configuration Manager\AdminConsole\bin"
         $filesToLoad = "Microsoft.ConfigurationManagement.ApplicationManagement.dll","AdminUI.WqlQueryEngine.dll", "AdminUI.DcmObjectWrapper.dll" 
     
         Set-Location $AdminConsoleDirectory
         [System.IO.Directory]::SetCurrentDirectory($AdminConsoleDirectory)
     
          foreach($fileName in $filesToLoad)
          {
             $fullAssemblyName = [System.IO.Path]::Combine($AdminConsoleDirectory, $fileName)
             if([System.IO.File]::Exists($fullAssemblyName ))
             {   
                 $FileLoaded = [Reflection.Assembly]::LoadFrom($fullAssemblyName )
             }
             else
             {
                  Write-Output ([System.String]::Format("File not found {0}",$fileName )) -backgroundcolor "red"
             }
          }
     }

    Load-ConfigMgrAssemblies

    $application = [wmi](Get-WmiObject -ComputerName $MPServer SMS_Application -Namespace root\sms\site_$($SiteCode) |  where {($_.LocalizedDisplayName -eq "$($ApplicationName)") -and ($_.IsLatest)}).__PATH

    $applicationXML = Get-ApplicationObjectFromServer "$($ApplicationName)" $MPServer


    if ($applicationXML.DeploymentTypes -ne $null)
        { 
            foreach ($a in $applicationXML.DeploymentTypes)
                {
                    If ($OnFastNetwork) {
                        $a.Installer.Contents[0].OnFastNetwork = $OnFastNetwork # can be "Download" or "DoNothing"
                    }
                    If ($XMLUpdate) {
                        Write-Output "Updating Commandline to $($XMLUpdate.InstallCommand)"
                        $a.Installer.InstallCommandLine = $XMLUpdate.InstallCommand
                        Write-Output "Updating ExecutionContext to $($XMLUpdate.ExecutionContext)"
                        $a.Installer.ExecutionContext = $XMLUpdate.ExecutionContext
                        Write-Output "Updating RequiresLogon to $($XMLUpdate.RequiresLogon)"
                        $a.Installer.RequiresLogOn = $XMLUpdate.RequiresLogOn
                        Write-Output "Updating RequiresReboot to $($XMLUpdate.RequiresReboot)"
                        $a.Installer.RequiresReboot = $XMLUpdate.RequiresReboot
                        Write-Output "Updating UninstallCommand to $($XMLUpdate.UninstallCommand)"
                        $a.Installer.UninstallCommandLine = $XMLUpdate.UninstallCommand
                    }
                }
        }

    $newappxml = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::Serialize($applicationXML, $false)

    $application.SDMPackageXML = $newappxml
    $application.Put() | Out-Null
}
