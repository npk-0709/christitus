<#
.NOTES
    Author         : N P K
    Runspace Author: @NpkDeveloper
    GitHub         : https://github.com/npk-0709
    Version        : 24.04.21
#>
param (
    [switch]$Debug,
    [string]$Config,
    [switch]$Run
)

# Set DebugPreference based on the -Debug switch
if ($Debug) {
    $DebugPreference = "Continue"
}

if ($Config) {
    $PARAM_CONFIG = $Config
}

$PARAM_RUN = $false
# Handle the -Run switch
if ($Run) {
    Write-Host "Running config file tasks..."
    $PARAM_RUN = $true
}

if (!(Test-Path -Path $ENV:TEMP)) {
    New-Item -ItemType Directory -Force -Path $ENV:TEMP
}

Start-Transcript $ENV:TEMP\Winutil.log -Append

# Load DLLs
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Variable to sync between runspaces
$sync = [Hashtable]::Synchronized(@{})
$sync.PSScriptRoot = $PSScriptRoot
$sync.version = "24.04.21"
$sync.configs = @{}
$sync.ProcessRunning = $false

$currentPid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = new-object System.Security.Principal.WindowsPrincipal($currentPid)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator


if ($principal.IsInRole($adminRole))
{
    $Host.UI.RawUI.WindowTitle = $myInvocation.MyCommand.Definition + "(Admin)"
    clear-host
}
else
{
    Write-Host "===========================================" -Foregroundcolor Red
    Write-Host "-- Scripts must be run as Administrator ---" -Foregroundcolor Red
    Write-Host "-- Right-Click Start -> Terminal(Admin) ---" -Foregroundcolor Red
    Write-Host "===========================================" -Foregroundcolor Red
    break
}
function ConvertTo-Icon { 
    <#
    
        .DESCRIPTION
        This function will convert PNG to ICO file

        .EXAMPLE
        ConvertTo-Icon -bitmapPath "$env:TEMP\cttlogo.png" -iconPath $iconPath
    #>
    param( [Parameter(Mandatory=$true)] 
        $bitmapPath, 
        $iconPath = "$env:temp\newicon.ico"
    ) 
    
    Add-Type -AssemblyName System.Drawing 
    
    if (Test-Path $bitmapPath) { 
        $b = [System.Drawing.Bitmap]::FromFile($bitmapPath) 
        $icon = [System.Drawing.Icon]::FromHandle($b.GetHicon()) 
        $file = New-Object System.IO.FileStream($iconPath, 'OpenOrCreate') 
        $icon.Save($file) 
        $file.Close() 
        $icon.Dispose() 
        #explorer "/SELECT,$iconpath" 
    } 
    else { Write-Warning "$BitmapPath does not exist" } 
}
function Copy-Files {
    <#
    
        .DESCRIPTION
        This function will make all modifications to the registry

        .EXAMPLE

        Set-WinUtilRegistry -Name "PublishUserActivities" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Type "DWord" -Value "0"
    
    #>    
    param (
        [string] $Path, 
        [string] $Destination, 
        [switch] $Recurse = $false, 
        [switch] $Force = $false
    )

    try {   

 	$files = Get-ChildItem -Path $path -Recurse:$recurse
	Write-Host "Copy $($files.Count)(s) from $path to $destination"

        foreach($file in $files)
        {
            $status = "Copy files {0} on {1}: {2}" -f $counter, $files.Count, $file.Name
            Write-Progress -Activity "Copy Windows files" -Status $status -PercentComplete ($counter++/$files.count*100)
            $restpath = $file.FullName -Replace $path, ''

            if($file.PSIsContainer -eq $true)
            {
                Write-Debug "Creating $($destination + $restpath)"
                New-Item ($destination+$restpath) -Force:$force -Type Directory -ErrorAction SilentlyContinue
            }
            else
            {
                Write-Debug "Copy from $($file.FullName) to $($destination+$restpath)"
                Copy-Item $file.FullName ($destination+$restpath) -ErrorAction SilentlyContinue -Force:$force 
                Set-ItemProperty -Path ($destination+$restpath) -Name IsReadOnly -Value $false
            }        
        }
        Write-Progress -Activity "Copy Windows files" -Status "Ready" -Completed
    }
    Catch{
        Write-Warning "Unable to Copy all the files due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Get-LocalizedYesNo {
    <#
    .SYNOPSIS
    This function runs choice.exe and captures its output to extract yes no in a localized Windows 
    
    .DESCRIPTION
    The function retrieves the output of the command 'cmd /c "choice <nul 2>nul"' and converts the default output for Yes and No
    in the localized format, such as "Yes=<first character>, No=<second character>".
    
    .EXAMPLE
    $yesNoArray = Get-LocalizedYesNo
    Write-Host "Yes=$($yesNoArray[0]), No=$($yesNoArray[1])"
    #>
  
    # Run choice and capture its options as output
    # The output shows the options for Yes and No as "[Y,N]?" in the (partitially) localized format.
    # eg. English: [Y,N]?
    # Dutch: [Y,N]?
    # German: [J,N]?
    # French: [O,N]?
    # Spanish: [S,N]?
    # Italian: [S,N]?
    # Russian: [Y,N]?
    
    $line = cmd /c "choice <nul 2>nul"
    $charactersArray = @()
    $regexPattern = '([a-zA-Z])'
    $charactersArray = [regex]::Matches($line, $regexPattern) | ForEach-Object { $_.Groups[1].Value }

    Write-Debug "According to takeown.exe local Yes is $charactersArray[0]"
    # Return the array of characters
    return $charactersArray
  }
  

function Get-LocalizedYesNoTakeown {
    <#
    .SYNOPSIS
    This function runs takeown.exe and captures its output to extract yes no in a localized Windows 
    
    .DESCRIPTION
    The function retrieves lines from the output of takeown.exe until there are at least 2 characters
    captured in a specific format, such as "Yes=<first character>, No=<second character>".
    
    .EXAMPLE
    $yesNoArray = Get-LocalizedYesNo
    Write-Host "Yes=$($yesNoArray[0]), No=$($yesNoArray[1])"
    #>
  
    # Run takeown.exe and capture its output
    $takeownOutput = & takeown.exe /? | Out-String

    # Parse the output and retrieve lines until there are at least 2 characters in the array
    $found = $false
    $charactersArray = @()
    foreach ($line in $takeownOutput -split "`r`n") 
    {
        # skip everything before /D flag help
        if ($found) 
        {
            # now that /D is found start looking for a single character in double quotes
            # in help text there is another string in double quotes but it is not a single character
            $regexPattern = '"([a-zA-Z])"'

            $charactersArray = [regex]::Matches($line, $regexPattern) | ForEach-Object { $_.Groups[1].Value }
            
            # if ($charactersArray.Count -gt 0) {
            #     Write-Output "Extracted symbols: $($matches -join ', ')"
            # } else {
            #     Write-Output "No matches found."
            # }

            if ($charactersArray.Count -ge 2) 
            {
                break
            }    
        }
        elseif ($line -match "/D   ") 
        {
            $found = $true
        }
    }

    Write-Debug "According to takeown.exe local Yes is $charactersArray[0]"
    # Return the array of characters
    return $charactersArray
  }
function Get-Oscdimg { 
    <#
    
        .DESCRIPTION
        This function will download oscdimg file from github Release folders and put it into env:temp folder

        .EXAMPLE
        Get-Oscdimg
    #>
    param( [Parameter(Mandatory=$true)] 
        [string]$oscdimgPath
    )
    $oscdimgPath = "$env:TEMP\oscdimg.exe"
    $downloadUrl = "https://github.com/ChrisTitusTech/winutil/raw/main/releases/oscdimg.exe"
    Invoke-RestMethod -Uri $downloadUrl -OutFile $oscdimgPath
    $hashResult = Get-FileHash -Path $oscdimgPath -Algorithm SHA256
    $sha256Hash = $hashResult.Hash

    Write-Host "[INFO] oscdimg.exe SHA-256 Hash: $sha256Hash"

    $expectedHash = "AB9E161049D293B544961BFDF2D61244ADE79376D6423DF4F60BF9B147D3C78D"  # Replace with the actual expected hash
    if ($sha256Hash -eq $expectedHash) {
        Write-Host "Hashes match. File is verified."
    } else {
        Write-Host "Hashes do not match. File may be corrupted or tampered with."
    }
} 
function Get-TabXaml {
    <#
    .SYNOPSIS
        Generates XAML for a tab in the WinUtil GUI
        This function is used to generate the XAML for the applications tab in the WinUtil GUI
        It takes the tabname and the number of columns to display the applications in as input and returns the XAML for the tab as output
    .PARAMETER tabname
        The name of the tab to generate XAML for
    .PARAMETER columncount
        The number of columns to display the applications in
    .OUTPUTS
        The XAML for the tab
    .EXAMPLE
        Get-TabXaml "applications" 3
    #>
    
    
    param( [Parameter(Mandatory=$true)]
        $tabname,
        $columncount = 0
    )
    $organizedData = @{}
    # Iterate through JSON data and organize by panel and category
    foreach ($appName in $sync.configs.$tabname.PSObject.Properties.Name) {
        $appInfo = $sync.configs.$tabname.$appName

        # Create an object for the application
        $appObject = [PSCustomObject]@{
            Name = $appName
            Category = $appInfo.Category
            Content = $appInfo.Content
            Choco = $appInfo.choco
            Winget = $appInfo.winget
            Panel = if ($columncount -gt 0 ) { "0" } else {$appInfo.panel}
            Link = $appInfo.link
            Description = $appInfo.description
            # Type is (Checkbox,Toggle,Button,Combobox ) (Default is Checkbox)
            Type = $appInfo.type
            ComboItems = $appInfo.ComboItems
            # Checked is the property to set startup checked status of checkbox (Default is false)
            Checked = $appInfo.Checked
        }

        if (-not $organizedData.ContainsKey($appObject.panel)) {
            $organizedData[$appObject.panel] = @{}
        }

        if (-not $organizedData[$appObject.panel].ContainsKey($appObject.Category)) {
            $organizedData[$appObject.panel][$appObject.Category] = @{}
        }

        # Store application data in a sub-array under the category
        # Add Order property to keep the original order of tweaks and features
        $organizedData[$appObject.panel][$appInfo.Category]["$($appInfo.order)$appName"] = $appObject
    }
    $panelcount=0
    $paneltotal = $organizedData.Keys.Count
    if ($columncount -gt 0) {
        $appcount = $sync.configs.$tabname.PSObject.Properties.Name.count + $organizedData["0"].Keys.count
        $maxcount = [Math]::Round( $appcount / $columncount + 0.5)
        $paneltotal = $columncount
    }
    # add ColumnDefinitions to evenly draw colums
    $blockXml="<Grid.ColumnDefinitions>`n"+("<ColumnDefinition Width=""*""/>`n"*($paneltotal))+"</Grid.ColumnDefinitions>`n"
    # Iterate through organizedData by panel, category, and application
    $count = 0
    foreach ($panel in ($organizedData.Keys | Sort-Object)) {
        $blockXml += "<Border Grid.Row=""1"" Grid.Column=""$panelcount"">`n<StackPanel Background=""{MainBackgroundColor}"" SnapsToDevicePixels=""True"">`n"
        $panelcount++
        foreach ($category in ($organizedData[$panel].Keys | Sort-Object)) {
            $count++
            if ($columncount -gt 0) {
                $panelcount2 = [Int](($count)/$maxcount-0.5)
                if ($panelcount -eq $panelcount2 ) {
                    $blockXml +="`n</StackPanel>`n</Border>`n"
                    $blockXml += "<Border Grid.Row=""1"" Grid.Column=""$panelcount"">`n<StackPanel Background=""{MainBackgroundColor}"" SnapsToDevicePixels=""True"">`n"
                    $panelcount++
                }
            }
            $blockXml += "<Label Content=""$($category -replace '^.__', '')"" FontSize=""16""/>`n"
            $sortedApps = $organizedData[$panel][$category].Keys | Sort-Object
            foreach ($appName in $sortedApps) {
                $count++
                if ($columncount -gt 0) {
                    $panelcount2 = [Int](($count)/$maxcount-0.5)
                    if ($panelcount -eq $panelcount2 ) {
                        $blockXml +="`n</StackPanel>`n</Border>`n"
                        $blockXml += "<Border Grid.Row=""1"" Grid.Column=""$panelcount"">`n<StackPanel Background=""{MainBackgroundColor}"" SnapsToDevicePixels=""True"">`n"
                        $panelcount++
                    }
                }
                $appInfo = $organizedData[$panel][$category][$appName]
                if ("Toggle" -eq $appInfo.Type) {
                    $blockXml += "<StackPanel Orientation=`"Horizontal`" Margin=`"0,10,0,0`">`n<Label Content=`"$($appInfo.Content)`" Style=`"{StaticResource labelfortweaks}`" ToolTip=`"$($appInfo.Description)`" />`n"
                    $blockXml += "<CheckBox Name=`"$($appInfo.Name)`" Style=`"{StaticResource ColorfulToggleSwitchStyle}`" Margin=`"2.5,0`"/>`n</StackPanel>`n"
                } elseif ("Combobox" -eq $appInfo.Type) {
                    $blockXml += "<StackPanel Orientation=`"Horizontal`" Margin=`"0,5,0,0`">`n<Label Content=`"$($appInfo.Content)`" HorizontalAlignment=`"Left`" VerticalAlignment=`"Center`"/>`n"
                    $blockXml += "<ComboBox Name=`"$($appInfo.Name)`"  Height=`"32`" Width=`"186`" HorizontalAlignment=`"Left`" VerticalAlignment=`"Center`" Margin=`"5,5`">`n"
                    $addfirst="IsSelected=`"True`""
                    foreach ($comboitem in ($appInfo.ComboItems -split " ")) {
                        $blockXml += "<ComboBoxItem $addfirst Content=`"$comboitem`"/>`n"
                        $addfirst=""
                    }
                    $blockXml += "</ComboBox>`n</StackPanel>"
                # If it is a digit, type is button and button length is digits
                } elseif ($appInfo.Type -match "^[\d\.]+$") {
                    $blockXml += "<Button Name=`"$($appInfo.Name)`" Content=`"$($appInfo.Content)`" HorizontalAlignment = `"Left`" Width=`"$($appInfo.Type)`" Margin=`"5`" Padding=`"20,5`" />`n"
                # else it is a checkbox
                } else {
                    $checkedStatus = If ($null -eq $appInfo.Checked) {""} Else {"IsChecked=`"$($appInfo.Checked)`" "}
                    if ($null -eq $appInfo.Link)
                    {
                        $blockXml += "<CheckBox Name=`"$($appInfo.Name)`" Content=`"$($appInfo.Content)`" $($checkedStatus)Margin=`"5,0`"  ToolTip=`"$($appInfo.Description)`"/>`n"
                    }
                    else
                    {
                        $blockXml += "<StackPanel Orientation=""Horizontal"">`n<CheckBox Name=""$($appInfo.Name)"" Content=""$($appInfo.Content)"" $($checkedStatus)ToolTip=""$($appInfo.Description)"" Margin=""0,0,2,0""/><TextBlock Name=""$($appInfo.Name)Link"" Style=""{StaticResource HoverTextBlockStyle}"" Text=""(?)"" ToolTip=""$($appInfo.Link)"" />`n</StackPanel>`n"
                    }
                }
            }
        }
        $blockXml +="`n</StackPanel>`n</Border>`n"
    }
    return ($blockXml)
}
Function Get-WinUtilCheckBoxes {

    <#

    .SYNOPSIS
        Finds all checkboxes that are checked on the specific tab and inputs them into a script.

    .PARAMETER Group
        The group of checkboxes to check

    .PARAMETER unCheck
        Whether to uncheck the checkboxes that are checked. Defaults to true

    .OUTPUTS
        A List containing the name of each checked checkbox

    .EXAMPLE
        Get-WinUtilCheckBoxes "WPFInstall"

    #>

    Param(
        [boolean]$unCheck = $false
    )

    $Output = @{
        Install      = @()
        WPFTweaks     = @()
        WPFFeature    = @()
        WPFInstall    = @()
    }

    $CheckBoxes = $sync.GetEnumerator() | Where-Object { $_.Value -is [System.Windows.Controls.CheckBox] }

    foreach ($CheckBox in $CheckBoxes) {
        $group = if ($CheckBox.Key.StartsWith("WPFInstall")) { "Install" }
                elseif ($CheckBox.Key.StartsWith("WPFTweaks")) { "WPFTweaks" }
                elseif ($CheckBox.Key.StartsWith("WPFFeature")) { "WPFFeature" }

        if ($group) {
            if ($CheckBox.Value.IsChecked -eq $true) {
                $feature = switch ($group) {
                    "Install" {
                        # Get the winget value
                        $wingetValue = $sync.configs.applications.$($CheckBox.Name).winget

                        if (-not [string]::IsNullOrWhiteSpace($wingetValue) -and $wingetValue -ne "na") {
                            $wingetValue -split ";"
                        } else {
                            $sync.configs.applications.$($CheckBox.Name).choco
                        }
                    }
                    default {
                        $CheckBox.Name
                    }
                }

                if (-not $Output.ContainsKey($group)) {
                    $Output[$group] = @()
                }
                if ($group -eq "Install") {
                    $Output["WPFInstall"] += $CheckBox.Name
                    Write-Debug "Adding: $($CheckBox.Name) under: WPFInstall"
                }

                Write-Debug "Adding: $($feature) under: $($group)"
                $Output[$group] += $feature

                if ($uncheck -eq $true) {
                    $CheckBox.Value.IsChecked = $false
                }
            }
        }
    }

    return  $Output
}
function Get-WinUtilInstallerProcess {
    <#

    .SYNOPSIS
        Checks if the given process is running

    .PARAMETER Process
        The process to check

    .OUTPUTS
        Boolean - True if the process is running

    #>

    param($Process)

    if ($Null -eq $Process){
        return $false
    }
    if (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue){
        return $true
    }
    return $false
}
Function Get-WinUtilToggleStatus {
    <#

    .SYNOPSIS
        Pulls the registry keys for the given toggle switch and checks whether the toggle should be checked or unchecked

    .PARAMETER ToggleSwitch
        The name of the toggle to check

    .OUTPUTS
        Boolean to set the toggle's status to

    #>

    Param($ToggleSwitch)
    if($ToggleSwitch -eq "WPFToggleDarkMode"){
        $app = (Get-ItemProperty -path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize').AppsUseLightTheme
        $system = (Get-ItemProperty -path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize').SystemUsesLightTheme
        if($app -eq 0 -and $system -eq 0){
            return $true
        }
        else{
            return $false
        }
    }
    if($ToggleSwitch -eq "WPFToggleBingSearch"){
        $bingsearch = (Get-ItemProperty -path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search').BingSearchEnabled
        if($bingsearch -eq 0){
            return $false
        }
        else{
            return $true
        }
    }
    if($ToggleSwitch -eq "WPFToggleNumLock"){
        $numlockvalue = (Get-ItemProperty -path 'HKCU:\Control Panel\Keyboard').InitialKeyboardIndicators
        if($numlockvalue -eq 2){
            return $true
        }
        else{
            return $false
        }
    }
    if($ToggleSwitch -eq "WPFToggleVerboseLogon"){
        $VerboseStatusvalue = (Get-ItemProperty -path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').VerboseStatus
        if($VerboseStatusvalue -eq 1){
            return $true
        }
        else{
            return $false
        }
    }    
    if($ToggleSwitch -eq "WPFToggleShowExt"){
        $hideextvalue = (Get-ItemProperty -path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced').HideFileExt
        if($hideextvalue -eq 0){
            return $true
        }
        else{
            return $false
        }
    }    
    if($ToggleSwitch -eq "WPFToggleSnapFlyout"){
        $hidesnap = (Get-ItemProperty -path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced').EnableSnapAssistFlyout
        if($hidesnap -eq 0){
            return $false
        }
        else{
            return $true
        }
    }    
    if($ToggleSwitch -eq "WPFToggleMouseAcceleration"){
        $MouseSpeed = (Get-ItemProperty -path 'HKCU:\Control Panel\Mouse').MouseSpeed
        $MouseThreshold1 = (Get-ItemProperty -path 'HKCU:\Control Panel\Mouse').MouseThreshold1
        $MouseThreshold2 = (Get-ItemProperty -path 'HKCU:\Control Panel\Mouse').MouseThreshold2

        if($MouseSpeed -eq 1 -and $MouseThreshold1 -eq 6 -and $MouseThreshold2 -eq 10){
            return $true
        }
        else{
            return $false
        }
    }
    if ($ToggleSwitch -eq "WPFToggleStickyKeys") {
        $StickyKeys = (Get-ItemProperty -path 'HKCU:\Control Panel\Accessibility\StickyKeys').Flags
        if($StickyKeys -eq 58){
            return $false
        }
        else{
            return $true
        }
    }
    if ($ToggleSwitch -eq "WPFToggleTaskbarWidgets") {
        $TaskbarWidgets = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced").TaskBarDa
	if($TaskbarWidgets -eq 0) {
            return $false
	}
	else{
            return $true
	}
    }
}
function Get-WinUtilVariables {

    <#
    .SYNOPSIS
        Gets every form object of the provided type

    .OUTPUTS
        List containing every object that matches the provided type
    #>
    param (
        [Parameter()]
        [string[]]$Type
    )

    $keys = $sync.keys | Where-Object { $_ -like "WPF*" }

    if ($Type) {
        $output = $keys | ForEach-Object {
            Try {
                $objType = $sync["$psitem"].GetType().Name
                if ($Type -contains $objType) {
                    Write-Output $psitem
                }
            }
            Catch {
                <#I am here so errors don't get outputted for a couple variables that don't have the .GetType() attribute#>
            }
        }
        return $output
    }
    return $keys
}
function Get-WinUtilWingetLatest {
    <#
    .SYNOPSIS
        Uses GitHub API to check for the latest release of Winget.
    .DESCRIPTION
        This function grabs the latest version of Winget and returns the download path to Install-WinUtilWinget for installation.
    #>

    Try{
        # Grabs the latest release of Winget from the Github API for the install process.
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/Winget-cli/releases/latest" -Method Get -ErrorAction Stop
        $latestVersion = $response.tag_name #Stores version number of latest release.
        $licenseWingetUrl = $response.assets.browser_download_url[0] #Index value for License file.
        Write-Host "Latest Version:`t$($latestVersion)`n"
        $assetUrl = $response.assets.browser_download_url[2] #Index value for download URL.
        Invoke-WebRequest -Uri $licenseWingetUrl -OutFile $ENV:TEMP\License1.xml
        # The only pain is that the msixbundle for winget-cli is 246MB. In some situations this can take a bit, with slower connections.
        Invoke-WebRequest -Uri $assetUrl -OutFile $ENV:TEMP\Microsoft.DesktopAppInstaller.msixbundle
    }
    Catch{
        throw [WingetFailedInstall]::new('Failed to get latest Winget release and license')
    }
}
function Get-WinUtilWingetPrerequisites {
    <#
    .SYNOPSIS
        Downloads the Winget Prereqs.
    .DESCRIPTION
        Downloads Prereqs for Winget. Version numbers are coded as variables and can be updated as uncommonly as Microsoft updates the prereqs.
    #>

    # I don't know of a way to detect the prereqs automatically, so if someone has a better way of defining these, that would be great.
    # Microsoft.VCLibs version rarely changes, but for future compatibility I made it a variable.
    $versionVCLibs = "14.00"
    $fileVCLibs = "https://aka.ms/Microsoft.VCLibs.x64.${versionVCLibs}.Desktop.appx"
    # Write-Host "$fileVCLibs"
    # Microsoft.UI.Xaml version changed recently, so I made the version numbers variables.
    $versionUIXamlMinor = "2.8"
    $versionUIXamlPatch = "2.8.6"
    $fileUIXaml = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v${versionUIXamlPatch}/Microsoft.UI.Xaml.${versionUIXamlMinor}.x64.appx"
    # Write-Host "$fileUIXaml"

    Try{
        Write-Host "Downloading Microsoft.VCLibs Dependency..."
        Invoke-WebRequest -Uri $fileVCLibs -OutFile $ENV:TEMP\Microsoft.VCLibs.x64.Desktop.appx
        Write-Host "Downloading Microsoft.UI.Xaml Dependency...`n"
        Invoke-WebRequest -Uri $fileUIXaml -OutFile $ENV:TEMP\Microsoft.UI.Xaml.x64.appx
    }
    Catch{
        throw [WingetFailedInstall]::new('Failed to install prerequsites')
    }
}
function Install-WinUtilChoco {

    <#

    .SYNOPSIS
        Installs Chocolatey if it is not already installed

    #>

    try {
        Write-Host "Checking if Chocolatey is Installed..."

        if((Test-WinUtilPackageManager -choco) -eq "installed") {
            return
        }

        Write-Host "Seems Chocolatey is not installed, installing now."
        Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')) -ErrorAction Stop
        powershell choco feature enable -n allowGlobalConfirmation

    }
    Catch {
        Write-Host "===========================================" -Foregroundcolor Red
        Write-Host "--     Chocolatey failed to install     ---" -Foregroundcolor Red
        Write-Host "===========================================" -Foregroundcolor Red
    }

}
Function Install-WinUtilProgramWinget {

    <#
    .SYNOPSIS
        Manages the provided programs using Winget

    .PARAMETER ProgramsToInstall
        A list of programs to manage

    .PARAMETER manage
        The action to perform on the programs, can be either 'Installing' or 'Uninstalling'

    .NOTES
        The triple quotes are required any time you need a " in a normal script block.
    #>

    param(
        $ProgramsToInstall,
        $manage = "Installing"
    )

    $x = 0
    $count = $($ProgramsToInstall -split ",").Count

    Write-Progress -Activity "$manage Applications" -Status "Starting" -PercentComplete 0

    Foreach ($Program in $($ProgramsToInstall -split ",")){

        Write-Progress -Activity "$manage Applications" -Status "$manage $Program $($x + 1) of $count" -PercentComplete $($x/$count*100)
        if($manage -eq "Installing"){
            # Install package via ID, if it fails try again with different scope and then with an unelevated prompt. 
            # Since Install-WinGetPackage might not be directly available, we use winget install command as a workaround.
            # Winget, not all installers honor any of the following: System-wide, User Installs, or Unelevated Prompt OR Silent Install Mode.
            # This is up to the individual package maintainers to enable these options. Aka. not as clean as Linux Package Managers.
            try {
                $status = $(Start-Process -FilePath "winget" -ArgumentList "install --id $Program --silent --accept-source-agreements --accept-package-agreements" -Wait -PassThru).ExitCode
                if($status -ne 0){
                    Write-Host "Attempt with User scope"
                    $status = $(Start-Process -FilePath "winget" -ArgumentList "install --id $Program --scope user --silent --accept-source-agreements --accept-package-agreements" -Wait -PassThru).ExitCode
                    if($status -ne 0){
                        Write-Host "Attempt with Unelevated prompt"
                        $status = $(Start-Process -FilePath "powershell" -ArgumentList "-Command Start-Process winget -ArgumentList 'install --id $Program --silent --accept-source-agreements --accept-package-agreements' -Verb runAsUser" -Wait -PassThru).ExitCode
                        if($status -ne 0){
                            Write-Host "Failed to install $Program."
                        } else {
                            Write-Host "$Program installed successfully with Unelevated prompt."
                        }
                    } else {
                        Write-Host "$Program installed successfully with User scope."
                    }
                } else {
                    Write-Host "$Program installed successfully."
                }
            } catch {
                Write-Host "Failed to install $Program due to an error: $_"
            }
        }
        if($manage -eq "Uninstalling"){
            # Uninstall package via ID using winget directly.
            try {
                $status = $(Start-Process -FilePath "winget" -ArgumentList "uninstall --id $Program --silent" -Wait -PassThru).ExitCode
                if($status -ne 0){
                    Write-Host "Failed to uninstall $Program."
                } else {
                    Write-Host "$Program uninstalled successfully."
                }
            } catch {
                Write-Host "Failed to uninstall $Program due to an error: $_"
            }
        }
        $X++
    }

    Write-Progress -Activity "$manage Applications" -Status "Finished" -Completed
}
function Install-WinUtilWinget {
    <#

    .SYNOPSIS
        Installs Winget if it is not already installed.

    .DESCRIPTION
        This function will download the latest version of Winget and install it. If Winget is already installed, it will do nothing.
    #>
    $isWingetInstalled = Test-WinUtilPackageManager -winget

    Try {
        if ($isWingetInstalled -eq "installed") {
            Write-Host "`nWinget is already installed.`r" -ForegroundColor Green
            return
        } elseif ($isWingetInstalled -eq "outdated") {
            Write-Host "`nWinget is Outdated. Continuing with install.`r" -ForegroundColor Yellow
        } else {
            Write-Host "`nWinget is not Installed. Continuing with install.`r" -ForegroundColor Red
        }

        # Gets the computer's information
        if ($null -eq $sync.ComputerInfo){
            $ComputerInfo = Get-ComputerInfo -ErrorAction Stop
        } else {
            $ComputerInfo = $sync.ComputerInfo
        }

        if (($ComputerInfo.WindowsVersion) -lt "1809") {
            # Checks if Windows Version is too old for Winget
            Write-Host "Winget is not supported on this version of Windows (Pre-1809)" -ForegroundColor Red
            return
        }

        # Install Winget via GitHub method.
        # Used part of my own script with some modification: ruxunderscore/windows-initialization
        Write-Host "Downloading Winget Prerequsites`n"
        Get-WinUtilWingetPrerequisites
        Write-Host "Downloading Winget and License File`r"
        Get-WinUtilWingetLatest
        Write-Host "Installing Winget w/ Prerequsites`r"
        Add-AppxProvisionedPackage -Online -PackagePath $ENV:TEMP\Microsoft.DesktopAppInstaller.msixbundle -DependencyPackagePath $ENV:TEMP\Microsoft.VCLibs.x64.Desktop.appx, $ENV:TEMP\Microsoft.UI.Xaml.x64.appx -LicensePath $ENV:TEMP\License1.xml
		Write-Host "Manually adding Winget Sources, from Winget CDN."
		Add-AppxPackage -Path https://cdn.winget.microsoft.com/cache/source.msix #Seems some installs of Winget don't add the repo source, this should makes sure that it's installed every time. 
        Write-Host "Winget Installed" -ForegroundColor Green
        Write-Host "Enabling NuGet and Module..."
        Install-PackageProvider -Name NuGet -Force
        Install-Module -Name Microsoft.WinGet.Client -Force
        # Winget only needs a refresh of the environment variables to be used.
        Write-Output "Refreshing Environment Variables...`n"
        $ENV:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    } Catch {
        Write-Host "Failure detected while installing via GitHub method. Continuing with Chocolatey method as fallback." -ForegroundColor Red
        # In case install fails via GitHub method.
        Try {
        Start-Process -Verb runas -FilePath powershell.exe -ArgumentList "choco install winget-cli"
        Write-Host "Winget Installed" -ForegroundColor Green
        Write-Output "Refreshing Environment Variables...`n"
        $ENV:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        } Catch {
            throw [WingetFailedInstall]::new('Failed to install!')
        }
    }
}
function Invoke-MicroWin-Helper {
<#

    .SYNOPSIS
        checking unit tests

    .PARAMETER Name
        no parameters

    .EXAMPLE
        placeholder

#>

}

function Test-CompatibleImage() {
<#

    .SYNOPSIS
        Checks the version of a Windows image and determines whether or not it is compatible with a specific feature depending on a desired version

    .PARAMETER Name
        imgVersion - The version of the Windows image
        desiredVersion - The version to compare the image version with

#>

    param
    (
        [Parameter(Mandatory = $true, Position=0)] [string] $imgVersion,
        [Parameter(Mandatory = $true, Position=1)] [Version] $desiredVersion
    )

    try {
        $version = [Version]$imgVersion
        return $version -ge $desiredVersion
    } catch {
        return $False
    }
}

function Remove-Features([switch] $dumpFeatures = $false, [switch] $keepDefender = $false) {
<#

    .SYNOPSIS
        Removes certain features from ISO image

    .PARAMETER Name
        dumpFeatures - Dumps all features found in the ISO into a file called allfeaturesdump.txt. This file can be examined and used to decide what to remove.
		keepDefender - Should Defender be removed from the ISO?

    .EXAMPLE
        Remove-Features -keepDefender:$false

#>
	$featlist = (Get-WindowsOptionalFeature -Path $scratchDir).FeatureName
	if ($dumpFeatures)
	{
		$featlist > allfeaturesdump.txt
	}

	$featlist = $featlist | Where-Object {
		$_ -NotLike "*Printing*" -AND
		$_ -NotLike "*TelnetClient*" -AND
		$_ -NotLike "*PowerShell*" -AND
		$_ -NotLike "*NetFx*" -AND
		$_ -NotLike "*Media*" -AND
		$_ -NotLike "*NFS*"
	}

	if ($keepDefender) { $featlist = $featlist | Where-Object { $_ -NotLike "*Defender*" }}

	foreach($feature in $featlist)
	{
		$status = "Removing feature $feature"
		Write-Progress -Activity "Removing features" -Status $status -PercentComplete ($counter++/$featlist.Count*100)
		Write-Debug "Removing feature $feature"
		Disable-WindowsOptionalFeature -Path "$scratchDir" -FeatureName $feature -Remove  -ErrorAction SilentlyContinue -NoRestart
	}
	Write-Progress -Activity "Removing features" -Status "Ready" -Completed
	Write-Host "You can re-enable the disabled features at any time, using either Windows Update or the SxS folder in <installation media>\Sources."
}

function Remove-Packages
{
	$pkglist = (Get-WindowsPackage -Path "$scratchDir").PackageName

	$pkglist = $pkglist | Where-Object {
			$_ -NotLike "*ApplicationModel*" -AND
			$_ -NotLike "*indows-Client-LanguagePack*" -AND
			$_ -NotLike "*LanguageFeatures-Basic*" -AND
			$_ -NotLike "*Package_for_ServicingStack*" -AND
			$_ -NotLike "*.NET*" -AND
			$_ -NotLike "*Store*" -AND
			$_ -NotLike "*VCLibs*" -AND
			$_ -NotLike "*AAD.BrokerPlugin",
			$_ -NotLike "*LockApp*" -AND
			$_ -NotLike "*Notepad*" -AND
			$_ -NotLike "*immersivecontrolpanel*" -AND
			$_ -NotLike "*ContentDeliveryManager*" -AND
			$_ -NotLike "*PinningConfirMationDialog*" -AND
			$_ -NotLike "*SecHealthUI*" -AND
			$_ -NotLike "*SecureAssessmentBrowser*" -AND
			$_ -NotLike "*PrintDialog*" -AND
			$_ -NotLike "*AssignedAccessLockApp*" -AND
			$_ -NotLike "*OOBENetworkConnectionFlow*" -AND
			$_ -NotLike "*Apprep.ChxApp*" -AND
			$_ -NotLike "*CBS*" -AND
			$_ -NotLike "*OOBENetworkCaptivePortal*" -AND
			$_ -NotLike "*PeopleExperienceHost*" -AND
			$_ -NotLike "*ParentalControls*" -AND
			$_ -NotLike "*Win32WebViewHost*" -AND
			$_ -NotLike "*InputApp*" -AND
			$_ -NotLike "*AccountsControl*" -AND
			$_ -NotLike "*AsyncTextService*" -AND
			$_ -NotLike "*CapturePicker*" -AND
			$_ -NotLike "*CredDialogHost*" -AND
			$_ -NotLike "*BioEnrollMent*" -AND
			$_ -NotLike "*ShellExperienceHost*" -AND
			$_ -NotLike "*DesktopAppInstaller*" -AND
			$_ -NotLike "*WebMediaExtensions*" -AND
			$_ -NotLike "*WMIC*" -AND
			$_ -NotLike "*UI.XaML*"	
		} 

	foreach ($pkg in $pkglist)
	{
		try {
			$status = "Removing $pkg"
			Write-Progress -Activity "Removing Apps" -Status $status -PercentComplete ($counter++/$pkglist.Count*100)
			Remove-WindowsPackage -Path "$scratchDir" -PackageName $pkg -NoRestart -ErrorAction SilentlyContinue
		}
		catch {
			# This can happen if the package that is being removed is a permanent one, like FodMetadata
			Write-Host "Could not remove OS package $($pkg)"
			continue
		}
	}
	Write-Progress -Activity "Removing Apps" -Status "Ready" -Completed
}

function Remove-ProvisionedPackages([switch] $keepSecurity = $false)
{
<#

    .SYNOPSIS
        Removes AppX packages from a Windows image during MicroWin processing

    .PARAMETER Name
        keepSecurity - Boolean that determines whether to keep "Microsoft.SecHealthUI" (Windows Security) in the Windows image

    .EXAMPLE
        Remove-ProvisionedPackages -keepSecurity:$false

#>
	$appxProvisionedPackages = Get-AppxProvisionedPackage -Path "$($scratchDir)" | Where-Object	{
			$_.PackageName -NotLike "*AppInstaller*" -AND
			$_.PackageName -NotLike "*Store*" -and
			$_.PackageName -NotLike "*dism*" -and
			$_.PackageName -NotLike "*Foundation*" -and
			$_.PackageName -NotLike "*FodMetadata*" -and
			$_.PackageName -NotLike "*LanguageFeatures*" -and
			$_.PackageName -NotLike "*Notepad*" -and
			$_.PackageName -NotLike "*Printing*" -and
			$_.PackageName -NotLike "*Wifi*" -and
			$_.PackageName -NotLike "*Foundation*" 
		} 
    
    if ($?)
    {
        if ($keepSecurity) { $appxProvisionedPackages = $appxProvisionedPackages | Where-Object { $_.PackageName -NotLike "*SecHealthUI*" }}
	    $counter = 0
	    foreach ($appx in $appxProvisionedPackages)
	    {
		    $status = "Removing Provisioned $($appx.PackageName)"
		    Write-Progress -Activity "Removing Provisioned Apps" -Status $status -PercentComplete ($counter++/$appxProvisionedPackages.Count*100)
			Remove-AppxProvisionedPackage -Path $scratchDir -PackageName $appx.PackageName -ErrorAction SilentlyContinue
	    }
	    Write-Progress -Activity "Removing Provisioned Apps" -Status "Ready" -Completed
    }
    else
    {
        Write-Host "Could not get Provisioned App information. Skipping process..."
    }
}

function Copy-ToUSB([string] $fileToCopy)
{
	foreach ($volume in Get-Volume) {
		if ($volume -and $volume.FileSystemLabel -ieq "ventoy") {
			$destinationPath = "$($volume.DriveLetter):\"
			#Copy-Item -Path $fileToCopy -Destination $destinationPath -Force
			# Get the total size of the file
			$totalSize = (Get-Item $fileToCopy).length

			Copy-Item -Path $fileToCopy -Destination $destinationPath -Verbose -Force -Recurse -Container -PassThru |
				ForEach-Object {
					# Calculate the percentage completed
					$completed = ($_.BytesTransferred / $totalSize) * 100

					# Display the progress bar
					Write-Progress -Activity "Copying File" -Status "Progress" -PercentComplete $completed -CurrentOperation ("{0:N2} MB / {1:N2} MB" -f ($_.BytesTransferred / 1MB), ($totalSize / 1MB))
				}

			Write-Host "File copied to Ventoy drive $($volume.DriveLetter)"
			return
		}
	}
	Write-Host "Ventoy USB Key is not inserted"
}

function Remove-FileOrDirectory([string] $pathToDelete, [string] $mask = "", [switch] $Directory = $false)
{
	if(([string]::IsNullOrEmpty($pathToDelete))) { return }
	if (-not (Test-Path -Path "$($pathToDelete)")) { return }

	$yesNo = Get-LocalizedYesNo
	Write-Host "[INFO] In Your local takeown expects '$($yesNo[0])' as a Yes answer."

	# Specify the path to the directory
	# $directoryPath = "$($scratchDir)\Windows\System32\LogFiles\WMI\RtBackup"
	# takeown /a /r /d $yesNo[0] /f "$($directoryPath)" > $null
	# icacls "$($directoryPath)" /q /c /t /reset > $null
	# icacls $directoryPath /setowner "*S-1-5-32-544"
	# icacls $directoryPath /grant "*S-1-5-32-544:(OI)(CI)F" /t /c /q
	# Remove-Item -Path $directoryPath -Recurse -Force

	# # Grant full control to BUILTIN\Administrators using icacls
	# $directoryPath = "$($scratchDir)\Windows\System32\WebThreatDefSvc" 
	# takeown /a /r /d $yesNo[0] /f "$($directoryPath)" > $null
	# icacls "$($directoryPath)" /q /c /t /reset > $null
	# icacls $directoryPath /setowner "*S-1-5-32-544"
	# icacls $directoryPath /grant "*S-1-5-32-544:(OI)(CI)F" /t /c /q
	# Remove-Item -Path $directoryPath -Recurse -Force
	
	$itemsToDelete = [System.Collections.ArrayList]::new()

	if ($mask -eq "")
	{
		Write-Debug "Adding $($pathToDelete) to array."
		[void]$itemsToDelete.Add($pathToDelete)
	}
	else 
	{
		Write-Debug "Adding $($pathToDelete) to array and mask is $($mask)" 
		if ($Directory)	{ $itemsToDelete = Get-ChildItem $pathToDelete -Include $mask -Recurse -Directory }
		else { $itemsToDelete = Get-ChildItem $pathToDelete -Include $mask -Recurse }
	}

	foreach($itemToDelete in $itemsToDelete)
	{
		$status = "Deleting $($itemToDelete)"
		Write-Progress -Activity "Removing Items" -Status $status -PercentComplete ($counter++/$itemsToDelete.Count*100)

		if (Test-Path -Path "$($itemToDelete)" -PathType Container) 
		{
			$status = "Deleting directory: $($itemToDelete)"

			takeown /r /d $yesNo[0] /a /f "$($itemToDelete)"
			icacls "$($itemToDelete)" /q /c /t /reset
			icacls $itemToDelete /setowner "*S-1-5-32-544"
			icacls $itemToDelete /grant "*S-1-5-32-544:(OI)(CI)F" /t /c /q
			Remove-Item -Force -Recurse "$($itemToDelete)"
		}
		elseif (Test-Path -Path "$($itemToDelete)" -PathType Leaf)
		{
			$status = "Deleting file: $($itemToDelete)"

			takeown /a /f "$($itemToDelete)"
			icacls "$($itemToDelete)" /q /c /t /reset
			icacls "$($itemToDelete)" /setowner "*S-1-5-32-544"
			icacls "$($itemToDelete)" /grant "*S-1-5-32-544:(OI)(CI)F" /t /c /q
			Remove-Item -Force "$($itemToDelete)"
		}
	}
	Write-Progress -Activity "Removing Items" -Status "Ready" -Completed
}

function New-Unattend {

	# later if we wont to remove even more bloat EU requires MS to remove everything from English(world)
	# Below is an example how to do it we probably should create a drop down with common locals
	# 	<settings pass="specialize">
	#     <!-- Specify English (World) locale -->
	#     <component name="Microsoft-Windows-International-Core" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
	#       <SetupUILanguage>
	#         <UILanguage>en-US</UILanguage>
	#       </SetupUILanguage>
	#       <InputLocale>en-US</InputLocale>
	#       <SystemLocale>en-US</SystemLocale>
	#       <UILanguage>en-US</UILanguage>
	#       <UserLocale>en-US</UserLocale>
	#     </component>
	#   </settings>

	#   <settings pass="oobeSystem">
	#     <!-- Specify English (World) locale -->
	#     <component name="Microsoft-Windows-International-Core" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
	#       <InputLocale>en-US</InputLocale>
	#       <SystemLocale>en-US</SystemLocale>
	#       <UILanguage>en-US</UILanguage>
	#       <UserLocale>en-US</UserLocale>
	#     </component>
	#   </settings>
	# using here string to embedd unattend
	# 	<RunSynchronousCommand wcm:action="add">
	# 	<Order>1</Order>
	# 	<Path>net user administrator /active:yes</Path>
	# </RunSynchronousCommand>

	# this section doesn't work in win10/????
# 	<settings pass="specialize">
# 	<component name="Microsoft-Windows-SQMApi" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
# 		<CEIPEnabled>0</CEIPEnabled>
# 	</component>
# 	<component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
# 		<ConfigureChatAutoInstall>false</ConfigureChatAutoInstall>
# 	</component>
# </settings>

	$unattend = @'
	<?xml version="1.0" encoding="utf-8"?>
	<unattend xmlns="urn:schemas-microsoft-com:unattend"
			xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
			xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <#REPLACEME#>
		<settings pass="auditUser">
			<component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
				<RunSynchronous>
					<RunSynchronousCommand wcm:action="add">
						<Order>1</Order>
						<CommandLine>CMD /C echo LAU GG&gt;C:\Windows\LogAuditUser.txt</CommandLine>
						<Description>StartMenu</Description>
					</RunSynchronousCommand>
				</RunSynchronous>
			</component>
		</settings>
		<settings pass="oobeSystem">
			<component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
				<OOBE>
                	<HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
	                <SkipUserOOBE>false</SkipUserOOBE>
                	<SkipMachineOOBE>false</SkipMachineOOBE>
					<HideOnlineAccountScreens>true</HideOnlineAccountScreens>
					<HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
					<HideEULAPage>true</HideEULAPage>
					<ProtectYourPC>3</ProtectYourPC>
				</OOBE>
				<FirstLogonCommands>
					<SynchronousCommand wcm:action="add">
						<Order>1</Order>
						<CommandLine>cmd.exe /c echo 23&gt;c:\windows\csup.txt</CommandLine>
					</SynchronousCommand>
					<SynchronousCommand wcm:action="add">
						<Order>2</Order>
						<CommandLine>CMD /C echo GG&gt;C:\Windows\LogOobeSystem.txt</CommandLine>
					</SynchronousCommand>
					<SynchronousCommand wcm:action="add">
						<Order>3</Order>
						<CommandLine>powershell -ExecutionPolicy Bypass -File c:\windows\FirstStartup.ps1</CommandLine>
					</SynchronousCommand>
				</FirstLogonCommands>
			</component>
		</settings>
	</unattend>
'@
    $specPass = @'
<settings pass="specialize">
            <component name="Microsoft-Windows-SQMApi" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <CEIPEnabled>0</CEIPEnabled>
            </component>
            <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <ConfigureChatAutoInstall>false</ConfigureChatAutoInstall>
            </component>
        </settings>
'@
    if ((Test-CompatibleImage $imgVersion $([System.Version]::new(10,0,22000,1))) -eq $false)
    {
        # Replace the placeholder text with an empty string to make it valid for Windows 10 Setup
        $unattend = $unattend.Replace("<#REPLACEME#>", "").Trim()
    }
    else
    {
        # Replace the placeholder text with the Specialize pass
        $unattend = $unattend.Replace("<#REPLACEME#>", $specPass).Trim()
    }
	$unattend | Out-File -FilePath "$env:temp\unattend.xml" -Force -Encoding utf8
}

function New-CheckInstall {

	# using here string to embedd firstrun
	$checkInstall = @'
	@echo off
	if exist "C:\windows\cpu.txt" (
		echo C:\windows\cpu.txt exists
	) else (
		echo C:\windows\cpu.txt does not exist
	)
	if exist "C:\windows\SerialNumber.txt" (
		echo C:\windows\SerialNumber.txt exists
	) else (
		echo C:\windows\SerialNumber.txt does not exist
	)
	if exist "C:\unattend.xml" (
		echo C:\unattend.xml exists
	) else (
		echo C:\unattend.xml does not exist
	)
	if exist "C:\Windows\Setup\Scripts\SetupComplete.cmd" (
		echo C:\Windows\Setup\Scripts\SetupComplete.cmd exists
	) else (
		echo C:\Windows\Setup\Scripts\SetupComplete.cmd does not exist
	)
	if exist "C:\Windows\Panther\unattend.xml" (
		echo C:\Windows\Panther\unattend.xml exists
	) else (
		echo C:\Windows\Panther\unattend.xml does not exist
	)
	if exist "C:\Windows\System32\Sysprep\unattend.xml" (
		echo C:\Windows\System32\Sysprep\unattend.xml exists
	) else (
		echo C:\Windows\System32\Sysprep\unattend.xml does not exist
	)
	if exist "C:\Windows\FirstStartup.ps1" (
		echo C:\Windows\FirstStartup.ps1 exists
	) else (
		echo C:\Windows\FirstStartup.ps1 does not exist
	)
	if exist "C:\Windows\winutil.ps1" (
		echo C:\Windows\winutil.ps1 exists
	) else (
		echo C:\Windows\winutil.ps1 does not exist
	)
	if exist "C:\Windows\LogSpecialize.txt" (
		echo C:\Windows\LogSpecialize.txt exists
	) else (
		echo C:\Windows\LogSpecialize.txt does not exist
	)
	if exist "C:\Windows\LogAuditUser.txt" (
		echo C:\Windows\LogAuditUser.txt exists
	) else (
		echo C:\Windows\LogAuditUser.txt does not exist
	)
	if exist "C:\Windows\LogOobeSystem.txt" (
		echo C:\Windows\LogOobeSystem.txt exists
	) else (
		echo C:\Windows\LogOobeSystem.txt does not exist
	)
	if exist "c:\windows\csup.txt" (
		echo c:\windows\csup.txt exists
	) else (
		echo c:\windows\csup.txt does not exist
	)
	if exist "c:\windows\LogFirstRun.txt" (
		echo c:\windows\LogFirstRun.txt exists
	) else (
		echo c:\windows\LogFirstRun.txt does not exist
	)
'@
	$checkInstall | Out-File -FilePath "$env:temp\checkinstall.cmd" -Force -Encoding Ascii
}

function New-FirstRun {

	# using here string to embedd firstrun
	$firstRun = @'
	# Set the global error action preference to continue
	$ErrorActionPreference = "Continue"
	function Remove-RegistryValue
	{
		param (
			[Parameter(Mandatory = $true)]
			[string]$RegistryPath,
	
			[Parameter(Mandatory = $true)]
			[string]$ValueName
		)
	
		# Check if the registry path exists
		if (Test-Path -Path $RegistryPath)
		{
			$registryValue = Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction SilentlyContinue
	
			# Check if the registry value exists
			if ($registryValue)
			{
				# Remove the registry value
				Remove-ItemProperty -Path $RegistryPath -Name $ValueName -Force
				Write-Host "Registry value '$ValueName' removed from '$RegistryPath'."
			}
			else
			{
				Write-Host "Registry value '$ValueName' not found in '$RegistryPath'."
			}
		}
		else
		{
			Write-Host "Registry path '$RegistryPath' not found."
		}
	}
	
	function Stop-UnnecessaryServices
	{
		$servicesToExclude = @(
			"AudioSrv",
			"AudioEndpointBuilder",
			"BFE",
			"BITS",
			"BrokerInfrastructure",
			"CDPSvc",
			"CDPUserSvc_dc2a4",
			"CoreMessagingRegistrar",
			"CryptSvc",
			"DPS",
			"DcomLaunch",
			"Dhcp",
			"DispBrokerDesktopSvc",
			"Dnscache",
			"DoSvc",
			"DusmSvc",
			"EventLog",
			"EventSystem",
			"FontCache",
			"LSM",
			"LanmanServer",
			"LanmanWorkstation",
			"MapsBroker",
			"MpsSvc",
			"OneSyncSvc_dc2a4",
			"Power",
			"ProfSvc",
			"RpcEptMapper",
			"RpcSs",
			"SCardSvr",
			"SENS",
			"SamSs",
			"Schedule",
			"SgrmBroker",
			"ShellHWDetection",
			"Spooler",
			"SysMain",
			"SystemEventsBroker",
			"TextInputManagementService",
			"Themes",
			"TrkWks",
			"UserManager",
			"VGAuthService",
			"VMTools",
			"WSearch",
			"Wcmsvc",
			"WinDefend",
			"Winmgmt",
			"WlanSvc",
			"WpnService",
			"WpnUserService_dc2a4",
			"cbdhsvc_dc2a4",
			"edgeupdate",
			"gpsvc",
			"iphlpsvc",
			"mpssvc",
			"nsi",
			"sppsvc",
			"tiledatamodelsvc",
			"vm3dservice",
			"webthreatdefusersvc_dc2a4",
			"wscsvc"
)	
	
		$runningServices = Get-Service | Where-Object { $servicesToExclude -notcontains $_.Name }
		foreach($service in $runningServices)
		{
            Stop-Service -Name $service.Name -PassThru
			Set-Service $service.Name -StartupType Manual
			"Stopping service $($service.Name)" | Out-File -FilePath c:\windows\LogFirstRun.txt -Append -NoClobber
		}
	}
	
	"FirstStartup has worked" | Out-File -FilePath c:\windows\LogFirstRun.txt -Append -NoClobber
	
	$Theme = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
	Set-ItemProperty -Path $Theme -Name AppsUseLightTheme -Value 1
	Set-ItemProperty -Path $Theme -Name SystemUsesLightTheme -Value 1

	# figure this out later how to set updates to security only
	#Import-Module -Name PSWindowsUpdate; 
	#Stop-Service -Name wuauserv
	#Set-WUSettings -MicrosoftUpdateEnabled -AutoUpdateOption 'Never'
	#Start-Service -Name wuauserv
	
	Stop-UnnecessaryServices
	
	$taskbarPath = "$env:AppData\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
	# Delete all files on the Taskbar 
	Get-ChildItem -Path $taskbarPath -File | Remove-Item -Force
	Remove-RegistryValue -RegistryPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -ValueName "FavoritesRemovedChanges"
	Remove-RegistryValue -RegistryPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -ValueName "FavoritesChanges"
	Remove-RegistryValue -RegistryPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -ValueName "Favorites"
	
	# Stop-Process -Name explorer -Force

	$process = Get-Process -Name "explorer"
	Stop-Process -InputObject $process
	# Wait for the process to exit
	Wait-Process -InputObject $process
	Start-Sleep -Seconds 3

	# Delete Edge Icon from the desktop
	$edgeShortcutFiles = Get-ChildItem -Path $desktopPath -Filter "*Edge*.lnk"
	# Check if Edge shortcuts exist on the desktop
	if ($edgeShortcutFiles) 
	{
		foreach ($shortcutFile in $edgeShortcutFiles) 
		{
			# Remove each Edge shortcut
			Remove-Item -Path $shortcutFile.FullName -Force
			Write-Host "Edge shortcut '$($shortcutFile.Name)' removed from the desktop."
		}
	}
	Remove-Item -Path "$env:USERPROFILE\Desktop\*.lnk"
	Remove-Item -Path "C:\Users\Default\Desktop\*.lnk"

	# ************************************************
	# Create WinUtil shortcut on the desktop
	#
	$desktopPath = "$($env:USERPROFILE)\Desktop"
	# Specify the target PowerShell command
	$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'irm https://christitus.com/win | iex'"
	# Specify the path for the shortcut
	$shortcutPath = Join-Path $desktopPath 'winutil.lnk'
	# Create a shell object
	$shell = New-Object -ComObject WScript.Shell
	
	# Create a shortcut object
	$shortcut = $shell.CreateShortcut($shortcutPath)

	if (Test-Path -Path "c:\Windows\cttlogo.png")
	{
		$shortcut.IconLocation = "c:\Windows\cttlogo.png"
	}
	
	# Set properties of the shortcut
	$shortcut.TargetPath = "powershell.exe"
	$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$command`""
	# Save the shortcut
	$shortcut.Save()
	
        # Make the shortcut have 'Run as administrator' property on
        $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        # Set byte value at position 0x15 in hex, or 21 in decimal, from the value 0x00 to 0x20 in hex
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)
        
	Write-Host "Shortcut created at: $shortcutPath"
	# 
	# Done create WinUtil shortcut on the desktop
	# ************************************************

	Start-Process explorer
	
'@
	$firstRun | Out-File -FilePath "$env:temp\FirstStartup.ps1" -Force 
}
function Invoke-WinUtilBingSearch {
    <#

    .SYNOPSIS
        Disables/Enables Bing Search

    .PARAMETER Enabled
        Indicates whether to enable or disable Bing Search

    #>
    Param($Enabled)
    Try{
        if ($Enabled -eq $false){
            Write-Host "Enabling Bing Search"
            $value = 1
        }
        else {
            Write-Host "Disabling Bing Search"
            $value = 0
        }
        $Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        Set-ItemProperty -Path $Path -Name BingSearchEnabled -Value $value
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
Function Invoke-WinUtilCurrentSystem {

    <#

    .SYNOPSIS
        Checks to see what tweaks have already been applied and what programs are installed, and checks the according boxes

    .EXAMPLE
        Get-WinUtilCheckBoxes "WPFInstall"

    #>

    param(
        $CheckBox
    )

    if ($checkbox -eq "winget"){

        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
        $Sync.InstalledPrograms = winget list -s winget | Select-Object -skip 3 | ConvertFrom-String -PropertyNames "Name", "Id", "Version", "Available" -Delimiter '\s{2,}'
        [Console]::OutputEncoding = $originalEncoding

        $filter = Get-WinUtilVariables -Type Checkbox | Where-Object {$psitem -like "WPFInstall*"}
        $sync.GetEnumerator() | Where-Object {$psitem.Key -in $filter} | ForEach-Object {
            $dependencies = @($sync.configs.applications.$($psitem.Key).winget -split ";")

            if ($dependencies[-1] -in $sync.InstalledPrograms.Id) {
                Write-Output $psitem.name
            }
        }
    }

    if($CheckBox -eq "tweaks"){

        if(!(Test-Path 'HKU:\')){New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS}
        $ScheduledTasks = Get-ScheduledTask

        $sync.configs.tweaks | Get-Member -MemberType NoteProperty | ForEach-Object {

            $Config = $psitem.Name
            #WPFEssTweaksTele
            $registryKeys = $sync.configs.tweaks.$Config.registry
            $scheduledtaskKeys = $sync.configs.tweaks.$Config.scheduledtask
            $serviceKeys = $sync.configs.tweaks.$Config.service

            if($registryKeys -or $scheduledtaskKeys -or $serviceKeys){
                $Values = @()


                Foreach ($tweaks in $registryKeys){
                    Foreach($tweak in $tweaks){

                        if(test-path $tweak.Path){
                            $actualValue = Get-ItemProperty -Name $tweak.Name -Path $tweak.Path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $($tweak.Name)
                            $expectedValue = $tweak.Value
                            if ($expectedValue -notlike $actualValue){
                                $values += $False
                            }
                        }
                    }
                }

                Foreach ($tweaks in $scheduledtaskKeys){
                    Foreach($tweak in $tweaks){
                        $task = $ScheduledTasks | Where-Object {$($psitem.TaskPath + $psitem.TaskName) -like "\$($tweak.name)"}

                        if($task){
                            $actualValue = $task.State
                            $expectedValue = $tweak.State
                            if ($expectedValue -ne $actualValue){
                                $values += $False
                            }
                        }
                    }
                }

                Foreach ($tweaks in $serviceKeys){
                    Foreach($tweak in $tweaks){
                        $Service = Get-Service -Name $tweak.Name

                        if($Service){
                            $actualValue = $Service.StartType
                            $expectedValue = $tweak.StartupType
                            if ($expectedValue -ne $actualValue){
                                $values += $False
                            }
                        }
                    }
                }

                if($values -notcontains $false){
                    Write-Output $Config
                }
            }
        }
    }
}

Function Invoke-WinUtilDarkMode {
    <#

    .SYNOPSIS
        Enables/Disables Dark Mode

    .PARAMETER DarkMoveEnabled
        Indicates the current dark mode state

    #>
    Param($DarkMoveEnabled)
    Try{
        if ($DarkMoveEnabled -eq $false){
            Write-Host "Enabling Dark Mode"
            $DarkMoveValue = 0
        }
        else {
            Write-Host "Disabling Dark Mode"
            $DarkMoveValue = 1
        }

        $Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        Set-ItemProperty -Path $Path -Name AppsUseLightTheme -Value $DarkMoveValue
        Set-ItemProperty -Path $Path -Name SystemUsesLightTheme -Value $DarkMoveValue
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Invoke-WinUtilFeatureInstall {
    <#

    .SYNOPSIS
        Converts all the values from the tweaks.json and routes them to the appropriate function

    #>

    param(
        $CheckBox
    )

    $CheckBox | ForEach-Object {
        if($sync.configs.feature.$psitem.feature){
            Foreach( $feature in $sync.configs.feature.$psitem.feature ){
                Try{
                    Write-Host "Installing $feature"
                    Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
                }
                Catch{
                    if ($psitem.Exception.Message -like "*requires elevation*"){
                        Write-Warning "Unable to Install $feature due to permissions. Are you running as admin?"
                    }

                    else{
                        Write-Warning "Unable to Install $feature due to unhandled exception"
                        Write-Warning $psitem.Exception.StackTrace
                    }
                }
            }
        }
        if($sync.configs.feature.$psitem.InvokeScript){
            Foreach( $script in $sync.configs.feature.$psitem.InvokeScript ){
                Try{
                    $Scriptblock = [scriptblock]::Create($script)

                    Write-Host "Running Script for $psitem"
                    Invoke-Command $scriptblock -ErrorAction stop
                }
                Catch{
                    if ($psitem.Exception.Message -like "*requires elevation*"){
                        Write-Warning "Unable to Install $feature due to permissions. Are you running as admin?"
                    }

                    else{
                        Write-Warning "Unable to Install $feature due to unhandled exception"
                        Write-Warning $psitem.Exception.StackTrace
                    }
                }
            }
        }
    }
}
function Invoke-WinUtilGPU {
    $gpuInfo = Get-CimInstance Win32_VideoController
    
    foreach ($gpu in $gpuInfo) {
        $gpuName = $gpu.Name
        if ($gpuName -like "*NVIDIA*") {
            return $true  # NVIDIA GPU found
        }
    }

    foreach ($gpu in $gpuInfo) {
        $gpuName = $gpu.Name
        if ($gpuName -like "*AMD Radeon RX*") {
            return $true # AMD GPU Found 
        }
    }
    foreach ($gpu in $gpuInfo) {
        $gpuName = $gpu.Name
        if ($gpuName -like "*UHD*") {
            return $false # Intel Intergrated GPU Found 
        }
    }
    foreach ($gpu in $gpuInfo) {
        $gpuName = $gpu.Name
        if ($gpuName -like "*AMD Radeon(TM)*") {
            return $false # AMD Intergrated GPU Found 
        }
    }
}
Function Invoke-WinUtilMouseAcceleration {
    <#

    .SYNOPSIS
        Enables/Disables Mouse Acceleration

    .PARAMETER DarkMoveEnabled
        Indicates the current Mouse Acceleration State

    #>
    Param($MouseAccelerationEnabled)
    Try{
        if ($MouseAccelerationEnabled -eq $false){
            Write-Host "Enabling Mouse Acceleration"
            $MouseSpeed = 1
            $MouseThreshold1 = 6
            $MouseThreshold2 = 10
        } 
        else {
            Write-Host "Disabling Mouse Acceleration"
            $MouseSpeed = 0
            $MouseThreshold1 = 0
            $MouseThreshold2 = 0 
            
        }

        $Path = "HKCU:\Control Panel\Mouse"
        Set-ItemProperty -Path $Path -Name MouseSpeed -Value $MouseSpeed
        Set-ItemProperty -Path $Path -Name MouseThreshold1 -Value $MouseThreshold1
        Set-ItemProperty -Path $Path -Name MouseThreshold2 -Value $MouseThreshold2
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Invoke-WinUtilNumLock {
    <#
    .SYNOPSIS
        Disables/Enables NumLock on startup
    .PARAMETER Enabled
        Indicates whether to enable or disable Numlock on startup
    #>
    Param($Enabled)
    Try{
        if ($Enabled -eq $false){
            Write-Host "Enabling Numlock on startup"
            $value = 2
        }
        else {
            Write-Host "Disabling Numlock on startup"
            $value = 0
        }
        $Path = "HKCU:\Control Panel\Keyboard"
        Set-ItemProperty -Path $Path -Name InitialKeyboardIndicators -Value $value
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Invoke-WinUtilScript {
    <#

    .SYNOPSIS
        Invokes the provided scriptblock. Intended for things that can't be handled with the other functions.

    .PARAMETER Name
        The name of the scriptblock being invoked

    .PARAMETER scriptblock
        The scriptblock to be invoked

    .EXAMPLE
        $Scriptblock = [scriptblock]::Create({"Write-output 'Hello World'"})
        Invoke-WinUtilScript -ScriptBlock $scriptblock -Name "Hello World"

    #>
    param (
        $Name,
        [scriptblock]$scriptblock
    )

    Try {
        Write-Host "Running Script for $name"
        Invoke-Command $scriptblock -ErrorAction Stop
    }
    Catch [System.Management.Automation.CommandNotFoundException] {
        Write-Warning "The specified command was not found."
        Write-Warning $PSItem.Exception.message
    }
    Catch [System.Management.Automation.RuntimeException] {
        Write-Warning "A runtime exception occurred."
        Write-Warning $PSItem.Exception.message
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "A security exception occurred."
        Write-Warning $PSItem.Exception.message
    }
    Catch [System.UnauthorizedAccessException] {
        Write-Warning "Access denied. You do not have permission to perform this operation."
        Write-Warning $PSItem.Exception.message
    }
    Catch {
        # Generic catch block to handle any other type of exception
        Write-Warning "Unable to run script for $name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }

}
function Invoke-WinUtilShowExt {
    <#
    .SYNOPSIS
        Disables/Enables Show file Extentions
    .PARAMETER Enabled
        Indicates whether to enable or disable Show file extentions
    #>
    Param($Enabled)
    Try{
        if ($Enabled -eq $false){
            Write-Host "Showing file extentions"
            $value = 0
        }
        else {
            Write-Host "hiding file extensions"
            $value = 1
        }
        $Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $Path -Name HideFileExt -Value $value
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Invoke-WinUtilSnapFlyout {
    <#
    .SYNOPSIS
        Disables/Enables Snap Assist Flyout on startup
    .PARAMETER Enabled
        Indicates whether to enable or disable Snap Assist Flyout on startup
    #>
    Param($Enabled)
    Try{
        if ($Enabled -eq $false){
            Write-Host "Enabling Snap Assist Flyout On startup"
            $value = 1
        }
        else {
            Write-Host "Disabling Snap Assist Flyout On startup"
            $value = 0
        }
        # taskkill.exe /F /IM "explorer.exe"
        $Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        taskkill.exe /F /IM "explorer.exe"
        Set-ItemProperty -Path $Path -Name EnableSnapAssistFlyout -Value $value
        Start-Process "explorer.exe"
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
Function Invoke-WinUtilStickyKeys {
    <#
    .SYNOPSIS
        Disables/Enables Sticky Keyss on startup
    .PARAMETER Enabled
        Indicates whether to enable or disable Sticky Keys on startup
    #>
    Param($Enabled)
    Try { 
        if ($Enabled -eq $false){
            Write-Host "Enabling Sticky Keys On startup"
            $value = 510
        }
        else {
            Write-Host "Disabling Sticky Keys On startup"
            $value = 58
        }
        $Path = "HKCU:\Control Panel\Accessibility\StickyKeys"
        Set-ItemProperty -Path $Path -Name Flags -Value $value
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Invoke-WinUtilTaskbarWidgets {
    <#

    .SYNOPSIS
        Enable/Disable Taskbar Widgets

    .PARAMETER Enabled
        Indicates whether to enable or disable Taskbar Widgets

    #>
    Param($Enabled)
    Try{
        if ($Enabled -eq $false){
            Write-Host "Enabling Taskbar Widgets"
            $value = 1
        }
        else {
            Write-Host "Disabling Taskbar Widgets"
            $value = 0
        }
        $Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-ItemProperty -Path $Path -Name TaskbarDa -Value $value
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Invoke-WinUtilTweaks {
    <#

    .SYNOPSIS
        Invokes the function associated with each provided checkbox

    .PARAMETER CheckBox
        The checkbox to invoke

    .PARAMETER undo
        Indicates whether to undo the operation contained in the checkbox

    .PARAMETER KeepServiceStartup
        Indicates whether to override the startup of a service with the one given from WinUtil,
        or to keep the startup of said service, if it was changed by the user, or another program, from its default value.
    #>

    param(
        $CheckBox,
        $undo = $false,
        $KeepServiceStartup = $true
    )

    Write-Debug "Tweaks: $($CheckBox)"
    if($undo){
        $Values = @{
            Registry = "OriginalValue"
            ScheduledTask = "OriginalState"
            Service = "OriginalType"
            ScriptType = "UndoScript"
        }

    }
    Else{
        $Values = @{
            Registry = "Value"
            ScheduledTask = "State"
            Service = "StartupType"
            OriginalService = "OriginalType"
            ScriptType = "InvokeScript"
        }
    }
    if($sync.configs.tweaks.$CheckBox.ScheduledTask){
        $sync.configs.tweaks.$CheckBox.ScheduledTask | ForEach-Object {
            Write-Debug "$($psitem.Name) and state is $($psitem.$($values.ScheduledTask))"
            Set-WinUtilScheduledTask -Name $psitem.Name -State $psitem.$($values.ScheduledTask)
        }
    }
    if($sync.configs.tweaks.$CheckBox.service){
        Write-Debug "KeepServiceStartup is $KeepServiceStartup"
        $sync.configs.tweaks.$CheckBox.service | ForEach-Object {
            $changeservice = $true
            
	    # The check for !($undo) is required, without it the script will throw an error for accessing unavailable memeber, which's the 'OriginalService' Property
            if($KeepServiceStartup -AND !($undo)) {
                try {
                    # Check if the service exists
                    $service = Get-Service -Name $psitem.Name -ErrorAction Stop
                    if(!($service.StartType.ToString() -eq $psitem.$($values.OriginalService))) {
                        Write-Debug "Service $($service.Name) was changed in the past to $($service.StartType.ToString()) from it's original type of $($psitem.$($values.OriginalService)), will not change it to $($psitem.$($values.service))"
                        $changeservice = $false
                    }
                }
                catch [System.ServiceProcess.ServiceNotFoundException] {
                    Write-Warning "Service $($psitem.Name) was not found"
                }
            }

            if($changeservice) {
                Write-Debug "$($psitem.Name) and state is $($psitem.$($values.service))"
                Set-WinUtilService -Name $psitem.Name -StartupType $psitem.$($values.Service)
            }
        }
    }
    if($sync.configs.tweaks.$CheckBox.registry){
        $sync.configs.tweaks.$CheckBox.registry | ForEach-Object {
            Write-Debug "$($psitem.Name) and state is $($psitem.$($values.registry))"
            Set-WinUtilRegistry -Name $psitem.Name -Path $psitem.Path -Type $psitem.Type -Value $psitem.$($values.registry)
        }
    }
    if($sync.configs.tweaks.$CheckBox.$($values.ScriptType)){
        $sync.configs.tweaks.$CheckBox.$($values.ScriptType) | ForEach-Object {
            Write-Debug "$($psitem) and state is $($psitem.$($values.ScriptType))"
            $Scriptblock = [scriptblock]::Create($psitem)
            Invoke-WinUtilScript -ScriptBlock $scriptblock -Name $CheckBox
        }
    }

    if(!$undo){
        if($sync.configs.tweaks.$CheckBox.appx){
            $sync.configs.tweaks.$CheckBox.appx | ForEach-Object {
                Write-Debug "UNDO $($psitem.Name)"
                Remove-WinUtilAPPX -Name $psitem
            }
        }

    }
}
function Invoke-WinUtilVerboseLogon {
    <#
    .SYNOPSIS
        Disables/Enables VerboseLogon Messages
    .PARAMETER Enabled
        Indicates whether to enable or disable VerboseLogon messages
    #>
    Param($Enabled)
    Try{
        if ($Enabled -eq $false){
            Write-Host "Enabling Verbose Logon Messages"
            $value = 1
        }
        else {
            Write-Host "Disabling Verbose Logon Messages"
            $value = 0
        }
        $Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        Set-ItemProperty -Path $Path -Name VerboseStatus -Value $value
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Remove-WinUtilAPPX {
    <#

    .SYNOPSIS
        Removes all APPX packages that match the given name

    .PARAMETER Name
        The name of the APPX package to remove

    .EXAMPLE
        Remove-WinUtilAPPX -Name "Microsoft.Microsoft3DViewer"

    #>
    param (
        $Name
    )

    Try {
        Write-Host "Removing $Name"
        Get-AppxPackage "*$Name*" | Remove-AppxPackage -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like "*$Name*" | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    }
    Catch [System.Exception] {
        if ($psitem.Exception.Message -like "*The requested operation requires elevation*") {
            Write-Warning "Unable to uninstall $name due to a Security Exception"
        }
        else {
            Write-Warning "Unable to uninstall $name due to unhandled exception"
            Write-Warning $psitem.Exception.StackTrace
        }
    }
    Catch{
        Write-Warning "Unable to uninstall $name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Set-WinUtilDNS {
    <#

    .SYNOPSIS
        Sets the DNS of all interfaces that are in the "Up" state. It will lookup the values from the DNS.Json file

    .PARAMETER DNSProvider
        The DNS provider to set the DNS server to

    .EXAMPLE
        Set-WinUtilDNS -DNSProvider "google"

    #>
    param($DNSProvider)
    if($DNSProvider -eq "Default"){return}
    Try{
        $Adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
        Write-Host "Ensuring DNS is set to $DNSProvider on the following interfaces"
        Write-Host $($Adapters | Out-String)

        Foreach ($Adapter in $Adapters){
            if($DNSProvider -eq "DHCP"){
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ResetServerAddresses
            }
            Else{
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ServerAddresses ("$($sync.configs.dns.$DNSProvider.Primary)", "$($sync.configs.dns.$DNSProvider.Secondary)")
            }
        }
    }
    Catch{
        Write-Warning "Unable to set DNS Provider due to an unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Set-WinUtilRegistry {
    <#

    .SYNOPSIS
        Modifies the registry based on the given inputs

    .PARAMETER Name
        The name of the key to modify

    .PARAMETER Path
        The path to the key

    .PARAMETER Type
        The type of value to set the key to

    .PARAMETER Value
        The value to set the key to

    .EXAMPLE
        Set-WinUtilRegistry -Name "PublishUserActivities" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Type "DWord" -Value "0"

    #>
    param (
        $Name,
        $Path,
        $Type,
        $Value
    )

    Try{
        if(!(Test-Path 'HKU:\')){New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS}

        If (!(Test-Path $Path)) {
            Write-Host "$Path was not found, Creating..."
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        Write-Host "Set $Path\$Name to $Value"
        Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $Value -Force -ErrorAction Stop | Out-Null
    }
    Catch [System.Security.SecurityException] {
        Write-Warning "Unable to set $Path\$Name to $Value due to a Security Exception"
    }
    Catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
    }
    Catch{
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
function Set-WinUtilScheduledTask {
    <#

    .SYNOPSIS
        Enables/Disables the provided Scheduled Task

    .PARAMETER Name
        The path to the Scheduled Task

    .PARAMETER State
        The State to set the Task to

    .EXAMPLE
        Set-WinUtilScheduledTask -Name "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -State "Disabled"

    #>
    param (
        $Name,
        $State
    )

    Try{
        if($State -eq "Disabled"){
            Write-Host "Disabling Scheduled Task $Name"
            Disable-ScheduledTask -TaskName $Name -ErrorAction Stop
        }
        if($State -eq "Enabled"){
            Write-Host "Enabling Scheduled Task $Name"
            Enable-ScheduledTask -TaskName $Name -ErrorAction Stop
        }
    }
    Catch [System.Exception]{
        if($psitem.Exception.Message -like "*The system cannot find the file specified*"){
            Write-Warning "Scheduled Task $name was not Found"
        }
        Else{
            Write-Warning "Unable to set $Name due to unhandled exception"
            Write-Warning $psitem.Exception.Message
        }
    }
    Catch{
        Write-Warning "Unable to run script for $name due to unhandled exception"
        Write-Warning $psitem.Exception.StackTrace
    }
}
Function Set-WinUtilService {
    <#

    .SYNOPSIS
        Changes the startup type of the given service

    .PARAMETER Name
        The name of the service to modify

    .PARAMETER StartupType
        The startup type to set the service to

    .EXAMPLE
        Set-WinUtilService -Name "HomeGroupListener" -StartupType "Manual"

    #>
    param (
        $Name,
        $StartupType
    )
    try {
        Write-Host "Setting Service $Name to $StartupType"

        # Check if the service exists
        $service = Get-Service -Name $Name -ErrorAction Stop

        # Service exists, proceed with changing properties
        $service | Set-Service -StartupType $StartupType -ErrorAction Stop
    }
    catch [System.ServiceProcess.ServiceNotFoundException] {
        Write-Warning "Service $Name was not found"
    }
    catch {
        Write-Warning "Unable to set $Name due to unhandled exception"
        Write-Warning $_.Exception.Message
    }

}
function Set-WinUtilUITheme {
    <#

    .SYNOPSIS
        Sets the theme of the XAML file

    .PARAMETER inputXML
        A string representing the XAML object to modify

    .PARAMETER themeName
        The name of the theme to set the XAML to. Defaults to 'matrix'

    .EXAMPLE
        Set-WinUtilUITheme -inputXAML $inputXAML

    #>
    param
    (
         [Parameter(Mandatory=$true, Position=0)]
         [string] $inputXML,
         [Parameter(Mandatory=$false, Position=1)]
         [string] $themeName = 'matrix'
    )

    try {
        # Convert the JSON to a PowerShell object
        $themes = $sync.configs.themes
        # Select the specified theme
        $selectedTheme = $themes.$themeName

        if ($selectedTheme) {
            # Loop through all key-value pairs in the selected theme
            foreach ($property in $selectedTheme.PSObject.Properties) {
                $key = $property.Name
                $value = $property.Value
                # Add curly braces around the key
                $formattedKey = "{$key}"
                # Replace the key with the value in the input XML
                $inputXML = $inputXML.Replace($formattedKey, $value)
            }
        }
        else {
            Write-Host "Theme '$themeName' not found."
        }

    }
    catch {
        Write-Warning "Unable to apply theme"
        Write-Warning $psitem.Exception.StackTrace
    }

    return $inputXML;
}
function Show-CustomDialog {
    <#
    .SYNOPSIS
    Displays a custom dialog box with an image, heading, message, and an OK button.
    
    .DESCRIPTION
    This function creates a custom dialog box with the specified message and additional elements such as an image, heading, and an OK button. The dialog box is designed with a green border, rounded corners, and a black background.
    
    .PARAMETER Message
    The message to be displayed in the dialog box.

    .PARAMETER Width
    The width of the custom dialog window.

    .PARAMETER Height
    The height of the custom dialog window.
    
    .EXAMPLE
    Show-CustomDialog -Message "This is a custom dialog with a message and an image above." -Width 300 -Height 200
    
    #>
    param(
        [string]$Message,
        [int]$Width = 300,
        [int]$Height = 200
    )

    Add-Type -AssemblyName PresentationFramework

    # Define theme colors
    $foregroundColor = [Windows.Media.Brushes]::White
    $backgroundColor = [Windows.Media.Brushes]::Black
    $font = New-Object Windows.Media.FontFamily("Consolas")
    $borderColor = [Windows.Media.Brushes]::Green
    $buttonBackgroundColor = [Windows.Media.Brushes]::Black
    $buttonForegroundColor = [Windows.Media.Brushes]::White
    $shadowColor = [Windows.Media.ColorConverter]::ConvertFromString("#AAAAAAAA")

    # Create a custom dialog window
    $dialog = New-Object Windows.Window
    $dialog.Title = "About"
    $dialog.Height = $Height
    $dialog.Width = $Width
    $dialog.Margin = New-Object Windows.Thickness(10)  # Add margin to the entire dialog box
    $dialog.WindowStyle = [Windows.WindowStyle]::None  # Remove title bar and window controls
    $dialog.ResizeMode = [Windows.ResizeMode]::NoResize  # Disable resizing
    $dialog.WindowStartupLocation = [Windows.WindowStartupLocation]::CenterScreen  # Center the window
    $dialog.Foreground = $foregroundColor
    $dialog.Background = $backgroundColor
    $dialog.FontFamily = $font

    # Create a Border for the green edge with rounded corners
    $border = New-Object Windows.Controls.Border
    $border.BorderBrush = $borderColor
    $border.BorderThickness = New-Object Windows.Thickness(1)  # Adjust border thickness as needed
    $border.CornerRadius = New-Object Windows.CornerRadius(10)  # Adjust the radius for rounded corners

    # Create a drop shadow effect
    $dropShadow = New-Object Windows.Media.Effects.DropShadowEffect
    $dropShadow.Color = $shadowColor
    $dropShadow.Direction = 270
    $dropShadow.ShadowDepth = 5
    $dropShadow.BlurRadius = 10

    # Apply drop shadow effect to the border
    $dialog.Effect = $dropShadow

    $dialog.Content = $border

    # Create a grid for layout inside the Border
    $grid = New-Object Windows.Controls.Grid
    $border.Child = $grid

    # Add the following line to show gridlines
    #$grid.ShowGridLines = $true

    # Add the following line to set the background color of the grid
    $grid.Background = [Windows.Media.Brushes]::Transparent
    # Add the following line to make the Grid stretch
    $grid.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch
    $grid.VerticalAlignment = [Windows.VerticalAlignment]::Stretch

    # Add the following line to make the Border stretch
    $border.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch
    $border.VerticalAlignment = [Windows.VerticalAlignment]::Stretch


    # Set up Row Definitions
    $row0 = New-Object Windows.Controls.RowDefinition
    $row0.Height = [Windows.GridLength]::Auto

    $row1 = New-Object Windows.Controls.RowDefinition
    $row1.Height = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)

    $row2 = New-Object Windows.Controls.RowDefinition
    $row2.Height = [Windows.GridLength]::Auto

    # Add Row Definitions to Grid
    $grid.RowDefinitions.Add($row0)
    $grid.RowDefinitions.Add($row1)
    $grid.RowDefinitions.Add($row2)
        
    # Add StackPanel for horizontal layout with margins
    $stackPanel = New-Object Windows.Controls.StackPanel
    $stackPanel.Margin = New-Object Windows.Thickness(10)  # Add margins around the stack panel
    $stackPanel.Orientation = [Windows.Controls.Orientation]::Horizontal
    $stackPanel.HorizontalAlignment = [Windows.HorizontalAlignment]::Left  # Align to the left
    $stackPanel.VerticalAlignment = [Windows.VerticalAlignment]::Top  # Align to the top

    $grid.Children.Add($stackPanel)
    [Windows.Controls.Grid]::SetRow($stackPanel, 0)  # Set the row to the second row (0-based index)

    $viewbox = New-Object Windows.Controls.Viewbox
    $viewbox.Width = 25
    $viewbox.Height = 25
    
    # Combine the paths into a single string
#     $cttLogoPath = @"
#     M174 1094 c-4 -14 -4 -55 -2 -92 3 -57 9 -75 41 -122 41 -60 45 -75 22 -84 -25 -9 -17 -21 30 -44 l45 -22 0 -103 c0 -91 3 -109 26 -155 30 -60 65 -87 204 -157 l95 -48 110 58 c184 96 205 127 205 293 l0 108 45 22 c47 23 55 36 30 46 -22 8 -18 30 9 63 13 16 34 48 46 71 20 37 21 52 15 116 l-6 73 -69 -23 c-38 -12 -137 -59 -220 -103 -82 -45 -160 -81 -171 -81 -12 0 -47 15 -78 34 -85 51 -239 127 -309 151 l-62 22 -6 -23z m500 -689 c20 -8 36 -19 36 -24 0 -18 -53 -51 -80 -51 -28 0 -80 33 -80 51 0 10 55 38 76 39 6 0 28 -7 48 -15z
#     M177 711 c-19 -88 4 -242 49 -318 43 -74 107 -127 232 -191 176 -90 199 -84 28 7 -169 91 -214 129 -258 220 -29 58 -32 74 -37 190 -4 90 -8 116 -14 92z
#     M1069 610 c-4 -131 -5 -137 -38 -198 -43 -79 -89 -119 -210 -181 -53 -27 -116 -61 -141 -76 -74 -43 -6 -20 115 40 221 109 296 217 294 425 -1 144 -16 137 -20 -10z
# "@
$cttLogoPath = @"
           M 18.00,14.00
           C 18.00,14.00 45.00,27.74 45.00,27.74
             45.00,27.74 57.40,34.63 57.40,34.63
             57.40,34.63 59.00,43.00 59.00,43.00
             59.00,43.00 59.00,83.00 59.00,83.00
             55.35,81.66 46.99,77.79 44.72,74.79
             41.17,70.10 42.01,59.80 42.00,54.00
             42.00,51.62 42.20,48.29 40.98,46.21
             38.34,41.74 25.78,38.60 21.28,33.79
             16.81,29.02 18.00,20.20 18.00,14.00 Z
           M 107.00,14.00
           C 109.01,19.06 108.93,30.37 104.66,34.21
             100.47,37.98 86.38,43.10 84.60,47.21
             83.94,48.74 84.01,51.32 84.00,53.00
             83.97,57.04 84.46,68.90 83.26,72.00
             81.06,77.70 72.54,81.42 67.00,83.00
             67.00,83.00 67.00,43.00 67.00,43.00
             67.00,43.00 67.99,35.63 67.99,35.63
             67.99,35.63 80.00,28.26 80.00,28.26
             80.00,28.26 107.00,14.00 107.00,14.00 Z
           M 19.00,46.00
           C 21.36,47.14 28.67,50.71 30.01,52.63
             31.17,54.30 30.99,57.04 31.00,59.00
             31.04,65.41 30.35,72.16 33.56,78.00
             38.19,86.45 46.10,89.04 54.00,93.31
             56.55,94.69 60.10,97.20 63.00,97.22
             65.50,97.24 68.77,95.36 71.00,94.25
             76.42,91.55 84.51,87.78 88.82,83.68
             94.56,78.20 95.96,70.59 96.00,63.00
             96.01,60.24 95.59,54.63 97.02,52.39
             98.80,49.60 103.95,47.87 107.00,47.00
             107.00,47.00 107.00,67.00 107.00,67.00
             106.90,87.69 96.10,93.85 80.00,103.00
             76.51,104.98 66.66,110.67 63.00,110.52
             60.33,110.41 55.55,107.53 53.00,106.25
             46.21,102.83 36.63,98.57 31.04,93.68
             16.88,81.28 19.00,62.88 19.00,46.00 Z
"@
    
    # Add SVG path
    $svgPath = New-Object Windows.Shapes.Path
    $svgPath.Data = [Windows.Media.Geometry]::Parse($cttLogoPath)
    $svgPath.Fill = $foregroundColor  # Set fill color to white

    # Add SVG path to Viewbox
    $viewbox.Child = $svgPath
    
    # Add SVG path to the stack panel
    $stackPanel.Children.Add($viewbox)

    # Add "Winutil" text
    $winutilTextBlock = New-Object Windows.Controls.TextBlock
    $winutilTextBlock.Text = "Winutil"
    $winutilTextBlock.FontSize = 18  # Adjust font size as needed
    $winutilTextBlock.Foreground = $foregroundColor
    $winutilTextBlock.Margin = New-Object Windows.Thickness(10, 5, 10, 5)  # Add margins around the text block
    $stackPanel.Children.Add($winutilTextBlock)

    # Add TextBlock for information with text wrapping and margins
    $messageTextBlock = New-Object Windows.Controls.TextBlock
    $messageTextBlock.Text = $Message
    $messageTextBlock.TextWrapping = [Windows.TextWrapping]::Wrap  # Enable text wrapping
    $messageTextBlock.HorizontalAlignment = [Windows.HorizontalAlignment]::Left
    $messageTextBlock.VerticalAlignment = [Windows.VerticalAlignment]::Top
    $messageTextBlock.Margin = New-Object Windows.Thickness(10)  # Add margins around the text block
    $grid.Children.Add($messageTextBlock)
    [Windows.Controls.Grid]::SetRow($messageTextBlock, 1)  # Set the row to the second row (0-based index)

    # Add OK button
    $okButton = New-Object Windows.Controls.Button
    $okButton.Content = "OK"
    $okButton.Width = 80
    $okButton.Height = 30
    $okButton.HorizontalAlignment = [Windows.HorizontalAlignment]::Center
    $okButton.VerticalAlignment = [Windows.VerticalAlignment]::Bottom
    $okButton.Margin = New-Object Windows.Thickness(0, 0, 0, 10)
    $okButton.Background = $buttonBackgroundColor
    $okButton.Foreground = $buttonForegroundColor
    $okButton.BorderBrush = $borderColor
    $okButton.Add_Click({
        $dialog.Close()
    })
    $grid.Children.Add($okButton)
    [Windows.Controls.Grid]::SetRow($okButton, 2)  # Set the row to the third row (0-based index)

    # Handle Escape key press to close the dialog
    $dialog.Add_KeyDown({
        if ($_.Key -eq 'Escape') {
            $dialog.Close()
        }
    })

    # Set the OK button as the default button (activated on Enter)
    $okButton.IsDefault = $true

    # Show the custom dialog
    $dialog.ShowDialog()
}
function Test-WinUtilPackageManager {
    <#

    .SYNOPSIS
        Checks if Winget and/or Choco are installed

    .PARAMETER winget
        Check if Winget is installed

    .PARAMETER choco
        Check if Chocolatey is installed

    #>

    Param(
        [System.Management.Automation.SwitchParameter]$winget,
        [System.Management.Automation.SwitchParameter]$choco
    )

    $status = "not-installed"

    if ($winget) {
        # Install Winget if not detected
        $wingetExists = Get-Command -Name winget -ErrorAction SilentlyContinue

        if ($wingetExists) {
            # Check Winget Version
            $wingetVersionFull = (winget --version) # Full Version without 'v'.

            # Check if Preview Version
            if ($wingetVersionFull.Contains("-preview")) {
                $wingetVersion = $wingetVersionFull.Trim("-preview")
                $wingetPreview = $true
            } else {
                $wingetVersion = $wingetVersionFull
                $wingetPreview = $false
            }

            # Check if Winget's Version is too old.
            $wingetCurrentVersion = [System.Version]::Parse($wingetVersion.Trim('v'))
            # Grabs the latest release of Winget from the Github API for version check process.
            $response = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/Winget-cli/releases/latest" -Method Get -ErrorAction Stop
            $wingetLatestVersion = [System.Version]::Parse(($response.tag_name).Trim('v')) #Stores version number of latest release.
            $wingetOutdated = $wingetCurrentVersion -lt $wingetLatestVersion
            Write-Host "===========================================" -ForegroundColor Green
            Write-Host "---        Winget is installed          ---" -ForegroundColor Green
            Write-Host "===========================================" -ForegroundColor Green
            Write-Host "Version: $wingetVersionFull" -ForegroundColor White

            if (!$wingetPreview) {
                Write-Host "    - Winget is a release version." -ForegroundColor Green
            } else {
                Write-Host "    - Winget is a preview version. Unexpected problems may occur." -ForegroundColor Yellow
            }

            if (!$wingetOutdated) {
                Write-Host "    - Winget is Up to Date" -ForegroundColor Green
                $status = "installed"
            }
            else {
                Write-Host "    - Winget is Out of Date" -ForegroundColor Red
                $status = "outdated"
            }
        } else {        
            Write-Host "===========================================" -ForegroundColor Red
            Write-Host "---      Winget is not installed        ---" -ForegroundColor Red
            Write-Host "===========================================" -ForegroundColor Red
            $status = "not-installed"
        }
    }

    if ($choco) {
        if ((Get-Command -Name choco -ErrorAction Ignore) -and ($chocoVersion = (Get-Item "$env:ChocolateyInstall\choco.exe" -ErrorAction Ignore).VersionInfo.ProductVersion)) {
            Write-Host "===========================================" -ForegroundColor Green
            Write-Host "---      Chocolatey is installed        ---" -ForegroundColor Green
            Write-Host "===========================================" -ForegroundColor Green
            Write-Host "Version: v$chocoVersion" -ForegroundColor White
            $status = "installed"
        } else {
            Write-Host "===========================================" -ForegroundColor Red
            Write-Host "---    Chocolatey is not installed      ---" -ForegroundColor Red
            Write-Host "===========================================" -ForegroundColor Red
            $status = "not-installed"
        }
    }

    return $status
}
Function Update-WinUtilProgramWinget {

    <#

    .SYNOPSIS
        This will update all programs using Winget

    #>

    [ScriptBlock]$wingetinstall = {

        $host.ui.RawUI.WindowTitle = """Winget Install"""

        Start-Transcript $ENV:TEMP\winget-update.log -Append
        winget upgrade --all --accept-source-agreements --accept-package-agreements --scope=machine --silent

    }

    $global:WinGetInstall = Start-Process -Verb runas powershell -ArgumentList "-command invoke-command -scriptblock {$wingetinstall} -argumentlist '$($ProgramsToInstall -join ",")'" -PassThru

}

function Invoke-ScratchDialog {

    <#

    .SYNOPSIS
        Enable Editable Text box Alternate Scartch path

    .PARAMETER Button
    #>
    $sync.WPFMicrowinISOScratchDir.IsChecked 
 

    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $Dialog.SelectedPath =          $sync.MicrowinScratchDirBox.Text
    $Dialog.ShowDialog() 
    $filePath = $Dialog.SelectedPath
        Write-Host "No ISO is chosen+  $filePath"

    if ([string]::IsNullOrEmpty($filePath))
    {
        Write-Host "No Folder had chosen"
        return
    }
    
       $sync.MicrowinScratchDirBox.Text =  Join-Path $filePath "\"

}
function Invoke-WPFButton {

    <#

    .SYNOPSIS
        Invokes the function associated with the clicked button

    .PARAMETER Button
        The name of the button that was clicked

    #>

    Param ([string]$Button)

    # Use this to get the name of the button
    #[System.Windows.MessageBox]::Show("$Button","Chris Titus Tech's Windows Utility","OK","Info")

    Switch -Wildcard ($Button){

        "WPFTab?BT" {Invoke-WPFTab $Button}
        "WPFinstall" {Invoke-WPFInstall}
        "WPFuninstall" {Invoke-WPFUnInstall}
        "WPFInstallUpgrade" {Invoke-WPFInstallUpgrade}
        "WPFdesktop" {Invoke-WPFPresets "Desktop"}
        "WPFlaptop" {Invoke-WPFPresets "laptop"}
        "WPFminimal" {Invoke-WPFPresets "minimal"}
        "WPFclear" {Invoke-WPFPresets -preset $null -imported $true}
        "WPFclearWinget" {Invoke-WPFPresets -preset $null -imported $true -CheckBox "WPFInstall"}
        "WPFtweaksbutton" {Invoke-WPFtweaksbutton}
        "WPFOOSUbutton" {Invoke-WPFOOSU -action "customize"}
        "WPFAddUltPerf" {Invoke-WPFUltimatePerformance -State "Enabled"}
        "WPFRemoveUltPerf" {Invoke-WPFUltimatePerformance -State "Disabled"}
        "WPFundoall" {Invoke-WPFundoall}
        "WPFFeatureInstall" {Invoke-WPFFeatureInstall}
        "WPFPanelDISM" {Invoke-WPFPanelDISM}
        "WPFPanelAutologin" {Invoke-WPFPanelAutologin}
        "WPFPanelcontrol" {Invoke-WPFControlPanel -Panel $button}
        "WPFPanelnetwork" {Invoke-WPFControlPanel -Panel $button}
        "WPFPanelpower" {Invoke-WPFControlPanel -Panel $button}
        "WPFPanelregion" {Invoke-WPFControlPanel -Panel $button}
        "WPFPanelsound" {Invoke-WPFControlPanel -Panel $button}
        "WPFPanelsystem" {Invoke-WPFControlPanel -Panel $button}
        "WPFPaneluser" {Invoke-WPFControlPanel -Panel $button}
        "WPFUpdatesdefault" {Invoke-WPFUpdatesdefault}
        "WPFFixesUpdate" {Invoke-WPFFixesUpdate}
        "WPFFixesWinget" {Invoke-WPFFixesWinget}
        "WPFRunAdobeCCCleanerTool" {Invoke-WPFRunAdobeCCCleanerTool}
        "WPFFixesNetwork" {Invoke-WPFFixesNetwork}
        "WPFUpdatesdisable" {Invoke-WPFUpdatesdisable}
        "WPFUpdatessecurity" {Invoke-WPFUpdatessecurity}
        "WPFWinUtilShortcut" {Invoke-WPFShortcut -ShortcutToAdd "WinUtil" -RunAsAdmin $true}
        "WPFGetInstalled" {Invoke-WPFGetInstalled -CheckBox "winget"}
        "WPFGetInstalledTweaks" {Invoke-WPFGetInstalled -CheckBox "tweaks"}
        "WPFGetIso" {Invoke-WPFGetIso}
        "WPFMicrowin" {Invoke-WPFMicrowin}
        "WPFCloseButton" {Invoke-WPFCloseButton}
        "MicrowinScratchDirBT" {Invoke-ScratchDialog}
    }
}
function Invoke-WPFCloseButton {

    <#

    .SYNOPSIS
        Close application

    .PARAMETER Button
    #>
    $sync["Form"].Close()
    Write-Host "Bye bye!"
}
function Invoke-WPFControlPanel {
    <#

    .SYNOPSIS
        Opens the requested legacy panel

    .PARAMETER Panel
        The panel to open

    #>
    param($Panel)

    switch ($Panel){
        "WPFPanelcontrol" {cmd /c control}
        "WPFPanelnetwork" {cmd /c ncpa.cpl}
        "WPFPanelpower"   {cmd /c powercfg.cpl}
        "WPFPanelregion"  {cmd /c intl.cpl}
        "WPFPanelsound"   {cmd /c mmsys.cpl}
        "WPFPanelsystem"  {cmd /c sysdm.cpl}
        "WPFPaneluser"    {cmd /c "control userpasswords2"}
    }
}
function Invoke-WPFFeatureInstall {
    <#

    .SYNOPSIS
        Installs selected Windows Features

    #>

    if($sync.ProcessRunning){
        $msg = "[Invoke-WPFFeatureInstall] Install process is currently running."
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $Features = (Get-WinUtilCheckBoxes)["WPFFeature"]

    Invoke-WPFRunspace -ArgumentList $Features -DebugPreference $DebugPreference -ScriptBlock {
        param($Features, $DebugPreference)

        $sync.ProcessRunning = $true

        Invoke-WinUtilFeatureInstall $Features

        $sync.ProcessRunning = $false
        Write-Host "==================================="
        Write-Host "---   Features are Installed    ---"
        Write-Host "---  A Reboot may be required   ---"
        Write-Host "==================================="
    }
}
function Invoke-WPFFixesNetwork {
    <#

    .SYNOPSIS
        Resets various network configurations

    #>

    Write-Host "Resetting Network with netsh"

    # Reset WinSock catalog to a clean state
    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winsock", "reset"
    # Resets WinHTTP proxy setting to DIRECT
    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winhttp", "reset", "proxy"
    # Removes all user configured IP settings
    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "int", "ip", "reset"

    Write-Host "Process complete. Please reboot your computer."

    $ButtonType = [System.Windows.MessageBoxButton]::OK
    $MessageboxTitle = "Network Reset "
    $Messageboxbody = ("Stock settings loaded.`n Please reboot your computer")
    $MessageIcon = [System.Windows.MessageBoxImage]::Information

    [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
    Write-Host "=========================================="
    Write-Host "-- Network Configuration has been Reset --"
    Write-Host "=========================================="
}
function Invoke-WPFFixesUpdate {

    <#

    .SYNOPSIS
        Performs various tasks in an attempt to repair Windows Update

    .DESCRIPTION
        1. (Aggressive Only) Scans the system for corruption using chkdsk, SFC, and DISM
            Steps:
                1. Runs chkdsk /scan /perf
                    /scan - Runs an online scan on the volume
                    /perf - Uses more system resources to complete a scan as fast as possible
                2. Runs SFC /scannow
                    /scannow - Scans integrity of all protected system files and repairs files with problems when possible
                3. Runs DISM /Online /Cleanup-Image /RestoreHealth
                    /Online - Targets the running operating system
                    /Cleanup-Image - Performs cleanup and recovery operations on the image
                    /RestoreHealth - Scans the image for component store corruption and attempts to repair the corruption using Windows Update
                4. Runs SFC /scannow
                    Ran twice in case DISM repaired SFC
        2. Stops Windows Update Services
        3. Remove the QMGR Data file, which stores BITS jobs
        4. (Aggressive Only) Renames the DataStore and CatRoot2 folders
            DataStore - Contains the Windows Update History and Log Files
            CatRoot2 - Contains the Signatures for Windows Update Packages
        5. Renames the Windows Update Download Folder
        6. Deletes the Windows Update Log
        7. (Aggressive Only) Resets the Security Descriptors on the Windows Update Services
        8. Reregisters the BITS and Windows Update DLLs
        9. Removes the WSUS client settings
        10. Resets WinSock
        11. Gets and deletes all BITS jobs
        12. Sets the startup type of the Windows Update Services then starts them
        13. Forces Windows Update to check for updates

    .PARAMETER Aggressive
        If specified, the script will take additional steps to repair Windows Update that are more dangerous, take a significant amount of time, or are generally unnecessary

    #>

    param($Aggressive = $false)

    Write-Progress -Id 0 -Activity "Repairing Windows Update" -PercentComplete 0
    # Wait for the first progress bar to show, otherwise the second one won't show
    Start-Sleep -Milliseconds 200

    if ($Aggressive) {
        # Scan system for corruption
        Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Scanning for corruption..." -PercentComplete 0
        Write-Progress -Id 1 -ParentId 0 -Activity "Scanning for corruption" -Status "Running chkdsk..." -PercentComplete 0
        # 2>&1 redirects stdout, alowing iteration over the output
        chkdsk.exe /scan /perf 2>&1 | ForEach-Object {
            # Write stdout to the Verbose stream
            Write-Verbose $_

            # Get the index of the total percentage
            $index = $_.IndexOf("Total:")
            if (
                # If the percent is found
                ($percent = try {(
                    $_.Substring(
                        $index + 6,
                        $_.IndexOf("%", $index) - $index - 6
                    )
                ).Trim()} catch {0}) `
                <# And the current percentage is greater than the previous one #>`
                -and $percent -gt $oldpercent
            ){
                # Update the progress bar
                $oldpercent = $percent
                Write-Progress -Id 1 -ParentId 0 -Activity "Scanning for corruption" -Status "Running chkdsk... ($percent%)" -PercentComplete $percent
            }
        }

        Write-Progress -Id 1 -ParentId 0 -Activity "Scanning for corruption" -Status "Running SFC..." -PercentComplete 0
        $oldpercent = 0
        # SFC has a bug when redirected which causes it to output only when the stdout buffer is full, causing the progress bar to move in chunks
        sfc /scannow 2>&1 | ForEach-Object {
            # Write stdout to the Verbose stream
            Write-Verbose $_

            # Filter for lines that contain a percentage that is greater than the previous one
            if (
                (
                    # Use a different method to get the percentage that accounts for SFC's Unicode output
                    [int]$percent = try {(
                        (
                            $_.Substring(
                                $_.IndexOf("n") + 2,
                                $_.IndexOf("%") - $_.IndexOf("n") - 2
                            ).ToCharArray() | Where-Object {$_}
                        ) -join ''
                    ).TrimStart()} catch {0}
                ) -and $percent -gt $oldpercent
            ){
                # Update the progress bar
                $oldpercent = $percent
                Write-Progress -Id 1 -ParentId 0 -Activity "Scanning for corruption" -Status "Running SFC... ($percent%)" -PercentComplete $percent
            }
        }

        Write-Progress -Id 1 -ParentId 0 -Activity "Scanning for corruption" -Status "Running DISM..." -PercentComplete 0
        $oldpercent = 0
        DISM /Online /Cleanup-Image /RestoreHealth | ForEach-Object {
            # Write stdout to the Verbose stream
            Write-Verbose $_

            # Filter for lines that contain a percentage that is greater than the previous one
            if (
                ($percent = try {
                    [int]($_ -replace "\[" -replace "=" -replace " " -replace "%" -replace "\]")
                } catch {0}) `
                -and $percent -gt $oldpercent
            ){
                # Update the progress bar
                $oldpercent = $percent
                Write-Progress -Id 1 -ParentId 0 -Activity "Scanning for corruption" -Status "Running DISM... ($percent%)" -PercentComplete $percent
            }
        }

        Write-Progress -Id 1 -ParentId 0 -Activity "Scanning for corruption" -Status "Running SFC again..." -PercentComplete 0
        $oldpercent = 0
        sfc /scannow 2>&1 | ForEach-Object {
            # Write stdout to the Verbose stream
            Write-Verbose $_

            # Filter for lines that contain a percentage that is greater than the previous one
            if (
                (
                    [int]$percent = try {(
                        (
                            $_.Substring(
                                $_.IndexOf("n") + 2,
                                $_.IndexOf("%") - $_.IndexOf("n") - 2
                            ).ToCharArray() | Where-Object {$_}
                        ) -join ''
                    ).TrimStart()} catch {0}
                ) -and $percent -gt $oldpercent
            ){
                # Update the progress bar
                $oldpercent = $percent
                Write-Progress -Id 1 -ParentId 0 -Activity "Scanning for corruption" -Status "Running SFC... ($percent%)" -PercentComplete $percent
            }
        }
        Write-Progress -Id 1 -ParentId 0 -Activity "Scanning for corruption" -Status "Completed" -PercentComplete 100
    }


    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Stopping Windows Update Services..." -PercentComplete 10
    # Stop the Windows Update Services
    Write-Progress -Id 2 -ParentId 0 -Activity "Stopping Services" -Status "Stopping BITS..." -PercentComplete 0
    Stop-Service -Name BITS -Force
    Write-Progress -Id 2 -ParentId 0 -Activity "Stopping Services" -Status "Stopping wuauserv..." -PercentComplete 20
    Stop-Service -Name wuauserv -Force
    Write-Progress -Id 2 -ParentId 0 -Activity "Stopping Services" -Status "Stopping appidsvc..." -PercentComplete 40
    Stop-Service -Name appidsvc -Force
    Write-Progress -Id 2 -ParentId 0 -Activity "Stopping Services" -Status "Stopping cryptsvc..." -PercentComplete 60
    Stop-Service -Name cryptsvc -Force
    Write-Progress -Id 2 -ParentId 0 -Activity "Stopping Services" -Status "Completed" -PercentComplete 100


    # Remove the QMGR Data file
    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Renaming/Removing Files..." -PercentComplete 20
    Write-Progress -Id 3 -ParentId 0 -Activity "Renaming/Removing Files" -Status "Removing QMGR Data files..." -PercentComplete 0
    Remove-Item "$env:allusersprofile\Application Data\Microsoft\Network\Downloader\qmgr*.dat" -ErrorAction SilentlyContinue


    if ($Aggressive) {
        # Rename the Windows Update Log and Signature Folders
        Write-Progress -Id 3 -ParentId 0 -Activity "Renaming/Removing Files" -Status "Renaming the Windows Update Log, Download, and Signature Folder..." -PercentComplete 20
        Rename-Item $env:systemroot\SoftwareDistribution\DataStore DataStore.bak -ErrorAction SilentlyContinue
        Rename-Item $env:systemroot\System32\Catroot2 catroot2.bak -ErrorAction SilentlyContinue
    }

    # Rename the Windows Update Download Folder
    Write-Progress -Id 3 -ParentId 0 -Activity "Renaming/Removing Files" -Status "Renaming the Windows Update Download Folder..." -PercentComplete 20
    Rename-Item $env:systemroot\SoftwareDistribution\Download Download.bak -ErrorAction SilentlyContinue

    # Delete the legacy Windows Update Log
    Write-Progress -Id 3 -ParentId 0 -Activity "Renaming/Removing Files" -Status "Removing the old Windows Update log..." -PercentComplete 80
    Remove-Item $env:systemroot\WindowsUpdate.log -ErrorAction SilentlyContinue
    Write-Progress -Id 3 -ParentId 0 -Activity "Renaming/Removing Files" -Status "Completed" -PercentComplete 100


    if ($Aggressive) {
        # Reset the Security Descriptors on the Windows Update Services
        Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Resetting the WU Service Security Descriptors..." -PercentComplete 25
        Write-Progress -Id 4 -ParentId 0 -Activity "Resetting the WU Service Security Descriptors" -Status "Resetting the BITS Security Descriptor..." -PercentComplete 0
        Start-Process -NoNewWindow -FilePath "sc.exe" -ArgumentList "sdset", "bits", "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)"
        Write-Progress -Id 4 -ParentId 0 -Activity "Resetting the WU Service Security Descriptors" -Status "Resetting the wuauserv Security Descriptor..." -PercentComplete 50
        Start-Process -NoNewWindow -FilePath "sc.exe" -ArgumentList "sdset", "wuauserv", "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)"
        Write-Progress -Id 4 -ParentId 0 -Activity "Resetting the WU Service Security Descriptors" -Status "Completed" -PercentComplete 100
    }


    # Reregister the BITS and Windows Update DLLs
    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Reregistering DLLs..." -PercentComplete 40
    $oldLocation = Get-Location
    Set-Location $env:systemroot\system32
    $i = 0
    $DLLs = @(
        "atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll",
        "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml.dll", "msxml3.dll",
        "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll",
        "rsaenh.dll", "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll",
        "oleaut32.dll", "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll",
        "wuaueng.dll", "wuaueng1.dll", "wucltui.dll", "wups.dll", "wups2.dll",
        "wuweb.dll", "qmgr.dll", "qmgrprxy.dll", "wucltux.dll", "muweb.dll", "wuwebv.dll"
    )
    foreach ($dll in $DLLs) {
        Write-Progress -Id 5 -ParentId 0 -Activity "Reregistering DLLs" -Status "Registering $dll..." -PercentComplete ($i / $DLLs.Count * 100)
        $i++
        Start-Process -NoNewWindow -FilePath "regsvr32.exe" -ArgumentList "/s", $dll
    }
    Set-Location $oldLocation
    Write-Progress -Id 5 -ParentId 0 -Activity "Reregistering DLLs" -Status "Completed" -PercentComplete 100


    # Remove the WSUS client settings
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate") {
        Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Removing WSUS client settings..." -PercentComplete 60
        Write-Progress -Id 6 -ParentId 0 -Activity "Removing WSUS client settings" -PercentComplete 0
        Start-Process -NoNewWindow -FilePath "REG" -ArgumentList "DELETE", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate", "/v", "AccountDomainSid", "/f" -RedirectStandardError $true
        Start-Process -NoNewWindow -FilePath "REG" -ArgumentList "DELETE", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate", "/v", "PingID", "/f" -RedirectStandardError $true
        Start-Process -NoNewWindow -FilePath "REG" -ArgumentList "DELETE", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate", "/v", "SusClientId", "/f" -RedirectStandardError $true
        Write-Progress -Id 6 -ParentId 0 -Activity "Removing WSUS client settings" -Status "Completed" -PercentComplete 100
    }


    # Reset WinSock
    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Resetting WinSock..." -PercentComplete 65
    Write-Progress -Id 7 -ParentId 0 -Activity "Resetting WinSock" -Status "Resetting WinSock..." -PercentComplete 0
    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winsock", "reset" -RedirectStandardOutput $true
    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "winhttp", "reset", "proxy" -RedirectStandardOutput $true
    Start-Process -NoNewWindow -FilePath "netsh" -ArgumentList "int", "ip", "reset" -RedirectStandardOutput $true
    Write-Progress -Id 7 -ParentId 0 -Activity "Resetting WinSock" -Status "Completed" -PercentComplete 100


    # Get and delete all BITS jobs
    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Deleting BITS jobs..." -PercentComplete 75
    Write-Progress -Id 8 -ParentId 0 -Activity "Deleting BITS jobs" -Status "Deleting BITS jobs..." -PercentComplete 0
    Get-BitsTransfer | Remove-BitsTransfer
    Write-Progress -Id 8 -ParentId 0 -Activity "Deleting BITS jobs" -Status "Completed" -PercentComplete 100


    # Change the startup type of the Windows Update Services and start them
    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Starting Windows Update Services..." -PercentComplete 90
    Write-Progress -Id 9 -ParentId 0 -Activity "Starting Windows Update Services" -Status "Starting BITS..." -PercentComplete 0
    Get-Service BITS | Set-Service -StartupType Manual -PassThru | Start-Service
    Write-Progress -Id 9 -ParentId 0 -Activity "Starting Windows Update Services" -Status "Starting wuauserv..." -PercentComplete 25
    Get-Service wuauserv | Set-Service -StartupType Manual -PassThru | Start-Service
    Write-Progress -Id 9 -ParentId 0 -Activity "Starting Windows Update Services" -Status "Starting AppIDSvc..." -PercentComplete 50
    # The AppIDSvc service is protected, so the startup type has to be changed in the registry
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\AppIDSvc" -Name "Start" -Value "3" # Manual
    Start-Service AppIDSvc
    Write-Progress -Id 9 -ParentId 0 -Activity "Starting Windows Update Services" -Status "Starting CryptSvc..." -PercentComplete 75
    Get-Service CryptSvc | Set-Service -StartupType Manual -PassThru | Start-Service
    Write-Progress -Id 9 -ParentId 0 -Activity "Starting Windows Update Services" -Status "Completed" -PercentComplete 100


    # Force Windows Update to check for updates
    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Forcing discovery..." -PercentComplete 95
    Write-Progress -Id 10 -ParentId 0 -Activity "Forcing discovery" -Status "Forcing discovery..." -PercentComplete 0
    (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()
    Start-Process -NoNewWindow -FilePath "wuauclt" -ArgumentList "/resetauthorization", "/detectnow"
    Write-Progress -Id 10 -ParentId 0 -Activity "Forcing discovery" -Status "Completed" -PercentComplete 100
    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Status "Completed" -PercentComplete 100

    $ButtonType = [System.Windows.MessageBoxButton]::OK
    $MessageboxTitle = "Reset Windows Update "
    $Messageboxbody = ("Stock settings loaded.`n Please reboot your computer")
    $MessageIcon = [System.Windows.MessageBoxImage]::Information

    [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
    Write-Host "==============================================="
    Write-Host "-- Reset All Windows Update Settings to Stock -"
    Write-Host "==============================================="

    # Remove the progress bars
    Write-Progress -Id 0 -Activity "Repairing Windows Update" -Completed
    Write-Progress -Id 1 -Activity "Scanning for corruption" -Completed
    Write-Progress -Id 2 -Activity "Stopping Services" -Completed
    Write-Progress -Id 3 -Activity "Renaming/Removing Files" -Completed
    Write-Progress -Id 4 -Activity "Resetting the WU Service Security Descriptors" -Completed
    Write-Progress -Id 5 -Activity "Reregistering DLLs" -Completed
    Write-Progress -Id 6 -Activity "Removing WSUS client settings" -Completed
    Write-Progress -Id 7 -Activity "Resetting WinSock" -Completed
    Write-Progress -Id 8 -Activity "Deleting BITS jobs" -Completed
    Write-Progress -Id 9 -Activity "Starting Windows Update Services" -Completed
    Write-Progress -Id 10 -Activity "Forcing discovery" -Completed
}
function Invoke-WPFFixesWinget {

    <#

    .SYNOPSIS
        Fixes Winget by running choco install winget 
    .DESCRIPTION
        BravoNorris for the fantastic idea of a button to reinstall winget
    #>

    Start-Process -FilePath "choco" -ArgumentList "install winget -y --force" -NoNewWindow -Wait

}
Function Invoke-WPFFormVariables {
    <#

    .SYNOPSIS
        Prints the logo

    #>
    #If ($global:ReadmeDisplay -ne $true) { Write-Host "If you need to reference this display again, run Get-FormVariables" -ForegroundColor Yellow; $global:ReadmeDisplay = $true }


    Write-Host ""
    Write-Host "    CCCCCCCCCCCCCTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT   "
    Write-Host " CCC::::::::::::CT:::::::::::::::::::::TT:::::::::::::::::::::T   "
    Write-Host "CC:::::::::::::::CT:::::::::::::::::::::TT:::::::::::::::::::::T  "
    Write-Host "C:::::CCCCCCCC::::CT:::::TT:::::::TT:::::TT:::::TT:::::::TT:::::T "
    Write-Host "C:::::C       CCCCCCTTTTTT  T:::::T  TTTTTTTTTTTT  T:::::T  TTTTTT"
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C                     T:::::T                T:::::T        "
    Write-Host "C:::::C       CCCCCC        T:::::T                T:::::T        "
    Write-Host "C:::::CCCCCCCC::::C      TT:::::::TT            TT:::::::TT       "
    Write-Host "CC:::::::::::::::C       T:::::::::T            T:::::::::T       "
    Write-Host "CCC::::::::::::C         T:::::::::T            T:::::::::T       "
    Write-Host "  CCCCCCCCCCCCC          TTTTTTTTTTT            TTTTTTTTTTT       "
    Write-Host ""
    Write-Host "====Chris Titus Tech====="
    Write-Host "=====Windows Toolbox====="

    #====DEBUG GUI Elements====

    #Write-Host "Found the following interactable elements from our form" -ForegroundColor Cyan
    #get-variable WPF*
}
function Invoke-WPFGetInstalled {
    <#

    .SYNOPSIS
        Invokes the function that gets the checkboxes to check in a new runspace

    .PARAMETER checkbox
        Indicates whether to check for installed 'winget' programs or applied 'tweaks'

    #>
    param($checkbox)

    if($sync.ProcessRunning){
        $msg = "[Invoke-WPFGetInstalled] Install process is currently running."
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    if(((Test-WinUtilPackageManager -winget) -eq "not-installed") -and $checkbox -eq "winget"){
        return
    }

    Invoke-WPFRunspace -ArgumentList $checkbox -DebugPreference $DebugPreference -ScriptBlock {
        param($checkbox, $DebugPreference)

        $sync.ProcessRunning = $true

        if($checkbox -eq "winget"){
            Write-Host "Getting Installed Programs..."
        }
        if($checkbox -eq "tweaks"){
            Write-Host "Getting Installed Tweaks..."
        }

        $Checkboxes = Invoke-WinUtilCurrentSystem -CheckBox $checkbox

        $sync.form.Dispatcher.invoke({
            foreach($checkbox in $Checkboxes){
                $sync.$checkbox.ischecked = $True
            }
        })

        Write-Host "Done..."
        $sync.ProcessRunning = $false
    }
}
function Invoke-WPFGetIso {
    <#
    .DESCRIPTION
    Function to get the path to Iso file for MicroWin, unpack that isom=, read basic information and populate the UI Options
    #>

    Write-Host "Invoking WPFGetIso"

    if($sync.ProcessRunning){
        $msg = "GetIso process is currently running."
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

  $sync.BusyMessage.Visibility="Visible"
    $sync.BusyText.Text="N Busy"


    Write-Host "         _                     __    __  _         "
	Write-Host "  /\/\  (_)  ___  _ __   ___  / / /\ \ \(_) _ __   "
	Write-Host " /    \ | | / __|| '__| / _ \ \ \/  \/ /| || '_ \  "
	Write-Host "/ /\/\ \| || (__ | |   | (_) | \  /\  / | || | | | "
	Write-Host "\/    \/|_| \___||_|    \___/   \/  \/  |_||_| |_| "

    $oscdimgPath = Join-Path $env:TEMP 'oscdimg.exe'   
   if( ! (Test-Path $oscdimgPath -PathType Leaf)  ) {
   $oscdimgPath = Join-Path '.\releases\' 'oscdimg.exe'   
}

    $oscdImgFound = [bool] (Get-Command -ErrorAction Ignore -Type Application oscdimg.exe) -or (Test-Path $oscdimgPath -PathType Leaf)
    Write-Host "oscdimg.exe on system: $oscdImgFound"
    
    if (!$oscdImgFound) 
    {
        $downloadFromGitHub = $sync.WPFMicrowinDownloadFromGitHub.IsChecked
        $sync.BusyMessage.Visibility="Hidden"

        if (!$downloadFromGitHub) 
        {
            # only show the message to people who did check the box to download from github, if you check the box 
            # you consent to downloading it, no need to show extra dialogs
            [System.Windows.MessageBox]::Show("oscdimge.exe is not found on the system, winutil will now attempt do download and install it using choco. This might take a long time.")
            # the step below needs choco to download oscdimg
            $chocoFound = [bool] (Get-Command -ErrorAction Ignore -Type Application choco)
            Write-Host "choco on system: $chocoFound"
            if (!$chocoFound) 
            {
                [System.Windows.MessageBox]::Show("choco.exe is not found on the system, you need choco to download oscdimg.exe")
                return
            }

            Start-Process -Verb runas -FilePath powershell.exe -ArgumentList "choco install windows-adk-oscdimg"
            [System.Windows.MessageBox]::Show("oscdimg is installed, now close, reopen PowerShell terminal and re-launch winutil.ps1")
            return
        }
        else {
            [System.Windows.MessageBox]::Show("oscdimge.exe is not found on the system, winutil will now attempt do download and install it from github. This might take a long time.")
            Get-Oscdimg -oscdimgPath $oscdimgPath
            $oscdImgFound = Test-Path $oscdimgPath -PathType Leaf
            if (!$oscdImgFound) {
                $msg = "oscdimg was not downloaded can not proceed"
                [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                return
            }
            else {
                Write-Host "oscdimg.exe was successfully downloaded from github"
            }
        }
    }

    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.initialDirectory = $initialDirectory
    $openFileDialog.filter = "ISO files (*.iso)| *.iso"
    $openFileDialog.ShowDialog() | Out-Null
    $filePath = $openFileDialog.FileName

    if ([string]::IsNullOrEmpty($filePath))
    {
        Write-Host "No ISO is chosen"
        $sync.BusyMessage.Visibility="Hidden"
        return
    }

    Write-Host "File path $($filePath)"
    if (-not (Test-Path -Path $filePath -PathType Leaf))
    {
        $msg = "File you've chosen doesn't exist"
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    # Detect the file size of the ISO and compare it with the free space of the system drive
    $isoSize = (Get-Item -Path $filePath).Length
    Write-Debug "Size of ISO file: $($isoSize) bytes"
    # Use this procedure to get the free space of the drive depending on where the user profile folder is stored.
    # This is done to guarantee a dynamic solution, as the installation drive may be mounted to a letter different than C
    $driveSpace = (Get-Volume -DriveLetter ([IO.Path]::GetPathRoot([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)).Replace(":\", "").Trim())).SizeRemaining
    Write-Debug "Free space on installation drive: $($driveSpace) bytes"
    if ($driveSpace -lt ($isoSize * 2))
    {
        # It's not critical and we _may_ continue. Output a warning
        Write-Warning "You may not have enough space for this operation. Proceed at your own risk."
    }
    elseif ($driveSpace -lt $isoSize)
    {
        # It's critical and we can't continue. Output an error
        Write-Host "You don't have enough space for this operation. You need at least $([Math]::Round(($isoSize / ([Math]::Pow(1024, 2))) * 2, 2)) MB of free space to copy the ISO files to a temp directory and to be able to perform additional operations."
        return
    }
    else 
    {
        Write-Host "You have enough space for this operation."
    }

    try {
        Write-Host "Mounting Iso. Please wait."
        $mountedISO = Mount-DiskImage -PassThru "$filePath"
        Write-Host "Done mounting Iso $mountedISO"
        $driveLetter = (Get-Volume -DiskImage $mountedISO).DriveLetter
        Write-Host "Iso mounted to '$driveLetter'"
    } catch {
        # @ChrisTitusTech  please copy this wiki and change the link below to your copy of the wiki
        Write-Error "Failed to mount the image. Error: $($_.Exception.Message)"
        Write-Error "This is NOT winutil's problem, your ISO might be corrupt, or there is a problem on the system"
        Write-Error "Please refer to this wiki for more details https://github.com/ChrisTitusTech/winutil/blob/main/wiki/Error-in-Winutil-MicroWin-during-ISO-mounting%2Cmd"
        return
    }
    # storing off values in hidden fields for further steps
    # there is probably a better way of doing this, I don't have time to figure this out
    $sync.MicrowinIsoDrive.Text = $driveLetter

    $mountedISOPath = (Split-Path -Path $filePath)
     if ($sync.MicrowinScratchDirBox.Text.Trim() -eq "Scratch") {
        $sync.MicrowinScratchDirBox.Text =""
    }

     $UseISOScratchDir = $sync.WPFMicrowinISOScratchDir.IsChecked

    if ($UseISOScratchDir) {
        $sync.MicrowinScratchDirBox.Text=$mountedISOPath
    }

    if( -Not $sync.MicrowinScratchDirBox.Text.EndsWith('\') -And  $sync.MicrowinScratchDirBox.Text.Length -gt 1) {

         $sync.MicrowinScratchDirBox.Text = Join-Path   $sync.MicrowinScratchDirBox.Text.Trim() '\'

    }
    
    # Detect if the folders already exist and remove them
    if (($sync.MicrowinMountDir.Text -ne "") -and (Test-Path -Path $sync.MicrowinMountDir.Text))
    {
        try {
            Write-Host "Deleting temporary files from previous run. Please wait..."
            Remove-Item -Path $sync.MicrowinMountDir.Text -Recurse -Force
            Remove-Item -Path $sync.MicrowinScratchDir.Text -Recurse -Force
        }
        catch {
            Write-Host "Could not delete temporary files. You need to delete those manually."
        }
    }

    Write-Host "Setting up mount dir and scratch dirs"
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $randomNumber = Get-Random -Minimum 1 -Maximum 9999
    $randomMicrowin = "Microwin_${timestamp}_${randomNumber}"
    $randomMicrowinScratch = "MicrowinScratch_${timestamp}_${randomNumber}"
    $sync.BusyText.Text=" - Mounting"
    Write-Host "Mounting Iso. Please wait."  
    if ($sync.MicrowinScratchDirBox.Text -eq "") {
    $mountDir = Join-Path $env:TEMP $randomMicrowin
    $scratchDir = Join-Path $env:TEMP $randomMicrowinScratch
    } else {
        $scratchDir = $sync.MicrowinScratchDirBox.Text+"Scrach"
        $mountDir = $sync.MicrowinScratchDirBox.Text+"micro"
    }

    $sync.MicrowinMountDir.Text = $mountDir
    $sync.MicrowinScratchDir.Text = $scratchDir
    Write-Host "Done setting up mount dir and scratch dirs"
    Write-Host "Scratch dir is $scratchDir"
    Write-Host "Image dir is $mountDir"

    try {
        
        #$data = @($driveLetter, $filePath)
        New-Item -ItemType Directory -Force -Path "$($mountDir)" | Out-Null
        New-Item -ItemType Directory -Force -Path "$($scratchDir)" | Out-Null
        Write-Host "Copying Windows image. This will take awhile, please don't use UI or cancel this step!"
        
        # xcopy we can verify files and also not copy files that already exist, but hard to measure
        # xcopy.exe /E /I /H /R /Y /J $DriveLetter":" $mountDir >$null
        $totalTime = Measure-Command { Copy-Files "$($driveLetter):" $mountDir -Recurse -Force }
        Write-Host "Copy complete! Total Time: $($totalTime.Minutes)m$($totalTime.Seconds)s"

        $wimFile = "$mountDir\sources\install.wim"
        Write-Host "Getting image information $wimFile"

        if ((-not (Test-Path -Path $wimFile -PathType Leaf)) -and (-not (Test-Path -Path $wimFile.Replace(".wim", ".esd").Trim() -PathType Leaf)))
        {
            $msg = "Neither install.wim nor install.esd exist in the image, this could happen if you use unofficial Windows images. Please don't use shady images from the internet, use only official images. Here are instructions how to download ISO images if the Microsoft website is not showing the link to download and ISO. https://www.techrepublic.com/article/how-to-download-a-windows-10-iso-file-without-using-the-media-creation-tool/"
            Write-Host $msg
            [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            throw
        }
        elseif ((-not (Test-Path -Path $wimFile -PathType Leaf)) -and (Test-Path -Path $wimFile.Replace(".wim", ".esd").Trim() -PathType Leaf))
        {
            Write-Host "Install.esd found on the image. It needs to be converted to a WIM file in order to begin processing"
            $wimFile = $wimFile.Replace(".wim", ".esd").Trim()
        }
        $sync.MicrowinWindowsFlavors.Items.Clear()
        Get-WindowsImage -ImagePath $wimFile | ForEach-Object {
            $imageIdx = $_.ImageIndex
            $imageName = $_.ImageName
            $sync.MicrowinWindowsFlavors.Items.Add("$imageIdx : $imageName")
        }
        $sync.MicrowinWindowsFlavors.SelectedIndex = 0
        Write-Host "Finding suitable Pro edition. This can take some time. Do note that this is an automatic process that might not select the edition you want."
        Get-WindowsImage -ImagePath $wimFile | ForEach-Object {
            if ((Get-WindowsImage -ImagePath $wimFile -Index $_.ImageIndex).EditionId -eq "Professional")
            {
                # We have found the Pro edition
                $sync.MicrowinWindowsFlavors.SelectedIndex = $_.ImageIndex - 1
            }
        }
        Get-Volume $driveLetter | Get-DiskImage | Dismount-DiskImage
        Write-Host "Selected value '$($sync.MicrowinWindowsFlavors.SelectedValue)'....."

        $sync.MicrowinOptionsPanel.Visibility = 'Visible'
    } catch {
        Write-Host "Dismounting bad image..."
        Get-Volume $driveLetter | Get-DiskImage | Dismount-DiskImage
        Remove-Item -Recurse -Force "$($scratchDir)"
        Remove-Item -Recurse -Force "$($mountDir)"
    }

    Write-Host "Done reading and unpacking ISO"
    Write-Host ""
    Write-Host "*********************************"
    Write-Host "Check the UI for further steps!!!"

    $sync.BusyMessage.Visibility="Hidden"
    $sync.ProcessRunning = $false
}


function Invoke-WPFImpex {
    <#

    .SYNOPSIS
        Handles importing and exporting of the checkboxes checked for the tweaks section

    .PARAMETER type
        Indicates whether to 'import' or 'export'

    .PARAMETER checkbox
        The checkbox to export to a file or apply the imported file to

    .EXAMPLE
        Invoke-WPFImpex -type "export"

    #>
    param(
        $type,
        $Config = $null
    )

    if ($type -eq "export"){
        $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog
    }
    if ($type -eq "import"){
        $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog
    }

    if (-not $Config){
        $FileBrowser.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        $FileBrowser.Filter = "JSON Files (*.json)|*.json"
        $FileBrowser.ShowDialog() | Out-Null

        if($FileBrowser.FileName -eq ""){
            return
        } 
        else{
            $Config = $FileBrowser.FileName
        }
    }
    
    if ($type -eq "export"){
        $jsonFile = Get-WinUtilCheckBoxes -unCheck $false
        $jsonFile | ConvertTo-Json | Out-File $FileBrowser.FileName -Force
    }
    if ($type -eq "import"){
        $jsonFile = Get-Content $Config | ConvertFrom-Json

        $flattenedJson = @()
        $jsonFile.PSObject.Properties | ForEach-Object {
            $category = $_.Name
            foreach ($checkboxName in $_.Value) {
                if ($category -ne "Install") {
                    $flattenedJson += $checkboxName
                }
            }
        }

        Invoke-WPFPresets -preset $flattenedJson -imported $true
    }
}
function Invoke-WPFInstall {
    <#

    .SYNOPSIS
        Installs the selected programs using winget, if one or more of the selected programs are already installed on the system, winget will try and perform an upgrade if there's a newer version to install.

    #>

    if($sync.ProcessRunning){
        $msg = "[Invoke-WPFInstall] An Install process is currently running."
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $WingetInstall = (Get-WinUtilCheckBoxes)["Install"]

    if ($wingetinstall.Count -eq 0) {
        $WarningMsg = "Please select the program(s) to install or upgrade"
        [System.Windows.MessageBox]::Show($WarningMsg, $AppTitle, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    Invoke-WPFRunspace -ArgumentList $WingetInstall -DebugPreference $DebugPreference -ScriptBlock {
        param($WingetInstall, $DebugPreference)

        try{
            $sync.ProcessRunning = $true

            Install-WinUtilWinget
            Install-WinUtilProgramWinget -ProgramsToInstall $WingetInstall

            Write-Host "==========================================="
            Write-Host "--      Installs have finished          ---"
            Write-Host "==========================================="
        }
        Catch {
            Write-Host "==========================================="
            Write-Host "Error: $_"
            Write-Host "==========================================="
        }
        Start-Sleep -Seconds 5
        $sync.ProcessRunning = $False
    }
}
function Invoke-WPFInstallUpgrade {
    <#

    .SYNOPSIS
        Invokes the function that upgrades all installed programs using winget

    #>
    if((Test-WinUtilPackageManager -winget) -eq "not-installed"){
        return
    }

    if(Get-WinUtilInstallerProcess -Process $global:WinGetInstall){
        $msg = "[Invoke-WPFInstallUpgrade] Install process is currently running. Please check for a powershell window labeled 'Winget Install'"
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    Update-WinUtilProgramWinget

    Write-Host "==========================================="
    Write-Host "--           Updates started            ---"
    Write-Host "-- You can close this window if desired ---"
    Write-Host "==========================================="
}
function Invoke-WPFMicrowin {
    <#
        .DESCRIPTION
        Invoke MicroWin routines...
    #>

	if($sync.ProcessRunning) {
        $msg = "GetIso process is currently running."
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

	# Define the constants for Windows API
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class PowerManagement {
	[DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
	public static extern EXECUTION_STATE SetThreadExecutionState(EXECUTION_STATE esFlags);

	[FlagsAttribute]
	public enum EXECUTION_STATE : uint {
		ES_SYSTEM_REQUIRED = 0x00000001,
		ES_DISPLAY_REQUIRED = 0x00000002,
		ES_CONTINUOUS = 0x80000000,
	}
}
"@

	# Prevent the machine from sleeping
	[PowerManagement]::SetThreadExecutionState([PowerManagement]::EXECUTION_STATE::ES_CONTINUOUS -bor [PowerManagement]::EXECUTION_STATE::ES_SYSTEM_REQUIRED -bor [PowerManagement]::EXECUTION_STATE::ES_DISPLAY_REQUIRED)

    # Ask the user where to save the file
    $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    $SaveDialog.Filter = "ISO images (*.iso)|*.iso"
    $SaveDialog.ShowDialog() | Out-Null

    if ($SaveDialog.FileName -eq "") {
        Write-Host "No file name for the target image was specified"
        return
    }

    Write-Host "Target ISO location: $($SaveDialog.FileName)"

	$index = $sync.MicrowinWindowsFlavors.SelectedValue.Split(":")[0].Trim()
	Write-Host "Index chosen: '$index' from $($sync.MicrowinWindowsFlavors.SelectedValue)"

	$keepPackages = $sync.WPFMicrowinKeepProvisionedPackages.IsChecked
	$keepProvisionedPackages = $sync.WPFMicrowinKeepAppxPackages.IsChecked
	$keepDefender = $sync.WPFMicrowinKeepDefender.IsChecked
	$keepEdge = $sync.WPFMicrowinKeepEdge.IsChecked
	$copyToUSB = $sync.WPFMicrowinCopyToUsb.IsChecked
	$injectDrivers = $sync.MicrowinInjectDrivers.IsChecked

    $mountDir = $sync.MicrowinMountDir.Text
    $scratchDir = $sync.MicrowinScratchDir.Text

	# Detect if the Windows image is an ESD file and convert it to WIM
	if (-not (Test-Path -Path $mountDir\sources\install.wim -PathType Leaf) -and (Test-Path -Path $mountDir\sources\install.esd -PathType Leaf))
	{
		Write-Host "Exporting Windows image to a WIM file, keeping the index we want to work on. This can take several minutes, depending on the performance of your computer..."
		Export-WindowsImage -SourceImagePath $mountDir\sources\install.esd -SourceIndex $index -DestinationImagePath $mountDir\sources\install.wim -CompressionType "Max"
		if ($?)
		{
            Remove-Item -Path $mountDir\sources\install.esd -Force
			# Since we've already exported the image index we wanted, switch to the first one
			$index = 1
		}
		else
		{
            $msg = "The export process has failed and MicroWin processing cannot continue"
            Write-Host "Failed to export the image"
            [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
		}
	}

    $imgVersion = (Get-WindowsImage -ImagePath $mountDir\sources\install.wim -Index $index).Version

    # Detect image version to avoid performing MicroWin processing on Windows 8 and earlier
    if ((Test-CompatibleImage $imgVersion $([System.Version]::new(10,0,10240,0))) -eq $false)
    {
		$msg = "This image is not compatible with MicroWin processing. Make sure it isn't a Windows 8 or earlier image."
        $dlg_msg = $msg + "`n`nIf you want more information, the version of the image selected is $($imgVersion)`n`nIf an image has been incorrectly marked as incompatible, report an issue to the developers."
		Write-Host $msg
		[System.Windows.MessageBox]::Show($dlg_msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Exclamation)
        return
    }

	$mountDirExists = Test-Path $mountDir
    $scratchDirExists = Test-Path $scratchDir
	if (-not $mountDirExists -or -not $scratchDirExists) 
	{
        Write-Error "Required directories '$mountDirExists' '$scratchDirExists' and do not exist."
        return
    }

	try {

		Write-Host "Mounting Windows image. This may take a while."
        Mount-WindowsImage -ImagePath "$mountDir\sources\install.wim" -Index $index -Path "$scratchDir"
        if ($?)
        {
		    Write-Host "Mounting complete! Performing removal of applications..."
        }
        else
        {
            Write-Host "Could not mount image. Exiting..."
            return
        }

		if ($injectDrivers)
		{
			$driverPath = $sync.MicrowinDriverLocation.Text
			if (Test-Path $driverPath)
			{
				Write-Host "Adding Windows Drivers image($scratchDir) drivers($driverPath) "
				Add-WindowsDriver -Path "$scratchDir" -Recurse -Driver "$driverPath"
			}
			else 
			{
				Write-Host "Path to drivers is invalid continuing without driver injection"
			}
		}

		Write-Host "Remove Features from the image"
		Remove-Features -keepDefender:$keepDefender
		Write-Host "Removing features complete!"

		Write-Host "Removing Appx Bloat"
		if (!$keepPackages)
		{
			Remove-Packages
		}
		if (!$keepProvisionedPackages)
		{
			Remove-ProvisionedPackages -keepSecurity:$keepDefender
		}

		# special code, for some reason when you try to delete some inbox apps
		# we have to get and delete log files directory. 
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\System32\LogFiles\WMI\RtBackup" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\System32\WebThreatDefSvc" -Directory

		# Defender is hidden in 2 places we removed a feature above now need to remove it from the disk
		if (!$keepDefender) 
		{
			Write-Host "Removing Defender"
			Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files\Windows Defender" -Directory
			Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files (x86)\Windows Defender"
		}
		if (!$keepEdge)
		{
			Write-Host "Removing Edge"
			Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files (x86)\Microsoft" -mask "*edge*" -Directory
			Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files\Microsoft" -mask "*edge*" -Directory
			Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\SystemApps" -mask "*edge*" -Directory
		}

		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\DiagTrack" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\InboxApps" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\System32\SecurityHealthSystray.exe"
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\System32\LocationNotificationWindows.exe" 
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files (x86)\Windows Photo Viewer" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files\Windows Photo Viewer" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files (x86)\Windows Media Player" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files\Windows Media Player" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files (x86)\Windows Mail" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files\Windows Mail" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files (x86)\Internet Explorer" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Program Files\Internet Explorer" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\GameBarPresenceWriter"
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\System32\OneDriveSetup.exe"
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\System32\OneDrive.ico"
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\SystemApps" -mask "*Windows.Search*" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\SystemApps" -mask "*narratorquickstart*" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\SystemApps" -mask "*Xbox*" -Directory
		Remove-FileOrDirectory -pathToDelete "$($scratchDir)\Windows\SystemApps" -mask "*ParentalControls*" -Directory
		Write-Host "Removal complete!"

		Write-Host "Create unattend.xml"
		New-Unattend
		Write-Host "Done Create unattend.xml"
		Write-Host "Copy unattend.xml file into the ISO"
		New-Item -ItemType Directory -Force -Path "$($scratchDir)\Windows\Panther"
		Copy-Item "$env:temp\unattend.xml" "$($scratchDir)\Windows\Panther\unattend.xml" -force
		New-Item -ItemType Directory -Force -Path "$($scratchDir)\Windows\System32\Sysprep"
		Copy-Item "$env:temp\unattend.xml" "$($scratchDir)\Windows\System32\Sysprep\unattend.xml" -force
		Copy-Item "$env:temp\unattend.xml" "$($scratchDir)\unattend.xml" -force
		Write-Host "Done Copy unattend.xml"

		Write-Host "Create FirstRun"
		New-FirstRun
		Write-Host "Done create FirstRun"
		Write-Host "Copy FirstRun.ps1 into the ISO"
		Copy-Item "$env:temp\FirstStartup.ps1" "$($scratchDir)\Windows\FirstStartup.ps1" -force
		Write-Host "Done copy FirstRun.ps1"

		Write-Host "Copy link to winutil.ps1 into the ISO"
		$desktopDir = "$($scratchDir)\Windows\Users\Default\Desktop"
		New-Item -ItemType Directory -Force -Path "$desktopDir"
	    dism /English /image:$($scratchDir) /set-profilepath:"$($scratchDir)\Windows\Users\Default"
		$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command 'irm https://christitus.com/win | iex'"
		$shortcutPath = "$desktopDir\WinUtil.lnk"
		$shell = New-Object -ComObject WScript.Shell
		$shortcut = $shell.CreateShortcut($shortcutPath)

		if (Test-Path -Path "$env:TEMP\cttlogo.png")
		{
			$pngPath = "$env:TEMP\cttlogo.png"
			$icoPath = "$env:TEMP\cttlogo.ico"
			ConvertTo-Icon -bitmapPath $pngPath -iconPath $icoPath
			Write-Host "ICO file created at: $icoPath"
			Copy-Item "$env:TEMP\cttlogo.png" "$($scratchDir)\Windows\cttlogo.png" -force
			Copy-Item "$env:TEMP\cttlogo.ico" "$($scratchDir)\Windows\cttlogo.ico" -force
			$shortcut.IconLocation = "c:\Windows\cttlogo.ico"
		}

		$shortcut.TargetPath = "powershell.exe"
		$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$command`""
		$shortcut.Save()
		Write-Host "Shortcut to winutil created at: $shortcutPath"
		# *************************** Automation black ***************************

		Write-Host "Copy checkinstall.cmd into the ISO"
		New-CheckInstall
		Copy-Item "$env:temp\checkinstall.cmd" "$($scratchDir)\Windows\checkinstall.cmd" -force
		Write-Host "Done copy checkinstall.cmd"

		Write-Host "Creating a directory that allows to bypass Wifi setup"
		New-Item -ItemType Directory -Force -Path "$($scratchDir)\Windows\System32\OOBE\BYPASSNRO"

		Write-Host "Loading registry"
		reg load HKLM\zCOMPONENTS "$($scratchDir)\Windows\System32\config\COMPONENTS"
		reg load HKLM\zDEFAULT "$($scratchDir)\Windows\System32\config\default"
		reg load HKLM\zNTUSER "$($scratchDir)\Users\Default\ntuser.dat"
		reg load HKLM\zSOFTWARE "$($scratchDir)\Windows\System32\config\SOFTWARE"
		reg load HKLM\zSYSTEM "$($scratchDir)\Windows\System32\config\SYSTEM"

		Write-Host "Disabling Teams"
		reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Communications" /v "ConfigureChatAutoInstall" /t REG_DWORD /d 0 /f   >$null 2>&1
		reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat" /v ChatIcon /t REG_DWORD /d 2 /f                             >$null 2>&1
		reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarMn" /t REG_DWORD /d 0 /f        >$null 2>&1  
		reg query "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Communications" /v "ConfigureChatAutoInstall"                      >$null 2>&1
		# Write-Host Error code $LASTEXITCODE
		Write-Host "Done disabling Teams"

		Write-Host "Bypassing system requirements (system image)"
		reg add "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache" /v "SV1" /t REG_DWORD /d 0 /f
		reg add "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache" /v "SV2" /t REG_DWORD /d 0 /f
		reg add "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache" /v "SV1" /t REG_DWORD /d 0 /f
		reg add "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache" /v "SV2" /t REG_DWORD /d 0 /f
		reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassCPUCheck" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassRAMCheck" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassSecureBootCheck" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassStorageCheck" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassTPMCheck" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSYSTEM\Setup\MoSetup" /v "AllowUpgradesWithUnsupportedTPMOrCPU" /t REG_DWORD /d 1 /f

		if (!$keepEdge)
		{
			Write-Host "Removing Edge icon from taskbar"
			reg delete "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband" /v "Favorites" /f 		  >$null 2>&1
			reg delete "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband" /v "FavoritesChanges" /f   >$null 2>&1
			reg delete "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband" /v "Pinned" /f             >$null 2>&1
			reg delete "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband" /v "LayoutCycle" /f        >$null 2>&1
			Write-Host "Edge icon removed from taskbar"
		}

		reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v "SearchboxTaskbarMode" /t REG_DWORD /d 0 /f
		Write-Host "Setting all services to start manually"
		reg add "HKLM\zSOFTWARE\CurrentControlSet\Services" /v Start /t REG_DWORD /d 3 /f
		# Write-Host $LASTEXITCODE

		Write-Host "Enabling Local Accounts on OOBE"
		reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v "BypassNRO" /t REG_DWORD /d "1" /f

		Write-Host "Disabling Sponsored Apps"
		reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "OemPreInstalledAppsEnabled" /t REG_DWORD /d 0 /f
		reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "PreInstalledAppsEnabled" /t REG_DWORD /d 0 /f
		reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SilentInstalledAppsEnabled" /t REG_DWORD /d 0 /f
		reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsConsumerFeatures" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start" /v "ConfigureStartPins" /t REG_SZ /d '{\"pinnedList\": [{}]}' /f
		Write-Host "Done removing Sponsored Apps"
		
		Write-Host "Disabling Reserved Storage"
		reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" /v "ShippedWithReserves" /t REG_DWORD /d 0 /f

		Write-Host "Changing theme to dark. This only works on Activated Windows"
		reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 0 /f
		reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "SystemUsesLightTheme" /t REG_DWORD /d 0 /f

	} catch {
        Write-Error "An unexpected error occurred: $_"
    } finally {
		Write-Host "Unmounting Registry..."
		reg unload HKLM\zCOMPONENTS
		reg unload HKLM\zDEFAULT
		reg unload HKLM\zNTUSER
		reg unload HKLM\zSOFTWARE
		reg unload HKLM\zSYSTEM

		Write-Host "Cleaning up image..."
		dism /English /image:$scratchDir /Cleanup-Image /StartComponentCleanup /ResetBase
		Write-Host "Cleanup complete."

		Write-Host "Unmounting image..."
        Dismount-WindowsImage -Path $scratchDir -Save
	} 
	
	try {

		Write-Host "Exporting image into $mountDir\sources\install2.wim"
        Export-WindowsImage -SourceImagePath "$mountDir\sources\install.wim" -SourceIndex $index -DestinationImagePath "$mountDir\sources\install2.wim" -CompressionType "Max"
		Write-Host "Remove old '$mountDir\sources\install.wim' and rename $mountDir\sources\install2.wim"
		Remove-Item "$mountDir\sources\install.wim"
		Rename-Item "$mountDir\sources\install2.wim" "$mountDir\sources\install.wim"

		if (-not (Test-Path -Path "$mountDir\sources\install.wim"))
		{
			Write-Error "Something went wrong and '$mountDir\sources\install.wim' doesn't exist. Please report this bug to the devs"
			return
		}
		Write-Host "Windows image completed. Continuing with boot.wim."

		# Next step boot image		
		Write-Host "Mounting boot image $mountDir\sources\boot.wim into $scratchDir"
        Mount-WindowsImage -ImagePath "$mountDir\sources\boot.wim" -Index 2 -Path "$scratchDir"

		if ($injectDrivers)
		{
			$driverPath = $sync.MicrowinDriverLocation.Text
			if (Test-Path $driverPath)
			{
				Write-Host "Adding Windows Drivers image($scratchDir) drivers($driverPath) "
				Add-WindowsDriver -Path "$scratchDir" -Driver "$driverPath" -Recurse
			}
			else 
			{
				Write-Host "Path to drivers is invalid continuing without driver injection"
			}
		}
	
		Write-Host "Loading registry..."
		reg load HKLM\zCOMPONENTS "$($scratchDir)\Windows\System32\config\COMPONENTS" >$null
		reg load HKLM\zDEFAULT "$($scratchDir)\Windows\System32\config\default" >$null
		reg load HKLM\zNTUSER "$($scratchDir)\Users\Default\ntuser.dat" >$null
		reg load HKLM\zSOFTWARE "$($scratchDir)\Windows\System32\config\SOFTWARE" >$null
		reg load HKLM\zSYSTEM "$($scratchDir)\Windows\System32\config\SYSTEM" >$null
		Write-Host "Bypassing system requirements on the setup image"
		reg add "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache" /v "SV1" /t REG_DWORD /d 0 /f
		reg add "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache" /v "SV2" /t REG_DWORD /d 0 /f
		reg add "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache" /v "SV1" /t REG_DWORD /d 0 /f
		reg add "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache" /v "SV2" /t REG_DWORD /d 0 /f
		reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassCPUCheck" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassRAMCheck" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassSecureBootCheck" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassStorageCheck" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassTPMCheck" /t REG_DWORD /d 1 /f
		reg add "HKLM\zSYSTEM\Setup\MoSetup" /v "AllowUpgradesWithUnsupportedTPMOrCPU" /t REG_DWORD /d 1 /f
		# Fix Computer Restarted Unexpectedly Error on New Bare Metal Install
		reg add "HKLM\zSYSTEM\Setup\Status\ChildCompletion" /v "setup.exe" /t REG_DWORD /d 3 /f
	} catch {
        Write-Error "An unexpected error occurred: $_"
    } finally {
		Write-Host "Unmounting Registry..."
		reg unload HKLM\zCOMPONENTS
		reg unload HKLM\zDEFAULT
		reg unload HKLM\zNTUSER
		reg unload HKLM\zSOFTWARE
		reg unload HKLM\zSYSTEM

		Write-Host "Unmounting image..."
        Dismount-WindowsImage -Path $scratchDir -Save

		Write-Host "Creating ISO image"

		# if we downloaded oscdimg from github it will be in the temp directory so use it
		# if it is not in temp it is part of ADK and is in global PATH so just set it to oscdimg.exe
		$oscdimgPath = Join-Path $env:TEMP 'oscdimg.exe'
		$oscdImgFound = Test-Path $oscdimgPath -PathType Leaf
		if (!$oscdImgFound)
		{
			$oscdimgPath = "oscdimg.exe"
		}

		Write-Host "[INFO] Using oscdimg.exe from: $oscdimgPath"
		#& oscdimg.exe -m -o -u2 -udfver102 -bootdata:2#p0,e,b$mountDir\boot\etfsboot.com#pEF,e,b$mountDir\efi\microsoft\boot\efisys.bin $mountDir $env:temp\microwin.iso
		#Start-Process -FilePath $oscdimgPath -ArgumentList "-m -o -u2 -udfver102 -bootdata:2#p0,e,b$mountDir\boot\etfsboot.com#pEF,e,b$mountDir\efi\microsoft\boot\efisys.bin $mountDir $env:temp\microwin.iso" -NoNewWindow -Wait
		#Start-Process -FilePath $oscdimgPath -ArgumentList '-m -o -u2 -udfver102 -bootdata:2#p0,e,b$mountDir\boot\etfsboot.com#pEF,e,b$mountDir\efi\microsoft\boot\efisys.bin $mountDir `"$($SaveDialog.FileName)`"' -NoNewWindow -Wait
        $oscdimgProc = New-Object System.Diagnostics.Process
        $oscdimgProc.StartInfo.FileName = $oscdimgPath
        $oscdimgProc.StartInfo.Arguments = "-m -o -u2 -udfver102 -bootdata:2#p0,e,b$mountDir\boot\etfsboot.com#pEF,e,b$mountDir\efi\microsoft\boot\efisys.bin $mountDir `"$($SaveDialog.FileName)`""
        $oscdimgProc.StartInfo.CreateNoWindow = $True
        $oscdimgProc.StartInfo.WindowStyle = "Hidden"
        $oscdimgProc.StartInfo.UseShellExecute = $False
        $oscdimgProc.Start()
        $oscdimgProc.WaitForExit()

		if ($copyToUSB)
		{
			Write-Host "Copying target ISO to the USB drive"
			#Copy-ToUSB("$env:temp\microwin.iso")
			Copy-ToUSB("$($SaveDialog.FileName)")
			if ($?) { Write-Host "Done Copying target ISO to USB drive!" } else { Write-Host "ISO copy failed." }
		}
		
		Write-Host " _____                       "
		Write-Host "(____ \                      "
		Write-Host " _   \ \ ___  ____   ____    "
		Write-Host "| |   | / _ \|  _ \ / _  )   "
		Write-Host "| |__/ / |_| | | | ( (/ /    "
		Write-Host "|_____/ \___/|_| |_|\____)   "

		# Check if the ISO was successfully created - CTT edit
		if ($LASTEXITCODE -eq 0) {
			Write-Host "`n`nPerforming Cleanup..."
				Remove-Item -Recurse -Force "$($scratchDir)"
				Remove-Item -Recurse -Force "$($mountDir)"
			#$msg = "Done. ISO image is located here: $env:temp\microwin.iso"
			$msg = "Done. ISO image is located here: $($SaveDialog.FileName)"
			Write-Host $msg
			[System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
		} else {
			Write-Host "ISO creation failed. The "$($mountDir)" directory has not been removed."
		}
		
		$sync.MicrowinOptionsPanel.Visibility = 'Collapsed'
		
		#$sync.MicrowinFinalIsoLocation.Text = "$env:temp\microwin.iso"
        $sync.MicrowinFinalIsoLocation.Text = "$($SaveDialog.FileName)"
		# Allow the machine to sleep again (optional)
		[PowerManagement]::SetThreadExecutionState(0)
		$sync.ProcessRunning = $false
	}
}
function Invoke-WPFOOSU {
    <#
    .SYNOPSIS
        Downloads and runs OO Shutup 10 with or without config files
    .PARAMETER action
        Specifies how OOSU should be started
        customize:      Opens the OOSU GUI
        recommended:    Loads and applies the recommended OOSU policies silently
        undo:           Resets all policies to factory silently
    #>

    param (
        [ValidateSet("customize", "recommended", "undo")]
        [string]$action
    )

    $OOSU_filepath = "$ENV:temp\OOSU10.exe"

    $Initial_ProgressPreference = $ProgressPreference
    $ProgressPreference = "SilentlyContinue" # Disables the Progress Bar to drasticly speed up Invoke-WebRequest
    Invoke-WebRequest -Uri "https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe" -OutFile $OOSU_filepath

    switch ($action) 
    {
        "customize"{
            Write-Host "Starting OO Shutup 10 ..."
            Start-Process $OOSU_filepath
        }
        "recommended"{
            $oosu_config = "$ENV:temp\ooshutup10_recommended.cfg"
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/config/ooshutup10_recommended.cfg" -OutFile $oosu_config
            Write-Host "Applying recommended OO Shutup 10 Policies"
            Start-Process $OOSU_filepath -ArgumentList "$oosu_config /quiet" -Wait
        }
        "undo"{
            $oosu_config = "$ENV:temp\ooshutup10_factory.cfg"
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/config/ooshutup10_factory.cfg" -OutFile $oosu_config
            Write-Host "Resetting all OO Shutup 10 Policies"
            Start-Process $OOSU_filepath -ArgumentList "$oosu_config /quiet" -Wait
        }
    }
    $ProgressPreference = $Initial_ProgressPreference
}
function Invoke-WPFPanelAutologin {
    <#

    .SYNOPSIS
        Enables autologin using Sysinternals Autologon.exe

    #>
    curl.exe -ss "https://live.sysinternals.com/Autologon.exe" -o $env:temp\autologin.exe # Official Microsoft recommendation https://learn.microsoft.com/en-us/sysinternals/downloads/autologon
    cmd /c $env:temp\autologin.exe /accepteula
}
function Invoke-WPFPanelDISM {
    <#

    .SYNOPSIS
        Checks for system corruption using Chkdsk, SFC, and DISM

    .DESCRIPTION
        1. Chkdsk    - Fixes disk and filesystem corruption
        2. SFC Run 1 - Fixes system file corruption, and fixes DISM if it was corrupted
        3. DISM      - Fixes system image corruption, and fixes SFC's system image if it was corrupted
        4. SFC Run 2 - Fixes system file corruption, this time with an almost guaranteed uncorrupted system image

    .NOTES
        Command Arguments:
            1. Chkdsk
                /Scan - Runs an online scan on the system drive, attempts to fix any corruption, and queues other corruption for fixing on reboot
            2. SFC
                /ScanNow - Performs a scan of the system files and fixes any corruption
            3. DISM      - Fixes system image corruption, and fixes SFC's system image if it was corrupted
                /Online - Fixes the currently running system image
                /Cleanup-Image - Performs cleanup operations on the image, could remove some unneeded temporary files
                /Restorehealth - Performs a scan of the image and fixes any corruption

    #>
    Start-Process PowerShell -ArgumentList "Write-Host '(1/4) Chkdsk' -ForegroundColor Green; Chkdsk /scan;
    Write-Host '`n(2/4) SFC - 1st scan' -ForegroundColor Green; sfc /scannow;
    Write-Host '`n(3/4) DISM' -ForegroundColor Green; DISM /Online /Cleanup-Image /Restorehealth;
    Write-Host '`n(4/4) SFC - 2nd scan' -ForegroundColor Green; sfc /scannow;
    Read-Host '`nPress Enter to Continue'" -verb runas
}
function Invoke-WPFPresets {
    <#

    .SYNOPSIS
        Sets the options in the tweaks panel to the given preset

    .PARAMETER preset
        The preset to set the options to

    .PARAMETER imported
        If the preset is imported from a file, defaults to false

    .PARAMETER checkbox
        The checkbox to set the options to, defaults to 'WPFTweaks'

    #>

    param(
        $preset,
        [bool]$imported = $false
    )

    if($imported -eq $true){
        $CheckBoxesToCheck = $preset
    }
    Else{
        $CheckBoxesToCheck = $sync.configs.preset.$preset
    }

    $CheckBoxes = $sync.GetEnumerator() | Where-Object { $_.Value -is [System.Windows.Controls.CheckBox] -and $_.Name -notlike "WPFToggle*" }
    Write-Debug "Getting checkboxes to set $($CheckBoxes.Count)"

    $CheckBoxesToCheck | ForEach-Object {
        if ($_ -ne $null) {
            Write-Debug $_
        }
    }
    
    foreach ($CheckBox in $CheckBoxes) {
        $checkboxName = $CheckBox.Key

        if (-not $CheckBoxesToCheck)
        {
            $sync.$checkboxName.IsChecked = $false
            continue
        }

        # Check if the checkbox name exists in the flattened JSON hashtable
        if ($CheckBoxesToCheck.Contains($checkboxName)) {
            # If it exists, set IsChecked to true
            $sync.$checkboxName.IsChecked = $true
            Write-Debug "$checkboxName is checked"
        } else {
            # If it doesn't exist, set IsChecked to false
            $sync.$checkboxName.IsChecked = $false
            Write-Debug "$checkboxName is not checked"
        }
    }
}
function Invoke-WPFRunAdobeCCCleanerTool {
    <#
    .SYNOPSIS
        It removes or fixes problem files and resolves permission issues in registry keys.
    .DESCRIPTION
        The Creative Cloud Cleaner tool is a utility for experienced users to clean up corrupted installations.
    #>

    [string]$url="https://swupmf.adobe.com/webfeed/CleanerTool/win/AdobeCreativeCloudCleanerTool.exe"

    Write-Host "The Adobe Creative Cloud Cleaner tool is hosted at"
    Write-Host "$url"

    try {
        # Don't show the progress because it will slow down the download speed
        $ProgressPreference='SilentlyContinue'

        Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\AdobeCreativeCloudCleanerTool.exe" -UseBasicParsing -ErrorAction SilentlyContinue -Verbose

        # Revert back the ProgressPreference variable to the default value since we got the file desired
        $ProgressPreference='Continue'

        Start-Process -FilePath "$env:TEMP\AdobeCreativeCloudCleanerTool.exe" -Wait -ErrorAction SilentlyContinue -Verbose
    } catch {
        Write-Error $_.Exception.Message
    } finally {
        if (Test-Path -Path "$env:TEMP\AdobeCreativeCloudCleanerTool.exe") {
            Write-Host "Cleaning up..."
            Remove-Item -Path "$env:TEMP\AdobeCreativeCloudCleanerTool.exe" -Verbose
        }
    }
}
function Invoke-WPFRunspace {

    <#

    .SYNOPSIS
        Creates and invokes a runspace using the given scriptblock and argumentlist

    .PARAMETER ScriptBlock
        The scriptblock to invoke in the runspace

    .PARAMETER ArgumentList
        A list of arguments to pass to the runspace

    .EXAMPLE
        Invoke-WPFRunspace `
            -ScriptBlock $sync.ScriptsInstallPrograms `
            -ArgumentList "Installadvancedip,Installbitwarden" `

    #>

    [CmdletBinding()]
    Param (
        $ScriptBlock,
        $ArgumentList,
        $DebugPreference
    )

    # Create a PowerShell instance
    $script:powershell = [powershell]::Create()

    # Add Scriptblock and Arguments to runspace
    $script:powershell.AddScript($ScriptBlock)
    $script:powershell.AddArgument($ArgumentList)
    $script:powershell.AddArgument($DebugPreference)  # Pass DebugPreference to the script block
    $script:powershell.RunspacePool = $sync.runspace

    # Execute the RunspacePool
    $script:handle = $script:powershell.BeginInvoke()

    # Clean up the RunspacePool threads when they are complete, and invoke the garbage collector to clean up the memory
    if ($script:handle.IsCompleted)
    {
        $script:powershell.EndInvoke($script:handle)
        $script:powershell.Dispose()
        $sync.runspace.Dispose()
        $sync.runspace.Close()
        [System.GC]::Collect()
    }
}

function Invoke-WPFShortcut {
    <#

    .SYNOPSIS
        Creates a shortcut and prompts for a save location

    .PARAMETER ShortcutToAdd
        The name of the shortcut to add

    .PARAMETER RunAsAdmin
        A boolean value to make 'Run as administrator' property on (true) or off (false), defaults to off

    #>
    param(
        $ShortcutToAdd,
        [bool]$RunAsAdmin = $false
    )

        $iconPath = $null
        Switch ($ShortcutToAdd) {
            "WinUtil" {
                $SourceExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
                $IRM = 'irm https://christitus.com/win | iex'
                $Powershell = '-ExecutionPolicy Bypass -Command "Start-Process powershell.exe -verb runas -ArgumentList'
                $ArgumentsToSourceExe = "$powershell '$IRM'"
                $DestinationName = "WinUtil.lnk"

                if (Test-Path -Path "$env:TEMP\cttlogo.png") {
                    $iconPath = "$env:SystempRoot\cttlogo.ico"
                    ConvertTo-Icon -bitmapPath "$env:TEMP\cttlogo.png" -iconPath $iconPath
                }
            }
        }

    $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog
    $FileBrowser.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    $FileBrowser.Filter = "Shortcut Files (*.lnk)|*.lnk"
    $FileBrowser.FileName = $DestinationName
    $FileBrowser.ShowDialog() | Out-Null

    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($FileBrowser.FileName)
    $Shortcut.TargetPath = $SourceExe
    $Shortcut.Arguments = $ArgumentsToSourceExe
    if ($null -ne $iconPath) {
        $shortcut.IconLocation = $iconPath
    }
    $Shortcut.Save()

    if ($RunAsAdmin -eq $true) {
        $bytes = [System.IO.File]::ReadAllBytes($FileBrowser.FileName)
        # Set byte value at position 0x15 in hex, or 21 in decimal, from the value 0x00 to 0x20 in hex
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($FileBrowser.FileName, $bytes)
    }

    Write-Host "Shortcut for $ShortcutToAdd has been saved to $($FileBrowser.FileName) with 'Run as administrator' set to $RunAsAdmin"
}
function Invoke-WPFTab {

    <#

    .SYNOPSIS
        Sets the selected tab to the tab that was clicked

    .PARAMETER ClickedTab
        The name of the tab that was clicked

    #>

    Param ($ClickedTab)

    $tabNav = Get-WinUtilVariables | Where-Object {$psitem -like "WPFTabNav"}
    $tabNumber = [int]($ClickedTab -replace "WPFTab","" -replace "BT","") - 1

    $filter = Get-WinUtilVariables -Type ToggleButton | Where-Object {$psitem -like "WPFTab?BT"}
    $sync.GetEnumerator() | Where-Object {$psitem.Key -in $filter} | ForEach-Object {
        if ($ClickedTab -ne $PSItem.name) {
            $sync[$PSItem.Name].IsChecked = $false
            # $tabNumber = [int]($PSItem.Name -replace "WPFTab","" -replace "BT","") - 1
            # $sync.$tabNav.Items[$tabNumber].IsSelected = $false
        }
        else {
            $sync["$ClickedTab"].IsChecked = $true
            $tabNumber = [int]($ClickedTab-replace "WPFTab","" -replace "BT","") - 1
            $sync.$tabNav.Items[$tabNumber].IsSelected = $true
        }
    }
}
function Invoke-WPFToggle {

    <#

    .SYNOPSIS
        Invokes the scriptblock for the given toggle

    .PARAMETER Button
        The name of the toggle to invoke

    #>

    Param ([string]$Button)

    # Use this to get the name of the button
    #[System.Windows.MessageBox]::Show("$Button","Chris Titus Tech's Windows Utility","OK","Info")

    Switch -Wildcard ($Button){

        "WPFToggleDarkMode" {Invoke-WinUtilDarkMode -DarkMoveEnabled $(Get-WinUtilToggleStatus WPFToggleDarkMode)}
        "WPFToggleBingSearch" {Invoke-WinUtilBingSearch $(Get-WinUtilToggleStatus WPFToggleBingSearch)}
        "WPFToggleNumLock" {Invoke-WinUtilNumLock $(Get-WinUtilToggleStatus WPFToggleNumLock)}
        "WPFToggleVerboseLogon" {Invoke-WinUtilVerboseLogon $(Get-WinUtilToggleStatus WPFToggleVerboseLogon)}
        "WPFToggleShowExt" {Invoke-WinUtilShowExt $(Get-WinUtilToggleStatus WPFToggleShowExt)}
        "WPFToggleSnapFlyout" {Invoke-WinUtilSnapFlyout $(Get-WinUtilToggleStatus WPFToggleSnapFlyout)}
        "WPFToggleMouseAcceleration" {Invoke-WinUtilMouseAcceleration $(Get-WinUtilToggleStatus WPFToggleMouseAcceleration)}
        "WPFToggleStickyKeys" {Invoke-WinUtilStickyKeys $(Get-WinUtilToggleStatus WPFToggleStickyKeys)}
        "WPFToggleTaskbarWidgets" {Invoke-WinUtilTaskbarWidgets $(Get-WinUtilToggleStatus WPFToggleTaskbarWidgets)}
    }
}
function Invoke-WPFtweaksbutton {
  <#

    .SYNOPSIS
        Invokes the functions associated with each group of checkboxes

  #>

  if($sync.ProcessRunning){
    $msg = "[Invoke-WPFtweaksbutton] Install process is currently running."
    [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    return
  }

  $Tweaks = (Get-WinUtilCheckBoxes)["WPFTweaks"]
  
  Set-WinUtilDNS -DNSProvider $sync["WPFchangedns"].text

  if ($tweaks.count -eq 0 -and  $sync["WPFchangedns"].text -eq "Default"){
    $msg = "Please check the tweaks you wish to perform."
    [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    return
  }

  Write-Debug "Number of tweaks to process: $($Tweaks.Count)"

  Invoke-WPFRunspace -ArgumentList $Tweaks -DebugPreference $DebugPreference -ScriptBlock {
    param($Tweaks, $DebugPreference)
    Write-Debug "Inside Number of tweaks to process: $($Tweaks.Count)"

    $sync.ProcessRunning = $true

    $cnt = 0
    # Execute other selected tweaks
    foreach ($tweak in $Tweaks) {
      Write-Debug "This is a tweak to run $tweak count: $cnt"
      Invoke-WinUtilTweaks $tweak
      $cnt += 1
    }

    $sync.ProcessRunning = $false
    Write-Host "================================="
    Write-Host "--     Tweaks are Finished    ---"
    Write-Host "================================="

    # $ButtonType = [System.Windows.MessageBoxButton]::OK
    # $MessageboxTitle = "Tweaks are Finished "
    # $Messageboxbody = ("Done")
    # $MessageIcon = [System.Windows.MessageBoxImage]::Information
    # [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
  }
}
Function Invoke-WPFUltimatePerformance {
    <#

    .SYNOPSIS
        Creates or removes the Ultimate Performance power scheme

    .PARAMETER State
        Indicates whether to enable or disable the Ultimate Performance power scheme

    #>
    param($State)
    Try{

        if($state -eq "Enabled"){
            # Define the name and GUID of the power scheme
            $powerSchemeName = "Ultimate Performance"
            $powerSchemeGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"

            # Get all power schemes
            $schemes = powercfg /list | Out-String -Stream

            # Check if the power scheme already exists
            $ultimateScheme = $schemes | Where-Object { $_ -match $powerSchemeName }

            if ($null -eq $ultimateScheme) {
                Write-Host "Power scheme '$powerSchemeName' not found. Adding..."

                # Add the power scheme
                powercfg /duplicatescheme $powerSchemeGuid
                powercfg -attributes SUB_SLEEP 7bc4a2f9-d8fc-4469-b07b-33eb785aaca0 -ATTRIB_HIDE
                powercfg -setactive $powerSchemeGuid
                powercfg -change -monitor-timeout-ac 0


                Write-Host "Power scheme added successfully."
            }
            else {
                Write-Host "Power scheme '$powerSchemeName' already exists."
            }
        }
        elseif($state -eq "Disabled"){
                # Define the name of the power scheme
                $powerSchemeName = "Ultimate Performance"

                # Get all power schemes
                $schemes = powercfg /list | Out-String -Stream

                # Find the scheme to be removed
                $ultimateScheme = $schemes | Where-Object { $_ -match $powerSchemeName }

                # If the scheme exists, remove it
                if ($null -ne $ultimateScheme) {
                    # Extract the GUID of the power scheme
                    $guid = ($ultimateScheme -split '\s+')[3]

                    if($null -ne $guid){
                        Write-Host "Found power scheme '$powerSchemeName' with GUID $guid. Removing..."

                        # Remove the power scheme
                        powercfg /delete $guid

                        Write-Host "Power scheme removed successfully."
                    }
                    else {
                        Write-Host "Could not find GUID for power scheme '$powerSchemeName'."
                    }
                }
                else {
                    Write-Host "Power scheme '$powerSchemeName' not found."
                }

            }

    }
    Catch{
        Write-Warning $psitem.Exception.Message
    }
}
function Invoke-WPFundoall {
    <#

    .SYNOPSIS
        Undoes every selected tweak

    #>

    if($sync.ProcessRunning){
        $msg = "[Invoke-WPFundoall] Install process is currently running."
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $Tweaks = (Get-WinUtilCheckBoxes)["WPFTweaks"]

    if ($tweaks.count -eq 0){
        $msg = "Please check the tweaks you wish to undo."
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    Invoke-WPFRunspace -ArgumentList $Tweaks -DebugPreference $DebugPreference -ScriptBlock {
        param($Tweaks, $DebugPreference)

        $sync.ProcessRunning = $true

        Foreach ($tweak in $tweaks){
            Invoke-WinUtilTweaks $tweak -undo $true
        }

        $sync.ProcessRunning = $false
        Write-Host "=================================="
        Write-Host "---  Undo Tweaks are Finished  ---"
        Write-Host "=================================="

        $ButtonType = [System.Windows.MessageBoxButton]::OK
        $MessageboxTitle = "Tweaks are Finished "
        $Messageboxbody = ("Done")
        $MessageIcon = [System.Windows.MessageBoxImage]::Information

        [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
    }

<#

    Write-Host "Creating Restore Point in case something bad happens"
    Enable-ComputerRestore -Drive "$env:SystemDrive"
    Checkpoint-Computer -Description "RestorePoint1" -RestorePointType "MODIFY_SETTINGS"

    Write-Host "Enabling Telemetry..."
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 1
    Write-Host "Enabling Wi-Fi Sense"
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting" -Name "Value" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots" -Name "Value" -Type DWord -Value 1
    Write-Host "Enabling Application suggestions..."
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "ContentDeliveryAllowed" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "OemPreInstalledAppsEnabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEnabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEverEnabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338388Enabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353698Enabled" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Type DWord -Value 1
    If (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent") {
        Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Type DWord -Value 0
    Write-Host "Enabling Activity History..."
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities" -Type DWord -Value 1
    Write-Host "Enable Location Tracking..."
    If (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location") {
        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Type String -Value "Allow"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "SensorPermissionState" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -Type DWord -Value 1
    Write-Host "Enabling automatic Maps updates..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\Maps" -Name "AutoUpdateEnabled" -Type DWord -Value 1
    Write-Host "Enabling Feedback..."
    If (Test-Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules") {
        Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Type DWord -Value 0
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Type DWord -Value 0
    Write-Host "Enabling Tailored Experiences..."
    If (Test-Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent") {
        Remove-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableTailoredExperiencesWithDiagnosticData" -Type DWord -Value 0
    Write-Host "Disabling Advertising ID..."
    If (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo") {
        Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Type DWord -Value 0
    Write-Host "Allow Error reporting..."
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Type DWord -Value 0
    Write-Host "Allowing Diagnostics Tracking Service..."
    Stop-Service "DiagTrack" -WarningAction SilentlyContinue
    Set-Service "DiagTrack" -StartupType Manual
    Write-Host "Allowing WAP Push Service..."
    Stop-Service "dmwappushservice" -WarningAction SilentlyContinue
    Set-Service "dmwappushservice" -StartupType Manual
    Write-Host "Allowing Home Groups services..."
    Stop-Service "HomeGroupListener" -WarningAction SilentlyContinue
    Set-Service "HomeGroupListener" -StartupType Manual
    Stop-Service "HomeGroupProvider" -WarningAction SilentlyContinue
    Set-Service "HomeGroupProvider" -StartupType Manual
    Write-Host "Enabling Storage Sense..."
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" | Out-Null
    Write-Host "Allowing Superfetch service..."
    Stop-Service "SysMain" -WarningAction SilentlyContinue
    Set-Service "SysMain" -StartupType Manual
    Write-Host "Setting BIOS time to Local Time instead of UTC..."
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" -Name "RealTimeIsUniversal" -Type DWord -Value 0
    Write-Host "Enabling Hibernation..."
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Session Manager\Power" -Name "HibernteEnabled" -Type Dword -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name "ShowHibernateOption" -Type Dword -Value 1
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -ErrorAction SilentlyContinue

    Write-Host "Hiding file operations details..."
    If (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager") {
        Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Recurse -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name "EnthusiastMode" -Type DWord -Value 0
    Write-Host "Showing Task View button..."
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Type DWord -Value 1

    Write-Host "Changing default Explorer view to Quick Access..."
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Type DWord -Value 0

    Write-Host "Unrestricting AutoLogger directory"
    $autoLoggerDir = "$env:PROGRAMDATA\Microsoft\Diagnosis\ETLLogs\AutoLogger"
    icacls $autoLoggerDir /grant:r SYSTEM:`(OI`)`(CI`)F | Out-Null

    Write-Host "Enabling and starting Diagnostics Tracking Service"
    Set-Service "DiagTrack" -StartupType Automatic
    Start-Service "DiagTrack"

    Write-Host "Hiding known file extensions"
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Type DWord -Value 1

    Write-Host "Reset Local Group Policies to Stock Defaults"
    # cmd /c secedit /configure /cfg %windir%\inf\defltbase.inf /db defltbase.sdb /verbose
    cmd /c RD /S /Q "%WinDir%\System32\GroupPolicyUsers"
    cmd /c RD /S /Q "%WinDir%\System32\GroupPolicy"
    cmd /c gpupdate /force
    # Considered using Invoke-GPUpdate but requires module most people won't have installed

    Write-Host "Adjusting visual effects for appearance..."
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Type String -Value 1
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Type String -Value 400
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Type Binary -Value ([byte[]](158, 30, 7, 128, 18, 0, 0, 0))
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Type String -Value 1
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "KeyboardDelay" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewAlphaSelect" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ListviewShadow" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Type DWord -Value 3
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Type DWord -Value 1
    Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout" -ErrorAction SilentlyContinue
    Write-Host "Restoring Clipboard History..."
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Clipboard" -Name "EnableClipboardHistory" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "AllowClipboardHistory" -ErrorAction SilentlyContinue
    Write-Host "Enabling Notifications and Action Center"
    Remove-Item -Path HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer -Force
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled"
    Write-Host "Restoring Default Right Click Menu Layout"
    Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Confirm:$false -Force

    Write-Host "Reset News and Interests"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Type DWord -Value 1
    # Remove "News and Interest" from taskbar
    Set-ItemProperty -Path  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Type DWord -Value 0
    Write-Host "Done - Reverted to Stock Settings"

    Write-Host "Essential Undo Completed"

    $ButtonType = [System.Windows.MessageBoxButton]::OK
    $MessageboxTitle = "Undo All"
    $Messageboxbody = ("Done")
    $MessageIcon = [System.Windows.MessageBoxImage]::Information

    [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)

    Write-Host "================================="
    Write-Host "---   Undo All is Finished    ---"
    Write-Host "================================="
    #>
}
function Invoke-WPFUnInstall {
    <#

    .SYNOPSIS
        Uninstalls the selected programs

    #>

    if($sync.ProcessRunning){
        $msg = "[Invoke-WPFUnInstall] Install process is currently running"
        [System.Windows.MessageBox]::Show($msg, "Winutil", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $WingetInstall = (Get-WinUtilCheckBoxes)["Install"]

    if ($wingetinstall.Count -eq 0) {
        $WarningMsg = "Please select the program(s) to install"
        [System.Windows.MessageBox]::Show($WarningMsg, $AppTitle, [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $ButtonType = [System.Windows.MessageBoxButton]::YesNo
    $MessageboxTitle = "Are you sure?"
    $Messageboxbody = ("This will uninstall the following applications: `n $WingetInstall")
    $MessageIcon = [System.Windows.MessageBoxImage]::Information

    $confirm = [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)

    if($confirm -eq "No"){return}

    Invoke-WPFRunspace -ArgumentList $WingetInstall -DebugPreference $DebugPreference -ScriptBlock {
        param($WingetInstall, $DebugPreference)

        try{
            $sync.ProcessRunning = $true

            # Install all selected programs in new window
            Install-WinUtilProgramWinget -ProgramsToInstall $WingetInstall -Manage "Uninstalling"

            $ButtonType = [System.Windows.MessageBoxButton]::OK
            $MessageboxTitle = "Uninstalls are Finished "
            $Messageboxbody = ("Done")
            $MessageIcon = [System.Windows.MessageBoxImage]::Information

            [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)

            Write-Host "==========================================="
            Write-Host "--       Uninstalls have finished       ---"
            Write-Host "==========================================="
        }
        Catch {
            Write-Host "==========================================="
            Write-Host "--       Winget failed to install       ---"
            Write-Host "==========================================="
        }
        $sync.ProcessRunning = $False
    }
}
function Invoke-WPFUpdatesdefault {
    <#

    .SYNOPSIS
        Resets Windows Update settings to default

    #>
    If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Type DWord -Value 0
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Type DWord -Value 3
    If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config")) {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 1

    $services = @(
        "BITS"
        "wuauserv"
    )

    foreach ($service in $services) {
        # -ErrorAction SilentlyContinue is so it doesn't write an error to stdout if a service doesn't exist

        Write-Host "Setting $service StartupType to Automatic"
        Get-Service -Name $service -ErrorAction SilentlyContinue | Set-Service -StartupType Automatic
    }
    Write-Host "Enabling driver offering through Windows Update..."
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
    Write-Host "Enabling Windows Update automatic restart..."
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -ErrorAction SilentlyContinue
    Write-Host "Enabled driver offering through Windows Update"
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "BranchReadinessLevel" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferFeatureUpdatesPeriodInDays" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferQualityUpdatesPeriodInDays" -ErrorAction SilentlyContinue
    Write-Host "==================================================="
    Write-Host "---  Windows Update Settings Reset to Default   ---"
    Write-Host "==================================================="
}
function Invoke-WPFUpdatesdisable {
    <#

    .SYNOPSIS
        Disables Windows Update

    .NOTES
        Disabling Windows Update is not recommended. This is only for advanced users who know what they are doing.

    #>
    If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Type DWord -Value 1
    If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config")) {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 0

    $services = @(
        "BITS"
        "wuauserv"
    )

    foreach ($service in $services) {
        # -ErrorAction SilentlyContinue is so it doesn't write an error to stdout if a service doesn't exist

        Write-Host "Setting $service StartupType to Disabled"
        Get-Service -Name $service -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled
    }
    Write-Host "================================="
    Write-Host "---   Updates ARE DISABLED    ---"
    Write-Host "================================="
}
function Invoke-WPFUpdatessecurity {
    <#

    .SYNOPSIS
        Sets Windows Update to recommended settings

    .DESCRIPTION
        1. Disables driver offering through Windows Update
        2. Disables Windows Update automatic restart
        3. Sets Windows Update to Semi-Annual Channel (Targeted)
        4. Defers feature updates for 365 days
        5. Defers quality updates for 4 days

    #>
    Write-Host "Disabling driver offering through Windows Update..."
        If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -Type DWord -Value 1
        If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -Type DWord -Value 1
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -Type DWord -Value 1
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -Type DWord -Value 0
        If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -Type DWord -Value 1
        Write-Host "Disabling Windows Update automatic restart..."
        If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")) {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -Type DWord -Value 1
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -Type DWord -Value 0
        Write-Host "Disabled driver offering through Windows Update"
        If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings")) {
            New-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Force | Out-Null
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "BranchReadinessLevel" -Type DWord -Value 20
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferFeatureUpdatesPeriodInDays" -Type DWord -Value 365
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" -Name "DeferQualityUpdatesPeriodInDays" -Type DWord -Value 4

        $ButtonType = [System.Windows.MessageBoxButton]::OK
        $MessageboxTitle = "Set Security Updates"
        $Messageboxbody = ("Recommended Update settings loaded")
        $MessageIcon = [System.Windows.MessageBoxImage]::Information

        [System.Windows.MessageBox]::Show($Messageboxbody, $MessageboxTitle, $ButtonType, $MessageIcon)
        Write-Host "================================="
        Write-Host "-- Updates Set to Recommended ---"
        Write-Host "================================="
}
$sync.configs.applications = '{
  "WPFInstall1password": {
    "category": "Utilities",
    "choco": "1password",
    "content": "1Password",
    "description": "1Password is a password manager that allows you to store and manage your passwords securely.",
    "link": "https://1password.com/",
    "winget": "AgileBits.1Password"
  },
  "WPFInstall7zip": {
    "category": "Utilities",
    "choco": "7zip",
    "content": "7-Zip",
    "description": "7-Zip is a free and open-source file archiver utility. It supports several compression formats and provides a high compression ratio, making it a popular choice for file compression.",
    "link": "https://www.7-zip.org/",
    "winget": "7zip.7zip"
  },
  "WPFInstalladobe": {
    "category": "Document",
    "choco": "adobereader",
    "content": "Adobe Acrobat Reader",
    "description": "Adobe Acrobat Reader is a free PDF viewer with essential features for viewing, printing, and annotating PDF documents.",
    "link": "https://www.adobe.com/acrobat/pdf-reader.html",
    "winget": "Adobe.Acrobat.Reader.64-bit"
  },
  "WPFInstalladvancedip": {
    "category": "Pro Tools",
    "choco": "advanced-ip-scanner",
    "content": "Advanced IP Scanner",
    "description": "Advanced IP Scanner is a fast and easy-to-use network scanner. It is designed to analyze LAN networks and provides information about connected devices.",
    "link": "https://www.advanced-ip-scanner.com/",
    "winget": "Famatech.AdvancedIPScanner"
  },
  "WPFInstallaimp": {
    "category": "Multimedia Tools",
    "choco": "aimp",
    "content": "AIMP (Music Player)",
    "description": "AIMP is a feature-rich music player with support for various audio formats, playlists, and customizable user interface.",
    "link": "https://www.aimp.ru/",
    "winget": "AIMP.AIMP"
  },
  "WPFInstallalacritty": {
    "category": "Utilities",
    "choco": "alacritty",
    "content": "Alacritty Terminal",
    "description": "Alacritty is a fast, cross-platform, and GPU-accelerated terminal emulator. It is designed for performance and aims to be the fastest terminal emulator available.",
    "link": "https://alacritty.org/",
    "winget": "Alacritty.Alacritty"
  },
  "WPFInstallanaconda3": {
    "category": "Development",
    "choco": "anaconda3",
    "content": "Anaconda",
    "description": "Anaconda is a distribution of the Python and R programming languages for scientific computing.",
    "link": "https://www.anaconda.com/products/distribution",
    "winget": "Anaconda.Anaconda3"
  },
  "WPFInstallangryipscanner": {
    "category": "Pro Tools",
    "choco": "angryip",
    "content": "Angry IP Scanner",
    "description": "Angry IP Scanner is an open-source and cross-platform network scanner. It is used to scan IP addresses and ports, providing information about network connectivity.",
    "link": "https://angryip.org/",
    "winget": "angryziber.AngryIPScanner"
  },
  "WPFInstallanki": {
    "category": "Document",
    "choco": "anki",
    "content": "Anki",
    "description": "Anki is a flashcard application that helps you memorize information with intelligent spaced repetition.",
    "link": "https://apps.ankiweb.net/",
    "winget": "Anki.Anki"
  },
  "WPFInstallanydesk": {
    "category": "Utilities",
    "choco": "anydesk",
    "content": "AnyDesk",
    "description": "AnyDesk is a remote desktop software that enables users to access and control computers remotely. It is known for its fast connection and low latency.",
    "link": "https://anydesk.com/",
    "winget": "AnyDeskSoftwareGmbH.AnyDesk"
  },
  "WPFInstallATLauncher": {
    "category": "Games",
    "choco": "na",
    "content": "ATLauncher",
    "description": "ATLauncher is a Launcher for Minecraft which integrates multiple different ModPacks to allow you to download and install ModPacks easily and quickly.",
    "link": "https://github.com/ATLauncher/ATLauncher",
    "winget": "ATLauncher.ATLauncher"
  },
  "WPFInstallaudacity": {
    "category": "Multimedia Tools",
    "choco": "audacity",
    "content": "Audacity",
    "description": "Audacity is a free and open-source audio editing software known for its powerful recording and editing capabilities.",
    "link": "https://www.audacityteam.org/",
    "winget": "Audacity.Audacity"
  },
  "WPFInstallauthy": {
    "category": "Utilities",
    "choco": "authy-desktop",
    "content": "Authy",
    "description": "Simple and cross-platform 2FA app",
    "link": "https://authy.com/",
    "winget": "Twilio.Authy"
  },
  "WPFInstallautoruns": {
    "category": "Microsoft Tools",
    "choco": "autoruns",
    "content": "Autoruns",
    "description": "This utility shows you what programs are configured to run during system bootup or login",
    "link": "https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns",
    "winget": "Microsoft.Sysinternals.Autoruns"
  },
  "WPFInstallautohotkey": {
    "category": "Utilities",
    "choco": "autohotkey",
    "content": "AutoHotkey",
    "description": "AutoHotkey is a scripting language for Windows that allows users to create custom automation scripts and macros. It is often used for automating repetitive tasks and customizing keyboard shortcuts.",
    "link": "https://www.autohotkey.com/",
    "winget": "AutoHotkey.AutoHotkey"
  },
  "WPFInstallazuredatastudio": {
    "category": "Microsoft Tools",
    "choco": "azure-data-studio",
    "content": "Microsoft Azure Data Studio",
    "description": "Azure Data Studio is a data management tool that enables you to work with SQL Server, Azure SQL DB and SQL DW from Windows, macOS and Linux.",
    "link": "https://docs.microsoft.com/sql/azure-data-studio/what-is-azure-data-studio",
    "winget": "Microsoft.AzureDataStudio"
  },
  "WPFInstallbarrier": {
    "category": "Utilities",
    "choco": "barrier",
    "content": "Barrier",
    "description": "Barrier is an open-source software KVM (keyboard, video, and mouseswitch). It allows users to control multiple computers with a single keyboard and mouse, even if they have different operating systems.",
    "link": "https://github.com/debauchee/barrier",
    "winget": "DebaucheeOpenSourceGroup.Barrier"
  },
  "WPFInstallbat": {
    "category": "Utilities",
    "choco": "bat",
    "content": "Bat (Cat)",
    "description": "Bat is a cat command clone with syntax highlighting. It provides a user-friendly and feature-rich alternative to the traditional cat command for viewing and concatenating files.",
    "link": "https://github.com/sharkdp/bat",
    "winget": "sharkdp.bat"
  },
  "WPFInstallbitcomet": {
    "category": "Utilities",
    "choco": "bitcomet",
    "content": "BitComet",
    "description": "BitComet is a free and open-source BitTorrent client that supports HTTP/FTP downloads and provides download management features.",
    "link": "https://www.bitcomet.com/",
    "winget": "CometNetwork.BitComet"
  },
  "WPFInstallbitwarden": {
    "category": "Utilities",
    "choco": "bitwarden",
    "content": "Bitwarden",
    "description": "Bitwarden is an open-source password management solution. It allows users to store and manage their passwords in a secure and encrypted vault, accessible across multiple devices.",
    "link": "https://bitwarden.com/",
    "winget": "Bitwarden.Bitwarden"
  },
  "WPFInstallbleachbit": {
    "category": "Utilities",
    "choco": "bleachbit",
    "content": "BleachBit",
    "description": "Clean Your System and Free Disk Space",
    "link": "https://www.bleachbit.org/",
    "winget": "BleachBit.BleachBit"
  },
  "WPFInstallblender": {
    "category": "Multimedia Tools",
    "choco": "blender",
    "content": "Blender (3D Graphics)",
    "description": "Blender is a powerful open-source 3D creation suite, offering modeling, sculpting, animation, and rendering tools.",
    "link": "https://www.blender.org/",
    "winget": "BlenderFoundation.Blender"
  },
  "WPFInstallbluestacks": {
    "category": "Games",
    "choco": "bluestacks",
    "content": "Bluestacks",
    "description": "Bluestacks is an Android emulator for running mobile apps and games on a PC.",
    "link": "https://www.bluestacks.com/",
    "winget": "BlueStack.BlueStacks"
  },
  "WPFInstallbrave": {
    "category": "Browsers",
    "choco": "brave",
    "content": "Brave",
    "description": "Brave is a privacy-focused web browser that blocks ads and trackers, offering a faster and safer browsing experience.",
    "link": "https://www.brave.com",
    "winget": "Brave.Brave"
  },
  "WPFInstallbulkcrapuninstaller": {
    "category": "Utilities",
    "choco": "bulk-crap-uninstaller",
    "content": "Bulk Crap Uninstaller",
    "description": "Bulk Crap Uninstaller is a free and open-source uninstaller utility for Windows. It helps users remove unwanted programs and clean up their system by uninstalling multiple applications at once.",
    "link": "https://www.bcuninstaller.com/",
    "winget": "Klocman.BulkCrapUninstaller"
  },
  "WPFInstallbulkrenameutility": {
    "category": "Utilities",
    "choco": "bulkrenameutility",
    "content": "Bulk Rename Utility",
    "description": "Bulk Rename Utility allows you to easily rename files and folders recursively based upon find-replace, character place, fields, sequences, regular expressions, EXIF data, and more.",
    "link": "https://www.bulkrenameutility.co.uk",
    "winget": "TGRMNSoftware.BulkRenameUtility"
  },
  "WPFInstallcalibre": {
    "category": "Document",
    "choco": "calibre",
    "content": "Calibre",
    "description": "Calibre is a powerful and easy-to-use e-book manager, viewer, and converter.",
    "link": "https://calibre-ebook.com/",
    "winget": "calibre.calibre"
  },
  "WPFInstallcarnac": {
    "category": "Utilities",
    "choco": "carnac",
    "content": "Carnac",
    "description": "Carnac is a keystroke visualizer for Windows. It displays keystrokes in an overlay, making it useful for presentations, tutorials, and live demonstrations.",
    "link": "https://carnackeys.com/",
    "winget": "code52.Carnac"
  },
  "WPFInstallcemu": {
    "category": "Games",
    "choco": "cemu",
    "content": "Cemu",
    "description": "Cemu is a highly experimental software to emulate Wii U applications on PC.",
    "link": "https://cemu.info/",
    "winget": "Cemu.Cemu"
  },
  "WPFInstallchatterino": {
    "category": "Communications",
    "choco": "chatterino",
    "content": "Chatterino",
    "description": "Chatterino is a chat client for Twitch chat that offers a clean and customizable interface for a better streaming experience.",
    "link": "https://www.chatterino.com/",
    "winget": "ChatterinoTeam.Chatterino"
  },
  "WPFInstallchrome": {
    "category": "Browsers",
    "choco": "googlechrome",
    "content": "Chrome",
    "description": "Google Chrome is a widely used web browser known for its speed, simplicity, and seamless integration with Google services.",
    "link": "https://www.google.com/chrome/",
    "winget": "Google.Chrome"
  },
  "WPFInstallchromium": {
    "category": "Browsers",
    "choco": "chromium",
    "content": "Chromium",
    "description": "Chromium is the open-source project that serves as the foundation for various web browsers, including Chrome.",
    "link": "https://github.com/Hibbiki/chromium-win64",
    "winget": "Hibbiki.Chromium"
  },
  "WPFInstallclementine": {
    "category": "Multimedia Tools",
    "choco": "clementine",
    "content": "Clementine",
    "description": "Clementine is a modern music player and library organizer, supporting various audio formats and online radio services.",
    "link": "https://www.clementine-player.org/",
    "winget": "Clementine.Clementine"
  },
  "WPFInstallclink": {
    "category": "Development",
    "choco": "clink",
    "content": "Clink",
    "description": "Clink is a powerful Bash-compatible command-line interface (CLIenhancement for Windows, adding features like syntax highlighting and improved history).",
    "link": "https://mridgers.github.io/clink/",
    "winget": "chrisant996.Clink"
  },
  "WPFInstallclonehero": {
    "category": "Games",
    "choco": "na",
    "content": "Clone Hero",
    "description": "Clone Hero is a free rhythm game, which can be played with any 5 or 6 button guitar controller.",
    "link": "https://clonehero.net/",
    "winget": "CloneHeroTeam.CloneHero"
  },
  "WPFInstallcmake": {
    "category": "Development",
    "choco": "cmake",
    "content": "CMake",
    "description": "CMake is an open-source, cross-platform family of tools designed to build, test and package software.",
    "link": "https://cmake.org/",
    "winget": "Kitware.CMake"
  },
  "WPFInstallcopyq": {
    "category": "Utilities",
    "choco": "copyq",
    "content": "CopyQ (Clipboard Manager)",
    "description": "CopyQ is a clipboard manager with advanced features, allowing you to store, edit, and retrieve clipboard history.",
    "link": "https://copyq.readthedocs.io/",
    "winget": "hluk.CopyQ"
  },
  "WPFInstallcpuz": {
    "category": "Utilities",
    "choco": "cpu-z",
    "content": "CPU-Z",
    "description": "CPU-Z is a system monitoring and diagnostic tool for Windows. It provides detailed information about the computer&#39;s hardware components, including the CPU, memory, and motherboard.",
    "link": "https://www.cpuid.com/softwares/cpu-z.html",
    "winget": "CPUID.CPU-Z"
  },
  "WPFInstallcrystaldiskinfo": {
    "category": "Utilities",
    "choco": "crystaldiskinfo",
    "content": "Crystal Disk Info",
    "description": "Crystal Disk Info is a disk health monitoring tool that provides information about the status and performance of hard drives. It helps users anticipate potential issues and monitor drive health.",
    "link": "https://crystalmark.info/en/software/crystaldiskinfo/",
    "winget": "CrystalDewWorld.CrystalDiskInfo"
  },
  "WPFInstallcapframex": {
    "category": "Utilities",
    "choco": "na",
    "content": "CapFrameX",
    "description": "Frametimes capture and analysis tool based on Intel&#39;s PresentMon. Overlay provided by Rivatuner Statistics Server.",
    "link": "https://www.capframex.com/",
    "winget": "CXWorld.CapFrameX"
  },
  "WPFInstallcrystaldiskmark": {
    "category": "Utilities",
    "choco": "crystaldiskmark",
    "content": "Crystal Disk Mark",
    "description": "Crystal Disk Mark is a disk benchmarking tool that measures the read and write speeds of storage devices. It helps users assess the performance of their hard drives and SSDs.",
    "link": "https://crystalmark.info/en/software/crystaldiskmark/",
    "winget": "CrystalDewWorld.CrystalDiskMark"
  },
  "WPFInstalldarktable": {
    "category": "Multimedia Tools",
    "choco": "darktable",
    "content": "darktable",
    "description": "Open-source photo editing tool, offering an intuitive interface, advanced editing capabilities, and a non-destructive workflow for seamless image enhancement.",
    "link": "https://www.darktable.org/install/",
    "winget": "darktable.darktable"
  },
  "WPFInstallDaxStudio": {
    "category": "Development",
    "choco": "daxstudio",
    "content": "DaxStudio",
    "description": "DAX (Data Analysis eXpressions) Studio is the ultimate tool for executing and analyzing DAX queries against Microsoft Tabular models.",
    "link": "https://daxstudio.org/",
    "winget": "DaxStudio.DaxStudio"
  },
  "WPFInstallddu": {
    "category": "Utilities",
    "choco": "ddu",
    "content": "Display Driver Uninstaller",
    "description": "Display Driver Uninstaller (DDU) is a tool for completely uninstalling graphics drivers from NVIDIA, AMD, and Intel. It is useful for troubleshooting graphics driver-related issues.",
    "link": "https://www.wagnardsoft.com/display-driver-uninstaller-DDU-",
    "winget": "ddu"
  },
  "WPFInstalldeluge": {
    "category": "Utilities",
    "choco": "deluge",
    "content": "Deluge",
    "description": "Deluge is a free and open-source BitTorrent client. It features a user-friendly interface, support for plugins, and the ability to manage torrents remotely.",
    "link": "https://deluge-torrent.org/",
    "winget": "DelugeTeam.Deluge"
  },
  "WPFInstalldevtoys": {
    "category": "Utilities",
    "choco": "devtoys",
    "content": "DevToys",
    "description": "DevToys is a collection of development-related utilities and tools for Windows. It includes tools for file management, code formatting, and productivity enhancements for developers.",
    "link": "https://devtoys.app/",
    "winget": "9PGCV4V3BK4W"
  },
  "WPFInstalldigikam": {
    "category": "Multimedia Tools",
    "choco": "digikam",
    "content": "digiKam",
    "description": "digiKam is an advanced open-source photo management software with features for organizing, editing, and sharing photos.",
    "link": "https://www.digikam.org/",
    "winget": "KDE.digikam"
  },
  "WPFInstalldiscord": {
    "category": "Communications",
    "choco": "discord",
    "content": "Discord",
    "description": "Discord is a popular communication platform with voice, video, and text chat, designed for gamers but used by a wide range of communities.",
    "link": "https://discord.com/",
    "winget": "Discord.Discord"
  },
  "WPFInstalldockerdesktop": {
    "category": "Development",
    "choco": "docker-desktop",
    "content": "Docker Desktop",
    "description": "Docker Desktop is a powerful tool for containerized application development and deployment.",
    "link": "https://www.docker.com/products/docker-desktop",
    "winget": "Docker.DockerDesktop"
  },
  "WPFInstalldotnet3": {
    "category": "Microsoft Tools",
    "choco": "dotnetcore3-desktop-runtime",
    "content": ".NET Desktop Runtime 3.1",
    "description": ".NET Desktop Runtime 3.1 is a runtime environment required for running applications developed with .NET Core 3.1.",
    "link": "https://dotnet.microsoft.com/download/dotnet/3.1",
    "winget": "Microsoft.DotNet.DesktopRuntime.3_1"
  },
  "WPFInstalldotnet5": {
    "category": "Microsoft Tools",
    "choco": "dotnet-5.0-runtime",
    "content": ".NET Desktop Runtime 5",
    "description": ".NET Desktop Runtime 5 is a runtime environment required for running applications developed with .NET 5.",
    "link": "https://dotnet.microsoft.com/download/dotnet/5.0",
    "winget": "Microsoft.DotNet.DesktopRuntime.5"
  },
  "WPFInstalldotnet6": {
    "category": "Microsoft Tools",
    "choco": "dotnet-6.0-runtime",
    "content": ".NET Desktop Runtime 6",
    "description": ".NET Desktop Runtime 6 is a runtime environment required for running applications developed with .NET 6.",
    "link": "https://dotnet.microsoft.com/download/dotnet/6.0",
    "winget": "Microsoft.DotNet.DesktopRuntime.6"
  },
  "WPFInstalldotnet7": {
    "category": "Microsoft Tools",
    "choco": "dotnet-7.0-runtime",
    "content": ".NET Desktop Runtime 7",
    "description": ".NET Desktop Runtime 7 is a runtime environment required for running applications developed with .NET 7.",
    "link": "https://dotnet.microsoft.com/download/dotnet/7.0",
    "winget": "Microsoft.DotNet.DesktopRuntime.7"
  },
  "WPFInstalldotnet8": {
    "category": "Microsoft Tools",
    "choco": "dotnet-8.0-runtime",
    "content": ".NET Desktop Runtime 8",
    "description": ".NET Desktop Runtime 8 is a runtime environment required for running applications developed with .NET 8.",
    "link": "https://dotnet.microsoft.com/download/dotnet/8.0",
    "winget": "Microsoft.DotNet.DesktopRuntime.8"
  },
  "WPFInstalldmt": {
    "winget": "GNE.DualMonitorTools",
    "choco": "dual-monitor-tools",
    "category": "Utilities",
    "content": "Dual Monitor Tools",
    "link": "https://dualmonitortool.sourceforge.net/",
    "description": "Dual Monitor Tools (DMT) is a FOSS app that customize handling multiple monitors and even lock the mouse on specific monitor. Useful for full screen games and apps that does not handle well a second monitor or helps the workflow."
  },
  "WPFInstallduplicati": {
    "category": "Utilities",
    "choco": "duplicati",
    "content": "Duplicati",
    "description": "Duplicati is an open-source backup solution that supports encrypted, compressed, and incremental backups. It is designed to securely store data on cloud storage services.",
    "link": "https://www.duplicati.com/",
    "winget": "Duplicati.Duplicati"
  },
  "WPFInstalleaapp": {
    "category": "Games",
    "choco": "ea-app",
    "content": "EA App",
    "description": "EA App is a platform for accessing and playing Electronic Arts games.",
    "link": "https://www.ea.com/ea-app",
    "winget": "ElectronicArts.EADesktop"
  },
  "WPFInstalleartrumpet": {
    "category": "Multimedia Tools",
    "choco": "eartrumpet",
    "content": "EarTrumpet (Audio)",
    "description": "EarTrumpet is an audio control app for Windows, providing a simple and intuitive interface for managing sound settings.",
    "link": "https://eartrumpet.app/",
    "winget": "File-New-Project.EarTrumpet"
  },
  "WPFInstalledge": {
    "category": "Browsers",
    "choco": "microsoft-edge",
    "content": "Edge",
    "description": "Microsoft Edge is a modern web browser built on Chromium, offering performance, security, and integration with Microsoft services.",
    "link": "https://www.microsoft.com/edge",
    "winget": "Microsoft.Edge"
  },
  "WPFInstallefibooteditor": {
    "category": "Pro Tools",
    "choco": "na",
    "content": "EFI Boot Editor",
    "description": "EFI Boot Editor is a tool for managing the EFI/UEFI boot entries on your system. It allows you to customize the boot configuration of your computer.",
    "link": "https://www.easyuefi.com/",
    "winget": "EFIBootEditor.EFIBootEditor"
  },
  "WPFInstallemulationstation": {
    "category": "Games",
    "choco": "emulationstation",
    "content": "Emulation Station",
    "description": "Emulation Station is a graphical and themeable emulator front-end that allows you to access all your favorite games in one place.",
    "link": "https://emulationstation.org/",
    "winget": "Emulationstation.Emulationstation"
  },
  "WPFInstallepicgames": {
    "category": "Games",
    "choco": "epicgameslauncher",
    "content": "Epic Games Launcher",
    "description": "Epic Games Launcher is the client for accessing and playing games from the Epic Games Store.",
    "link": "https://www.epicgames.com/store/en-US/",
    "winget": "EpicGames.EpicGamesLauncher"
  },
  "WPFInstallerrorlookup": {
    "category": "Utilities",
    "choco": "na",
    "content": "Windows Error Code Lookup",
    "description": "ErrorLookup is a tool for looking up Windows error codes and their descriptions.",
    "link": "https://github.com/HenryPP/ErrorLookup",
    "winget": "Henry++.ErrorLookup"
  },
  "WPFInstallesearch": {
    "category": "Utilities",
    "choco": "everything",
    "content": "Everything Search",
    "description": "Everything Search is a fast and efficient file search utility for Windows.",
    "link": "https://www.voidtools.com/",
    "winget": "voidtools.Everything"
  },
  "WPFInstallespanso": {
    "category": "Utilities",
    "choco": "espanso",
    "content": "Espanso",
    "description": "Cross-platform and open-source Text Expander written in Rust",
    "link": "https://espanso.org/",
    "winget": "Espanso.Espanso"
  },
  "WPFInstalletcher": {
    "category": "Utilities",
    "choco": "etcher",
    "content": "Etcher USB Creator",
    "description": "Etcher is a powerful tool for creating bootable USB drives with ease.",
    "link": "https://www.balena.io/etcher/",
    "winget": "Balena.Etcher"
  },
  "WPFInstallfalkon": {
    "category": "Browsers",
    "choco": "falkon",
    "content": "Falkon",
    "description": "Falkon is a lightweight and fast web browser with a focus on user privacy and efficiency.",
    "link": "https://www.falkon.org/",
    "winget": "KDE.Falkon"
  },
  "WPFInstallferdium": {
    "category": "Communications",
    "choco": "ferdium",
    "content": "Ferdium",
    "description": "Ferdium is a messaging application that combines multiple messaging services into a single app for easy management.",
    "link": "https://ferdium.org/",
    "winget": "Ferdium.Ferdium"
  },
  "WPFInstallffmpeg": {
    "category": "Multimedia Tools",
    "choco": "ffmpeg-full",
    "content": "FFmpeg (full)",
    "description": "FFmpeg is a powerful multimedia processing tool that enables users to convert, edit, and stream audio and video files with a vast range of codecs and formats.",
    "link": "https://ffmpeg.org/",
    "winget": "Gyan.FFmpeg"
  },
  "WPFInstallfileconverter": {
    "category": "Utilities",
    "choco": "files",
    "content": "File-Converter",
    "description": "File Converter is a very simple tool which allows you to convert and compress one or several file(s) using the context menu in windows explorer.",
    "link": "https://file-converter.io/",
    "winget": "AdrienAllard.FileConverter"
  },
  "WPFInstallfirealpaca": {
    "category": "Multimedia Tools",
    "choco": "firealpaca",
    "content": "Fire Alpaca",
    "description": "Fire Alpaca is a free digital painting software that provides a wide range of drawing tools and a user-friendly interface.",
    "link": "https://firealpaca.com/",
    "winget": "FireAlpaca.FireAlpaca"
  },
  "WPFInstallfirefox": {
    "category": "Browsers",
    "choco": "firefox",
    "content": "Firefox",
    "description": "Mozilla Firefox is an open-source web browser known for its customization options, privacy features, and extensions.",
    "link": "https://www.mozilla.org/en-US/firefox/new/",
    "winget": "Mozilla.Firefox"
  },
  "WPFInstallfirefoxesr": {
    "category": "Browsers",
    "choco": "FirefoxESR",
    "content": "Firefox ESR",
    "description": "Mozilla Firefox is an open-source web browser known for its customization options, privacy features, and extensions. Firefox ESR (Extended Support Release) receives major updates every 42 weeks with minor updates such as crash fixes, security fixes and policy updates as needed, but at least every four weeks.",
    "link": "https://www.mozilla.org/en-US/firefox/enterprise/",
    "winget": "Mozilla.Firefox.ESR"
  },
  "WPFInstallflameshot": {
    "category": "Multimedia Tools",
    "choco": "flameshot",
    "content": "Flameshot (Screenshots)",
    "description": "Flameshot is a powerful yet simple to use screenshot software, offering annotation and editing features.",
    "link": "https://flameshot.org/",
    "winget": "Flameshot.Flameshot"
  },
  "WPFInstalllightshot": {
    "category": "Multimedia Tools",
    "choco": "lightshot",
    "content": "Lightshot (Screenshots)",
    "description": "Ligthshot is an Easy-to-use, light-weight screenshot software tool, where you can optionally edit your screenshots using different tools, share them via Internet and/or save to disk, and customize the available options.",
    "link": "https://app.prntscr.com/",
    "winget": "Skillbrains.Lightshot"
  },
  "WPFInstallfloorp": {
    "category": "Browsers",
    "choco": "na",
    "content": "Floorp",
    "description": "Floorp is an open-source web browser project that aims to provide a simple and fast browsing experience.",
    "link": "https://floorp.app/",
    "winget": "Ablaze.Floorp"
  },
  "WPFInstallflow": {
    "category": "Utilities",
    "choco": "flow-launcher",
    "content": "Flow launcher",
    "description": "Keystroke launcher for Windows to search, manage and launch files, folders bookmarks, websites and more.",
    "link": "https://www.flowlauncher.com/",
    "winget": "Flow-Launcher.Flow-Launcher"
  },
  "WPFInstallflux": {
    "category": "Utilities",
    "choco": "flux",
    "content": "F.lux",
    "description": "f.lux adjusts the color temperature of your screen to reduce eye strain during nighttime use.",
    "link": "https://justgetflux.com/",
    "winget": "flux.flux"
  },
  "WPFInstallfoobar": {
    "category": "Multimedia Tools",
    "choco": "foobar2000",
    "content": "foobar2000 (Music Player)",
    "description": "foobar2000 is a highly customizable and extensible music player for Windows, known for its modular design and advanced features.",
    "link": "https://www.foobar2000.org/",
    "winget": "PeterPawlowski.foobar2000"
  },
  "WPFInstallfoxpdfeditor": {
    "category": "Document",
    "choco": "na",
    "content": "Foxit PDF Editor",
    "description": "Foxit PDF Editor is a feature-rich PDF editor and viewer with a familiar ribbon-style interface.",
    "link": "https://www.foxit.com/pdf-editor/",
    "winget": "Foxit.PhantomPDF"
  },
  "WPFInstallfoxpdfreader": {
    "category": "Document",
    "choco": "foxitreader",
    "content": "Foxit PDF Reader",
    "description": "Foxit PDF Reader is a free PDF viewer with a familiar ribbon-style interface.",
    "link": "https://www.foxit.com/pdf-reader/",
    "winget": "Foxit.FoxitReader"
  },
  "WPFInstallfreecad": {
    "category": "Multimedia Tools",
    "choco": "freecad",
    "content": "FreeCAD",
    "description": "FreeCAD is a parametric 3D CAD modeler, designed for product design and engineering tasks, with a focus on flexibility and extensibility.",
    "link": "https://www.freecadweb.org/",
    "winget": "FreeCAD.FreeCAD"
  },
  "WPFInstallorcaslicer": {
    "category": "Multimedia Tools",
    "choco": "orcaslicer",
    "content": "OrcaSlicer",
    "description": "G-code generator for 3D printers (Bambu, Prusa, Voron, VzBot, RatRig, Creality, etc.)",
    "link": "https://github.com/SoftFever/OrcaSlicer",
    "winget": "SoftFever.OrcaSlicer"
  },
  "WPFInstallfxsound": {
    "category": "Multimedia Tools",
    "choco": "fxsound",
    "content": "FxSound",
    "description": "FxSound is a cutting-edge audio enhancement software that elevates your listening experience across all media.",
    "link": "https://www.fxsound.com/",
    "winget": "FxSoundLLC.FxSound"
  },
  "WPFInstallfzf": {
    "category": "Utilities",
    "choco": "fzf",
    "content": "Fzf",
    "description": "A command-line fuzzy finder",
    "link": "https://github.com/junegunn/fzf/",
    "winget": "junegunn.fzf"
  },
  "WPFInstallgeforcenow": {
    "category": "Games",
    "choco": "nvidia-geforce-now",
    "content": "GeForce NOW",
    "description": "GeForce NOW is a cloud gaming service that allows you to play high-quality PC games on your device.",
    "link": "https://www.nvidia.com/en-us/geforce-now/",
    "winget": "Nvidia.GeForceNow"
  },
  "WPFInstallgimp": {
    "category": "Multimedia Tools",
    "choco": "gimp",
    "content": "GIMP (Image Editor)",
    "description": "GIMP is a versatile open-source raster graphics editor used for tasks such as photo retouching, image editing, and image composition.",
    "link": "https://www.gimp.org/",
    "winget": "GIMP.GIMP"
  },
  "WPFInstallgit": {
    "category": "Development",
    "choco": "git",
    "content": "Git",
    "description": "Git is a distributed version control system widely used for tracking changes in source code during software development.",
    "link": "https://git-scm.com/",
    "winget": "Git.Git"
  },
  "WPFInstallgitextensions": {
    "category": "Development",
    "choco": "git;gitextensions",
    "content": "Git Extensions",
    "description": "Git Extensions is a graphical user interface for Git, providing additional features for easier source code management.",
    "link": "https://gitextensions.github.io/",
    "winget": "Git.Git;GitExtensionsTeam.GitExtensions"
  },
  "WPFInstallgithubcli": {
    "category": "Development",
    "choco": "git;gh",
    "content": "GitHub CLI",
    "description": "GitHub CLI is a command-line tool that simplifies working with GitHub directly from the terminal.",
    "link": "https://cli.github.com/",
    "winget": "Git.Git;GitHub.cli"
  },
  "WPFInstallgithubdesktop": {
    "category": "Development",
    "choco": "git;github-desktop",
    "content": "GitHub Desktop",
    "description": "GitHub Desktop is a visual Git client that simplifies collaboration on GitHub repositories with an easy-to-use interface.",
    "link": "https://desktop.github.com/",
    "winget": "Git.Git;GitHub.GitHubDesktop"
  },
  "WPFInstallglaryutilities": {
    "category": "Utilities",
    "choco": "glaryutilities-free",
    "content": "Glary Utilities",
    "description": "Glary Utilities is a comprehensive system optimization and maintenance tool for Windows.",
    "link": "https://www.glarysoft.com/glary-utilities/",
    "winget": "Glarysoft.GlaryUtilities"
  },
  "WPFInstallgog": {
    "category": "Games",
    "choco": "goggalaxy",
    "content": "GOG Galaxy",
    "description": "GOG Galaxy is a gaming client that offers DRM-free games, additional content, and more.",
    "link": "https://www.gog.com/galaxy",
    "winget": "GOG.Galaxy"
  },
  "WPFInstallgolang": {
    "category": "Development",
    "choco": "golang",
    "content": "GoLang",
    "description": "GoLang (or Golang) is a statically typed, compiled programming language designed for simplicity, reliability, and efficiency.",
    "link": "https://golang.org/",
    "winget": "GoLang.Go"
  },
  "WPFInstallgoogledrive": {
    "category": "Utilities",
    "choco": "googledrive",
    "content": "Google Drive",
    "description": "File syncing across devices all tied to your google account",
    "link": "https://www.google.com/drive/",
    "winget": "Google.Drive"
  },
  "WPFInstallgpuz": {
    "category": "Utilities",
    "choco": "gpu-z",
    "content": "GPU-Z",
    "description": "GPU-Z provides detailed information about your graphics card and GPU.",
    "link": "https://www.techpowerup.com/gpuz/",
    "winget": "TechPowerUp.GPU-Z"
  },
  "WPFInstallgreenshot": {
    "category": "Multimedia Tools",
    "choco": "greenshot",
    "content": "Greenshot (Screenshots)",
    "description": "Greenshot is a light-weight screenshot software tool with built-in image editor and customizable capture options.",
    "link": "https://getgreenshot.org/",
    "winget": "Greenshot.Greenshot"
  },
  "WPFInstallgsudo": {
    "category": "Utilities",
    "choco": "gsudo",
    "content": "Gsudo",
    "description": "Gsudo is a sudo implementation for Windows, allowing elevated privilege execution.",
    "link": "https://gerardog.github.io/gsudo/",
    "winget": "gerardog.gsudo"
  },
  "WPFInstallguilded": {
    "category": "Communications",
    "choco": "na",
    "content": "Guilded",
    "description": "Guilded is a communication and productivity platform that includes chat, scheduling, and collaborative tools for gaming and communities.",
    "link": "https://www.guilded.gg/",
    "winget": "Guilded.Guilded"
  },
  "WPFInstallhandbrake": {
    "category": "Multimedia Tools",
    "choco": "handbrake",
    "content": "HandBrake",
    "description": "HandBrake is an open-source video transcoder, allowing you to convert video from nearly any format to a selection of widely supported codecs.",
    "link": "https://handbrake.fr/",
    "winget": "HandBrake.HandBrake"
  },
  "WPFInstallharmonoid": {
    "category": "Multimedia Tools",
    "choco": "na",
    "content": "Harmonoid",
    "description": "Plays and manages your music library. Looks beautiful and juicy. Playlists, visuals, synced lyrics, pitch shift, volume boost and more.",
    "link": "https://harmonoid.com/",
    "winget": "Harmonoid.Harmonoid"
  },
  "WPFInstallheidisql": {
    "category": "Pro Tools",
    "choco": "heidisql",
    "content": "HeidiSQL",
    "description": "HeidiSQL is a powerful and easy-to-use client for MySQL, MariaDB, Microsoft SQL Server, and PostgreSQL databases. It provides tools for database management and development.",
    "link": "https://www.heidisql.com/",
    "winget": "HeidiSQL.HeidiSQL"
  },
  "WPFInstallhelix": {
    "category": "Development",
    "choco": "helix",
    "content": "Helix",
    "description": "Helix is a neovim alternative built in rust.",
    "link": "https://helix-editor.com/",
    "winget": "Helix.Helix"
  },
  "WPFInstallheroiclauncher": {
    "category": "Games",
    "choco": "na",
    "content": "Heroic Games Launcher",
    "description": "Heroic Games Launcher is an open-source alternative game launcher for Epic Games Store.",
    "link": "https://heroicgameslauncher.com/",
    "winget": "HeroicGamesLauncher.HeroicGamesLauncher"
  },
  "WPFInstallhexchat": {
    "category": "Communications",
    "choco": "hexchat",
    "content": "Hexchat",
    "description": "HexChat is a free, open-source IRC (Internet Relay Chat) client with a graphical interface for easy communication.",
    "link": "https://hexchat.github.io/",
    "winget": "HexChat.HexChat"
  },
  "WPFInstallhwinfo": {
    "category": "Utilities",
    "choco": "hwinfo",
    "content": "HWiNFO",
    "description": "HWiNFO provides comprehensive hardware information and diagnostics for Windows.",
    "link": "https://www.hwinfo.com/",
    "winget": "REALiX.HWiNFO"
  },
  "WPFInstallhwmonitor": {
    "category": "Utilities",
    "choco": "hwmonitor",
    "content": "HWMonitor",
    "description": "HWMonitor is a hardware monitoring program that reads PC systems main health sensors.",
    "link": "https://www.cpuid.com/softwares/hwmonitor.html",
    "winget": "CPUID.HWMonitor"
  },
  "WPFInstallimageglass": {
    "category": "Multimedia Tools",
    "choco": "imageglass",
    "content": "ImageGlass (Image Viewer)",
    "description": "ImageGlass is a versatile image viewer with support for various image formats and a focus on simplicity and speed.",
    "link": "https://imageglass.org/",
    "winget": "DuongDieuPhap.ImageGlass"
  },
  "WPFInstallimgburn": {
    "category": "Multimedia Tools",
    "choco": "imgburn",
    "content": "ImgBurn",
    "description": "ImgBurn is a lightweight CD, DVD, HD-DVD, and Blu-ray burning application with advanced features for creating and burning disc images.",
    "link": "http://www.imgburn.com/",
    "winget": "LIGHTNINGUK.ImgBurn"
  },
  "WPFInstallinkscape": {
    "category": "Multimedia Tools",
    "choco": "inkscape",
    "content": "Inkscape",
    "description": "Inkscape is a powerful open-source vector graphics editor, suitable for tasks such as illustrations, icons, logos, and more.",
    "link": "https://inkscape.org/",
    "winget": "Inkscape.Inkscape"
  },
  "WPFInstallitch": {
    "category": "Games",
    "choco": "itch",
    "content": "Itch.io",
    "description": "Itch.io is a digital distribution platform for indie games and creative projects.",
    "link": "https://itch.io/",
    "winget": "ItchIo.Itch"
  },
  "WPFInstallitunes": {
    "category": "Multimedia Tools",
    "choco": "itunes",
    "content": "iTunes",
    "description": "iTunes is a media player, media library, and online radio broadcaster application developed by Apple Inc.",
    "link": "https://www.apple.com/itunes/",
    "winget": "Apple.iTunes"
  },
  "WPFInstalljami": {
    "category": "Communications",
    "choco": "jami",
    "content": "Jami",
    "description": "Jami is a secure and privacy-focused communication platform that offers audio and video calls, messaging, and file sharing.",
    "link": "https://jami.net/",
    "winget": "SFLinux.Jami"
  },
  "WPFInstalljava16": {
    "category": "Development",
    "choco": "temurin16jre",
    "content": "OpenJDK Java 16",
    "description": "OpenJDK Java 16 is the latest version of the open-source Java development kit.",
    "link": "https://adoptopenjdk.net/",
    "winget": "AdoptOpenJDK.OpenJDK.16"
  },
  "WPFInstalljava18": {
    "category": "Development",
    "choco": "temurin18jre",
    "content": "Oracle Java 18",
    "description": "Oracle Java 18 is the latest version of the official Java development kit from Oracle.",
    "link": "https://www.oracle.com/java/",
    "winget": "EclipseAdoptium.Temurin.18.JRE"
  },
  "WPFInstalljava20": {
    "category": "Development",
    "choco": "na",
    "content": "Azul Zulu JDK 20",
    "description": "Azul Zulu JDK 20 is a distribution of the OpenJDK with long-term support, performance enhancements, and security updates.",
    "link": "https://www.azul.com/downloads/zulu-community/",
    "winget": "Azul.Zulu.20.JDK"
  },
  "WPFInstalljava21": {
    "category": "Development",
    "choco": "na",
    "content": "Azul Zulu JDK 21",
    "description": "Azul Zulu JDK 21 is a distribution of the OpenJDK with long-term support, performance enhancements, and security updates.",
    "link": "https://www.azul.com/downloads/zulu-community/",
    "winget": "Azul.Zulu.21.JDK"
  },
  "WPFInstalljava8": {
    "category": "Development",
    "choco": "temurin8jre",
    "content": "OpenJDK Java 8",
    "description": "OpenJDK Java 8 is an open-source implementation of the Java Platform, Standard Edition.",
    "link": "https://adoptopenjdk.net/",
    "winget": "EclipseAdoptium.Temurin.8.JRE"
  },
  "WPFInstalljava11runtime": {
    "category": "Development",
    "choco": "na",
    "content": "Eclipse Temurin JRE 11",
    "description": "Eclipse Temurin JRE is the open source Java SE build based upon OpenJRE.",
    "link": "https://adoptium.net/",
    "winget": "EclipseAdoptium.Temurin.11.JRE"
  },
  "WPFInstalljava17runtime": {
    "category": "Development",
    "choco": "na",
    "content": "Eclipse Temurin JRE 17",
    "description": "Eclipse Temurin JRE is the open source Java SE build based upon OpenJRE.",
    "link": "https://adoptium.net/",
    "winget": "EclipseAdoptium.Temurin.17.JRE"
  },
  "WPFInstalljava18runtime": {
    "category": "Development",
    "choco": "na",
    "content": "Eclipse Temurin JRE 18",
    "description": "Eclipse Temurin JRE is the open source Java SE build based upon OpenJRE.",
    "link": "https://adoptium.net/",
    "winget": "EclipseAdoptium.Temurin.18.JRE"
  },
  "WPFInstalljava19runtime": {
    "category": "Development",
    "choco": "na",
    "content": "Eclipse Temurin JRE 19",
    "description": "Eclipse Temurin JRE is the open source Java SE build based upon OpenJRE.",
    "link": "https://adoptium.net/",
    "winget": "EclipseAdoptium.Temurin.19.JRE"
  },
  "WPFInstalljdownloader": {
    "category": "Utilities",
    "choco": "jdownloader",
    "content": "JDownloader",
    "description": "JDownloader is a feature-rich download manager with support for various file hosting services.",
    "link": "http://jdownloader.org/",
    "winget": "AppWork.JDownloader"
  },
  "WPFInstalljellyfinmediaplayer": {
    "category": "Multimedia Tools",
    "choco": "jellyfin-media-player",
    "content": "Jellyfin Media Player",
    "description": "Jellyfin Media Player is a client application for the Jellyfin media server, providing access to your media library.",
    "link": "https://github.com/jellyfin/jellyfin-media-playerf",
    "winget": "Jellyfin.JellyfinMediaPlayer"
  },
  "WPFInstalljellyfinserver": {
    "category": "Multimedia Tools",
    "choco": "jellyfin",
    "content": "Jellyfin Server",
    "description": "Jellyfin Server is an open-source media server software, allowing you to organize and stream your media library.",
    "link": "https://jellyfin.org/",
    "winget": "Jellyfin.Server"
  },
  "WPFInstalljetbrains": {
    "category": "Development",
    "choco": "jetbrainstoolbox",
    "content": "Jetbrains Toolbox",
    "description": "Jetbrains Toolbox is a platform for easy installation and management of JetBrains developer tools.",
    "link": "https://www.jetbrains.com/toolbox/",
    "winget": "JetBrains.Toolbox"
  },
  "WPFInstalljoplin": {
    "category": "Document",
    "choco": "joplin",
    "content": "Joplin (FOSS Notes)",
    "description": "Joplin is an open-source note-taking and to-do application with synchronization capabilities.",
    "link": "https://joplinapp.org/",
    "winget": "Joplin.Joplin"
  },
  "WPFInstalljpegview": {
    "category": "Utilities",
    "choco": "jpegview",
    "content": "JPEG View",
    "description": "JPEGView is a lean, fast and highly configurable viewer/editor for JPEG, BMP, PNG, WEBP, TGA, GIF, JXL, HEIC, HEIF, AVIF and TIFF images with a minimal GUI",
    "link": "https://github.com/sylikc/jpegview",
    "winget": "sylikc.JPEGView"
  },
  "WPFInstallkdeconnect": {
    "category": "Utilities",
    "choco": "kdeconnect-kde",
    "content": "KDE Connect",
    "description": "KDE Connect allows seamless integration between your KDE desktop and mobile devices.",
    "link": "https://community.kde.org/KDEConnect",
    "winget": "KDE.KDEConnect"
  },
  "WPFInstallkdenlive": {
    "category": "Multimedia Tools",
    "choco": "kdenlive",
    "content": "Kdenlive (Video Editor)",
    "description": "Kdenlive is an open-source video editing software with powerful features for creating and editing professional-quality videos.",
    "link": "https://kdenlive.org/",
    "winget": "KDE.Kdenlive"
  },
  "WPFInstallkeepass": {
    "category": "Utilities",
    "choco": "keepassxc",
    "content": "KeePassXC",
    "description": "KeePassXC is a cross-platform, open-source password manager with strong encryption features.",
    "link": "https://keepassxc.org/",
    "winget": "KeePassXCTeam.KeePassXC"
  },
  "WPFInstallklite": {
    "category": "Multimedia Tools",
    "choco": "k-litecodecpack-standard",
    "content": "K-Lite Codec Standard",
    "description": "K-Lite Codec Pack Standard is a collection of audio and video codecs and related tools, providing essential components for media playback.",
    "link": "https://www.codecguide.com/",
    "winget": "CodecGuide.K-LiteCodecPack.Standard"
  },
  "WPFInstallkodi": {
    "category": "Multimedia Tools",
    "choco": "kodi",
    "content": "Kodi Media Center",
    "description": "Kodi is an open-source media center application that allows you to play and view most videos, music, podcasts, and other digital media files.",
    "link": "https://kodi.tv/",
    "winget": "XBMCFoundation.Kodi"
  },
  "WPFInstallkrita": {
    "category": "Multimedia Tools",
    "choco": "krita",
    "content": "Krita (Image Editor)",
    "description": "Krita is a powerful open-source painting application. It is designed for concept artists, illustrators, matte and texture artists, and the VFX industry.",
    "link": "https://krita.org/en/features/",
    "winget": "KDE.Krita"
  },
  "WPFInstalllazygit": {
    "category": "Development",
    "choco": "lazygit",
    "content": "Lazygit",
    "description": "Simple terminal UI for git commands",
    "link": "https://github.com/jesseduffield/lazygit/",
    "winget": "JesseDuffield.lazygit"
  },
  "WPFInstalllibreoffice": {
    "category": "Document",
    "choco": "libreoffice-fresh",
    "content": "LibreOffice",
    "description": "LibreOffice is a powerful and free office suite, compatible with other major office suites.",
    "link": "https://www.libreoffice.org/",
    "winget": "TheDocumentFoundation.LibreOffice"
  },
  "WPFInstalllibrewolf": {
    "category": "Browsers",
    "choco": "librewolf",
    "content": "LibreWolf",
    "description": "LibreWolf is a privacy-focused web browser based on Firefox, with additional privacy and security enhancements.",
    "link": "https://librewolf-community.gitlab.io/",
    "winget": "LibreWolf.LibreWolf"
  },
  "WPFInstalllinkshellextension": {
    "category": "Utilities",
    "choco": "linkshellextension",
    "content": "Link Shell extension",
    "description": "Link Shell Extension (LSE) provides for the creation of Hardlinks, Junctions, Volume Mountpoints, Symbolic Links, a folder cloning process that utilises Hardlinks or Symbolic Links and a copy process taking care of Junctions, Symbolic Links, and Hardlinks. LSE, as its name implies is implemented as a Shell extension and is accessed from Windows Explorer, or similar file/folder managers.",
    "link": "https://schinagl.priv.at/nt/hardlinkshellext/hardlinkshellext.html",
    "winget": "HermannSchinagl.LinkShellExtension"
  },
  "WPFInstalllinphone": {
    "category": "Communications",
    "choco": "linphone",
    "content": "Linphone",
    "description": "Linphone is an open-source voice over IP (VoIPservice that allows for audio and video calls, messaging, and more.",
    "link": "https://www.linphone.org/",
    "winget": "BelledonneCommunications.Linphone"
  },
  "WPFInstalllivelywallpaper": {
    "category": "Utilities",
    "choco": "lively",
    "content": "Lively Wallpaper",
    "description": "Free and open-source software that allows users to set animated desktop wallpapers and screensavers.",
    "link": "https://www.rocksdanister.com/lively/",
    "winget": "rocksdanister.LivelyWallpaper"
  },
  "WPFInstalllocalsend": {
    "category": "Utilities",
    "choco": "localsend.install",
    "content": "LocalSend",
    "description": "An open source cross-platform alternative to AirDrop.",
    "link": "https://localsend.org/",
    "winget": "LocalSend.LocalSend"
  },
  "WPFInstalllockhunter": {
    "category": "Utilities",
    "choco": "lockhunter",
    "content": "LockHunter",
    "description": "LockHunter is a free tool to delete files blocked by something you do not know.",
    "link": "https://lockhunter.com/",
    "winget": "CrystalRich.LockHunter"
  },
  "WPFInstalllogseq": {
    "category": "Document",
    "choco": "logseq",
    "content": "Logseq",
    "description": "Logseq is a versatile knowledge management and note-taking application designed for the digital thinker. With a focus on the interconnectedness of ideas, Logseq allows users to seamlessly organize their thoughts through a combination of hierarchical outlines and bi-directional linking. It supports both structured and unstructured content, enabling users to create a personalized knowledge graph that adapts to their evolving ideas and insights.",
    "link": "https://logseq.com/",
    "winget": "Logseq.Logseq"
  },
  "WPFInstallmalwarebytes": {
    "category": "Utilities",
    "choco": "malwarebytes",
    "content": "Malwarebytes",
    "description": "Malwarebytes is an anti-malware software that provides real-time protection against threats.",
    "link": "https://www.malwarebytes.com/",
    "winget": "Malwarebytes.Malwarebytes"
  },
  "WPFInstallmasscode": {
    "category": "Document",
    "choco": "na",
    "content": "massCode (Snippet Manager)",
    "description": "massCode is a fast and efficient open-source code snippet manager for developers.",
    "link": "https://masscode.io/",
    "winget": "antonreshetov.massCode"
  },
  "WPFInstallmatrix": {
    "category": "Communications",
    "choco": "element-desktop",
    "content": "Matrix",
    "description": "Matrix is an open network for secure, decentralized communication with features like chat, VoIP, and collaboration tools.",
    "link": "https://element.io/",
    "winget": "Element.Element"
  },
  "WPFInstallmeld": {
    "category": "Utilities",
    "choco": "meld",
    "content": "Meld",
    "description": "Meld is a visual diff and merge tool for files and directories.",
    "link": "https://meldmerge.org/",
    "winget": "Meld.Meld"
  },
  "WPFInstallmonitorian": {
    "category": "Utilities",
    "choco": "monitorian",
    "content": "Monitorian",
    "description": "Monitorian is a utility for adjusting monitor brightness and contrast on Windows.",
    "link": "https://github.com/emoacht/Monitorian",
    "winget": "emoacht.Monitorian"
  },
  "WPFInstallmoonlight": {
    "category": "Games",
    "choco": "moonlight-qt",
    "content": "Moonlight/GameStream Client",
    "description": "Moonlight/GameStream Client allows you to stream PC games to other devices over your local network.",
    "link": "https://moonlight-stream.org/",
    "winget": "MoonlightGameStreamingProject.Moonlight"
  },
  "WPFInstallMotrix": {
    "category": "Utilities",
    "choco": "motrix",
    "content": "Motrix Download Manager",
    "description": "A full-featured download manager.",
    "link": "https://motrix.app/",
    "winget": "agalwood.Motrix"
  },
  "WPFInstallmpc": {
    "category": "Multimedia Tools",
    "choco": "mpc-hc",
    "content": "Media Player Classic (Video Player)",
    "description": "Media Player Classic is a lightweight, open-source media player that supports a wide range of audio and video formats. It includes features like customizable toolbars and support for subtitles.",
    "link": "https://mpc-hc.org/",
    "winget": "clsid2.mpc-hc"
  },
  "WPFInstallmremoteng": {
    "category": "Pro Tools",
    "choco": "mremoteng",
    "content": "mRemoteNG",
    "description": "mRemoteNG is a free and open-source remote connections manager. It allows you to view and manage multiple remote sessions in a single interface.",
    "link": "https://mremoteng.org/",
    "winget": "mRemoteNG.mRemoteNG"
  },
  "WPFInstallmsiafterburner": {
    "category": "Utilities",
    "choco": "msiafterburner",
    "content": "MSI Afterburner",
    "description": "MSI Afterburner is a graphics card overclocking utility with advanced features.",
    "link": "https://www.msi.com/Landing/afterburner",
    "winget": "Guru3D.Afterburner"
  },
  "WPFInstallmullvadbrowser": {
    "category": "Browsers",
    "choco": "na",
    "content": "Mullvad Browser",
    "description": "Mullvad Browser is a privacy-focused web browser, developed in partnership with the Tor Project.",
    "link": "https://mullvad.net/browser",
    "winget": "MullvadVPN.MullvadBrowser"
  },
  "WPFInstallmusescore": {
    "category": "Multimedia Tools",
    "choco": "musescore",
    "content": "MuseScore",
    "description": "Create, play back and print beautiful sheet music with free and easy to use music notation software MuseScore.",
    "link": "https://musescore.org/en",
    "winget": "Musescore.Musescore"
  },
  "WPFInstallmusicbee": {
    "category": "Multimedia Tools",
    "choco": "musicbee",
    "content": "MusicBee (Music Player)",
    "description": "MusicBee is a customizable music player with support for various audio formats. It includes features like an integrated search function, tag editing, and more.",
    "link": "https://getmusicbee.com/",
    "winget": "MusicBee.MusicBee"
  },
  "WPFInstallnanazip": {
    "category": "Utilities",
    "choco": "nanazip",
    "content": "NanaZip",
    "description": "NanaZip is a fast and efficient file compression and decompression tool.",
    "link": "https://github.com/M2Team/NanaZip",
    "winget": "M2Team.NanaZip"
  },
  "WPFInstallnaps2": {
    "category": "Document",
    "choco": "naps2",
    "content": "NAPS2 (Document Scanner)",
    "description": "NAPS2 is a document scanning application that simplifies the process of creating electronic documents.",
    "link": "https://www.naps2.com/",
    "winget": "Cyanfish.NAPS2"
  },
  "WPFInstallneofetchwin": {
    "category": "Utilities",
    "choco": "na",
    "content": "Neofetch",
    "description": "Neofetch is a command-line utility for displaying system information in a visually appealing way.",
    "link": "https://github.com/nepnep39/neofetch-win",
    "winget": "nepnep.neofetch-win"
  },
  "WPFInstallneovim": {
    "category": "Development",
    "choco": "neovim",
    "content": "Neovim",
    "description": "Neovim is a highly extensible text editor and an improvement over the original Vim editor.",
    "link": "https://neovim.io/",
    "winget": "Neovim.Neovim"
  },
  "WPFInstallnextclouddesktop": {
    "category": "Utilities",
    "choco": "nextcloud-client",
    "content": "Nextcloud Desktop",
    "description": "Nextcloud Desktop is the official desktop client for the Nextcloud file synchronization and sharing platform.",
    "link": "https://nextcloud.com/install/#install-clients",
    "winget": "Nextcloud.NextcloudDesktop"
  },
  "WPFInstallnglide": {
    "category": "Multimedia Tools",
    "choco": "na",
    "content": "nGlide (3dfx compatibility)",
    "description": "nGlide is a 3Dfx Voodoo Glide wrapper. It allows you to play games that use Glide API on modern graphics cards without the need for a 3Dfx Voodoo graphics card.",
    "link": "http://www.zeus-software.com/downloads/nglide",
    "winget": "ZeusSoftware.nGlide"
  },
  "WPFInstallnmap": {
    "category": "Pro Tools",
    "choco": "nmap",
    "content": "Nmap",
    "description": "Nmap (Network Mapper) is an open-source tool for network exploration and security auditing. It discovers devices on a network and provides information about their ports and services.",
    "link": "https://nmap.org/",
    "winget": "Insecure.Nmap"
  },
  "WPFInstallnodejs": {
    "category": "Development",
    "choco": "nodejs",
    "content": "NodeJS",
    "description": "NodeJS is a JavaScript runtime built on Chrome&#39;s V8 JavaScript engine for building server-side and networking applications.",
    "link": "https://nodejs.org/",
    "winget": "OpenJS.NodeJS"
  },
  "WPFInstallnodejslts": {
    "category": "Development",
    "choco": "nodejs-lts",
    "content": "NodeJS LTS",
    "description": "NodeJS LTS provides Long-Term Support releases for stable and reliable server-side JavaScript development.",
    "link": "https://nodejs.org/",
    "winget": "OpenJS.NodeJS.LTS"
  },
  "WPFInstallnomacs": {
    "category": "Multimedia Tools",
    "choco": "nomacs",
    "content": "Nomacs (Image viewer)",
    "description": "Nomacs is a free, open-source image viewer that supports multiple platforms. It features basic image editing capabilities and supports a variety of image formats.",
    "link": "https://nomacs.org/",
    "winget": "nomacs.nomacs"
  },
  "WPFInstallnotepadplus": {
    "category": "Document",
    "choco": "notepadplusplus",
    "content": "Notepad++",
    "description": "Notepad++ is a free, open-source code editor and Notepad replacement with support for multiple languages.",
    "link": "https://notepad-plus-plus.org/",
    "winget": "Notepad++.Notepad++"
  },
  "WPFInstallnuget": {
    "category": "Microsoft Tools",
    "choco": "nuget.commandline",
    "content": "NuGet",
    "description": "NuGet is a package manager for the .NET framework, enabling developers to manage and share libraries in their .NET applications.",
    "link": "https://www.nuget.org/",
    "winget": "Microsoft.NuGet"
  },
  "WPFInstallnushell": {
    "category": "Utilities",
    "choco": "nushell",
    "content": "Nushell",
    "description": "Nushell is a new shell that takes advantage of modern hardware and systems to provide a powerful, expressive, and fast experience.",
    "link": "https://www.nushell.sh/",
    "winget": "Nushell.Nushell"
  },
  "WPFInstallnvclean": {
    "category": "Utilities",
    "choco": "na",
    "content": "NVCleanstall",
    "description": "NVCleanstall is a tool designed to customize NVIDIA driver installations, allowing advanced users to control more aspects of the installation process.",
    "link": "https://www.techpowerup.com/nvcleanstall/",
    "winget": "TechPowerUp.NVCleanstall"
  },
  "WPFInstallnvm": {
    "category": "Development",
    "choco": "nvm",
    "content": "Node Version Manager",
    "description": "Node Version Manager (NVM) for Windows allows you to easily switch between multiple Node.js versions.",
    "link": "https://github.com/coreybutler/nvm-windows",
    "winget": "CoreyButler.NVMforWindows"
  },
  "WPFInstallobs": {
    "category": "Multimedia Tools",
    "choco": "obs-studio",
    "content": "OBS Studio",
    "description": "OBS Studio is a free and open-source software for video recording and live streaming. It supports real-time video/audio capturing and mixing, making it popular among content creators.",
    "link": "https://obsproject.com/",
    "winget": "OBSProject.OBSStudio"
  },
  "WPFInstallobsidian": {
    "category": "Document",
    "choco": "obsidian",
    "content": "Obsidian",
    "description": "Obsidian is a powerful note-taking and knowledge management application.",
    "link": "https://obsidian.md/",
    "winget": "Obsidian.Obsidian"
  },
  "WPFInstallokular": {
    "category": "Document",
    "choco": "okular",
    "content": "Okular",
    "description": "Okular is a versatile document viewer with advanced features.",
    "link": "https://okular.kde.org/",
    "winget": "KDE.Okular"
  },
  "WPFInstallonedrive": {
    "category": "Microsoft Tools",
    "choco": "onedrive",
    "content": "OneDrive",
    "description": "OneDrive is a cloud storage service provided by Microsoft, allowing users to store and share files securely across devices.",
    "link": "https://onedrive.live.com/",
    "winget": "Microsoft.OneDrive"
  },
  "WPFInstallonlyoffice": {
    "category": "Document",
    "choco": "onlyoffice",
    "content": "ONLYOffice Desktop",
    "description": "ONLYOffice Desktop is a comprehensive office suite for document editing and collaboration.",
    "link": "https://www.onlyoffice.com/desktop.aspx",
    "winget": "ONLYOFFICE.DesktopEditors"
  },
  "WPFInstallOPAutoClicker": {
    "category": "Utilities",
    "choco": "autoclicker",
    "content": "OPAutoClicker",
    "description": "A full-fledged autoclicker with two modes of autoclicking, at your dynamic cursor location or at a prespecified location.",
    "link": "https://www.opautoclicker.com",
    "winget": "OPAutoClicker.OPAutoClicker"
  },
  "WPFInstallopenhashtab": {
    "category": "Utilities",
    "choco": "openhashtab",
    "content": "OpenHashTab",
    "description": "OpenHashTab is a shell extension for conveniently calculating and checking file hashes from file properties.",
    "link": "https://github.com/namazso/OpenHashTab/",
    "winget": "namazso.OpenHashTab"
  },
  "WPFInstallopenoffice": {
    "category": "Document",
    "choco": "openoffice",
    "content": "Apache OpenOffice",
    "description": "Apache OpenOffice is an open-source office software suite for word processing, spreadsheets, presentations, and more.",
    "link": "https://www.openoffice.org/",
    "winget": "Apache.OpenOffice"
  },
  "WPFInstallopenrgb": {
    "category": "Utilities",
    "choco": "openrgb",
    "content": "OpenRGB",
    "description": "OpenRGB is an open-source RGB lighting control software designed to manage and control RGB lighting for various components and peripherals.",
    "link": "https://openrgb.org/",
    "winget": "CalcProgrammer1.OpenRGB"
  },
  "WPFInstallopenscad": {
    "category": "Multimedia Tools",
    "choco": "openscad",
    "content": "OpenSCAD",
    "description": "OpenSCAD is a free and open-source script-based 3D CAD modeler. It is especially useful for creating parametric designs for 3D printing.",
    "link": "https://www.openscad.org/",
    "winget": "OpenSCAD.OpenSCAD"
  },
  "WPFInstallopenshell": {
    "category": "Utilities",
    "choco": "open-shell",
    "content": "Open Shell (Start Menu)",
    "description": "Open Shell is a Windows Start Menu replacement with enhanced functionality and customization options.",
    "link": "https://github.com/Open-Shell/Open-Shell-Menu",
    "winget": "Open-Shell.Open-Shell-Menu"
  },
  "WPFInstallOpenVPN": {
    "category": "Pro Tools",
    "choco": "openvpn-connect",
    "content": "OpenVPN Connect",
    "description": "OpenVPN Connect is an open-source VPN client that allows you to connect securely to a VPN server. It provides a secure and encrypted connection for protecting your online privacy.",
    "link": "https://openvpn.net/",
    "winget": "OpenVPNTechnologies.OpenVPNConnect"
  },
  "WPFInstallOVirtualBox": {
    "category": "Utilities",
    "choco": "virtualbox",
    "content": "Oracle VirtualBox",
    "description": "Oracle VirtualBox is a powerful and free open-source virtualization tool for x86 and AMD64/Intel64 architectures.",
    "link": "https://www.virtualbox.org/",
    "winget": "Oracle.VirtualBox"
  },
  "WPFInstallownclouddesktop": {
    "category": "Utilities",
    "choco": "owncloud-client",
    "content": "ownCloud Desktop",
    "description": "ownCloud Desktop is the official desktop client for the ownCloud file synchronization and sharing platform.",
    "link": "https://owncloud.com/desktop-app/",
    "winget": "ownCloud.ownCloudDesktop"
  },
  "WPFInstallPaintdotnet": {
    "category": "Multimedia Tools",
    "choco": "paint.net",
    "content": "Paint.NET",
    "description": "Paint.NET is a free image and photo editing software for Windows. It features an intuitive user interface and supports a wide range of powerful editing tools.",
    "link": "https://www.getpaint.net/",
    "winget": "dotPDN.PaintDotNet"
  },
  "WPFInstallparsec": {
    "category": "Utilities",
    "choco": "parsec",
    "content": "Parsec",
    "description": "Parsec is a low-latency, high-quality remote desktop sharing application for collaborating and gaming across devices.",
    "link": "https://parsec.app/",
    "winget": "Parsec.Parsec"
  },
  "WPFInstallpdf24creator": {
    "category": "Document",
    "choco": "pdf24",
    "content": "PDF24 creator",
    "description": "Free and easy-to-use online/desktop PDF tools that make you more productive",
    "link": "https://tools.pdf24.org/en/",
    "winget": "geeksoftwareGmbH.PDF24Creator"
  },
  "WPFInstallpdfsam": {
    "category": "Document",
    "choco": "pdfsam",
    "content": "PDFsam Basic",
    "description": "PDFsam Basic is a free and open-source tool for splitting, merging, and rotating PDF files.",
    "link": "https://pdfsam.org/",
    "winget": "PDFsam.PDFsam"
  },
  "WPFInstallpeazip": {
    "category": "Utilities",
    "choco": "peazip",
    "content": "PeaZip",
    "description": "PeaZip is a free, open-source file archiver utility that supports multiple archive formats and provides encryption features.",
    "link": "https://peazip.github.io/",
    "winget": "Giorgiotani.Peazip"
  },
  "WPFInstallpiimager": {
    "category": "Utilities",
    "choco": "rpi-imager",
    "content": "Raspberry Pi Imager",
    "description": "Raspberry Pi Imager is a utility for writing operating system images to SD cards for Raspberry Pi devices.",
    "link": "https://www.raspberrypi.com/software/",
    "winget": "RaspberryPiFoundation.RaspberryPiImager"
  },
  "WPFInstallplaynite": {
    "category": "Games",
    "choco": "playnite",
    "content": "Playnite",
    "description": "Playnite is an open-source video game library manager with one simple goal: To provide a unified interface for all of your games.",
    "link": "https://playnite.link/",
    "winget": "Playnite.Playnite"
  },
  "WPFInstallplex": {
    "category": "Multimedia Tools",
    "choco": "plexmediaserver",
    "content": "Plex Media Server",
    "description": "Plex Media Server is a media server software that allows you to organize and stream your media library. It supports various media formats and offers a wide range of features.",
    "link": "https://www.plex.tv/your-media/",
    "winget": "Plex.PlexMediaServer"
  },
  "WPFInstallPortmaster": {
    "category": "Pro Tools",
    "choco": "portmaster",
    "content": "Portmaster",
    "description": "Portmaster is a free and open-source application that puts you back in charge over all your computers network connections.",
    "link": "https://safing.io/",
    "winget": "Safing.Portmaster"
  },
  "WPFInstallposh": {
    "category": "Development",
    "choco": "oh-my-posh",
    "content": "Oh My Posh (Prompt)",
    "description": "Oh My Posh is a cross-platform prompt theme engine for any shell.",
    "link": "https://ohmyposh.dev/",
    "winget": "JanDeDobbeleer.OhMyPosh"
  },
  "WPFInstallpostman": {
    "category": "Development",
    "choco": "postman",
    "content": "Postman",
    "description": "Postman is a collaboration platform for API development that simplifies the process of developing APIs.",
    "link": "https://www.postman.com/",
    "winget": "Postman.Postman"
  },
  "WPFInstallpowerautomate": {
    "category": "Microsoft Tools",
    "choco": "powerautomatedesktop",
    "content": "Power Automate",
    "description": "Using Power Automate Desktop you can automate tasks on the desktop as well as the Web.",
    "link": "https://www.microsoft.com/en-us/power-platform/products/power-automate",
    "winget": "Microsoft.PowerAutomateDesktop"
  },
  "WPFInstallpowerbi": {
    "category": "Microsoft Tools",
    "choco": "powerbi",
    "content": "Power BI",
    "description": "Create stunning reports and visualizations with Power BI Desktop. It puts visual analytics at your fingertips with intuitive report authoring. Drag-and-drop to place content exactly where you want it on the flexible and fluid canvas. Quickly discover patterns as you explore a single unified view of linked, interactive visualizations.",
    "link": "https://www.microsoft.com/en-us/power-platform/products/power-bi/",
    "winget": "Microsoft.PowerBI"
  },
  "WPFInstallpowershell": {
    "category": "Microsoft Tools",
    "choco": "powershell-core",
    "content": "PowerShell",
    "description": "PowerShell is a task automation framework and scripting language designed for system administrators, offering powerful command-line capabilities.",
    "link": "https://github.com/PowerShell/PowerShell",
    "winget": "Microsoft.PowerShell"
  },
  "WPFInstallpowertoys": {
    "category": "Microsoft Tools",
    "choco": "powertoys",
    "content": "PowerToys",
    "description": "PowerToys is a set of utilities for power users to enhance productivity, featuring tools like FancyZones, PowerRename, and more.",
    "link": "https://github.com/microsoft/PowerToys",
    "winget": "Microsoft.PowerToys"
  },
  "WPFInstallprismlauncher": {
    "category": "Games",
    "choco": "prismlauncher",
    "content": "Prism Launcher",
    "description": "Prism Launcher is a game launcher and manager designed to provide a clean and intuitive interface for organizing and launching your games.",
    "link": "https://prismlauncher.org/",
    "winget": "PrismLauncher.PrismLauncher"
  },
  "WPFInstallprocesslasso": {
    "category": "Utilities",
    "choco": "plasso",
    "content": "Process Lasso",
    "description": "Process Lasso is a system optimization and automation tool that improves system responsiveness and stability by adjusting process priorities and CPU affinities.",
    "link": "https://bitsum.com/",
    "winget": "BitSum.ProcessLasso"
  },
  "WPFInstallprocessmonitor": {
    "category": "Microsoft Tools",
    "choco": "procexp",
    "content": "SysInternals Process Monitor",
    "description": "SysInternals Process Monitor is an advanced monitoring tool that shows real-time file system, registry, and process/thread activity.",
    "link": "https://docs.microsoft.com/en-us/sysinternals/downloads/procmon",
    "winget": "Microsoft.Sysinternals.ProcessMonitor"
  },
  "WPFInstallprucaslicer": {
    "category": "Utilities",
    "choco": "prusaslicer",
    "content": "PrusaSlicer",
    "description": "PrusaSlicer is a powerful and easy-to-use slicing software for 3D printing with Prusa 3D printers.",
    "link": "https://www.prusa3d.com/prusaslicer/",
    "winget": "Prusa3d.PrusaSlicer"
  },
  "WPFInstallpsremoteplay": {
    "category": "Games",
    "choco": "ps-remote-play",
    "content": "PS Remote Play",
    "description": "PS Remote Play is a free application that allows you to stream games from your PlayStation console to a PC or mobile device.",
    "link": "https://remoteplay.dl.playstation.net/remoteplay/lang/gb/",
    "winget": "PlayStation.PSRemotePlay"
  },
  "WPFInstallputty": {
    "category": "Pro Tools",
    "choco": "putty",
    "content": "PuTTY",
    "description": "PuTTY is a free and open-source terminal emulator, serial console, and network file transfer application. It supports various network protocols such as SSH, Telnet, and SCP.",
    "link": "https://www.chiark.greenend.org.uk/~sgtatham/putty/",
    "winget": "PuTTY.PuTTY"
  },
  "WPFInstallpython3": {
    "category": "Development",
    "choco": "python",
    "content": "Python3",
    "description": "Python is a versatile programming language used for web development, data analysis, artificial intelligence, and more.",
    "link": "https://www.python.org/",
    "winget": "Python.Python.3.12"
  },
  "WPFInstallqbittorrent": {
    "category": "Utilities",
    "choco": "qbittorrent",
    "content": "qBittorrent",
    "description": "qBittorrent is a free and open-source BitTorrent client that aims to provide a feature-rich and lightweight alternative to other torrent clients.",
    "link": "https://www.qbittorrent.org/",
    "winget": "qBittorrent.qBittorrent"
  },
  "WPFInstalltixati": {
    "category": "Utilities",
    "choco": "tixati.portable",
    "content": "Tixati",
    "description": "Tixati is a cross-platform BitTorrent client written in C++ that has been designed to be light on system resources.",
    "link": "https://www.tixati.com/",
    "winget": "Tixati.Tixati.Portable"
  },
  "WPFInstallqtox": {
    "category": "Communications",
    "choco": "qtox",
    "content": "QTox",
    "description": "QTox is a free and open-source messaging app that prioritizes user privacy and security in its design.",
    "link": "https://qtox.github.io/",
    "winget": "Tox.qTox"
  },
  "WPFInstallquicklook": {
    "category": "Utilities",
    "choco": "quicklook",
    "content": "Quicklook",
    "description": "Bring macOS &#8220;Quick Look&#8221; feature to Windows",
    "link": "https://github.com/QL-Win/QuickLook",
    "winget": "QL-Win.QuickLook"
  },
  "WPFInstallrainmeter": {
    "category": "Utilities",
    "choco": "na",
    "content": "Rainmeter",
    "description": "Rainmeter is a desktop customization tool that allows you to create and share customizable skins for your desktop.",
    "link": "https://www.rainmeter.net/",
    "winget": "Rainmeter.Rainmeter"
  },
  "WPFInstallrevo": {
    "category": "Utilities",
    "choco": "revo-uninstaller",
    "content": "Revo Uninstaller",
    "description": "Revo Uninstaller is an advanced uninstaller tool that helps you remove unwanted software and clean up your system.",
    "link": "https://www.revouninstaller.com/",
    "winget": "RevoUninstaller.RevoUninstaller"
  },
  "WPFInstallrevolt": {
    "category": "Communications",
    "choco": "na",
    "content": "Revolt",
    "description": "Find your community, connect with the world. Revolt is one of the best ways to stay connected with your friends and community without sacrificing any usability.",
    "link": "https://revolt.chat/",
    "winget": "Revolt.RevoltDesktop"
  },
  "WPFInstallripgrep": {
    "category": "Utilities",
    "choco": "ripgrep",
    "content": "Ripgrep",
    "description": "Fast and powerful commandline search tool",
    "link": "https://github.com/BurntSushi/ripgrep/",
    "winget": "BurntSushi.ripgrep.MSVC"
  },
  "WPFInstallrufus": {
    "category": "Utilities",
    "choco": "rufus",
    "content": "Rufus Imager",
    "description": "Rufus is a utility that helps format and create bootable USB drives, such as USB keys or pen drives.",
    "link": "https://rufus.ie/",
    "winget": "Rufus.Rufus"
  },
  "WPFInstallrustdesk": {
    "category": "Pro Tools",
    "choco": "rustdesk.portable",
    "content": "RustDesk",
    "description": "RustDesk is a free and open-source remote desktop application. It provides a secure way to connect to remote machines and access desktop environments.",
    "link": "https://rustdesk.com/",
    "winget": "RustDesk.RustDesk"
  },
  "WPFInstallrustlang": {
    "category": "Development",
    "choco": "rust",
    "content": "Rust",
    "description": "Rust is a programming language designed for safety and performance, particularly focused on systems programming.",
    "link": "https://www.rust-lang.org/",
    "winget": "Rustlang.Rust.MSVC"
  },
  "WPFInstallsamsungmagician": {
    "category": "Utilities",
    "choco": "samsung-magician",
    "content": "Samsung Magician",
    "description": "Samsung Magician is a utility for managing and optimizing Samsung SSDs.",
    "link": "https://semiconductor.samsung.com/consumer-storage/magician/",
    "winget": "Samsung.SamsungMagician"
  },
  "WPFInstallsandboxie": {
    "category": "Utilities",
    "choco": "sandboxie",
    "content": "Sandboxie Plus",
    "description": "Sandboxie Plus is a sandbox-based isolation program that provides enhanced security by running applications in an isolated environment.",
    "link": "https://github.com/sandboxie-plus/Sandboxie",
    "winget": "Sandboxie.Plus"
  },
  "WPFInstallsdio": {
    "category": "Utilities",
    "choco": "sdio",
    "content": "Snappy Driver Installer Origin",
    "description": "Snappy Driver Installer Origin is a free and open-source driver updater with a vast driver database for Windows.",
    "link": "https://sourceforge.net/projects/snappy-driver-installer-origin",
    "winget": "GlennDelahoy.SnappyDriverInstallerOrigin"
  },
  "WPFInstallsession": {
    "category": "Communications",
    "choco": "session",
    "content": "Session",
    "description": "Session is a private and secure messaging app built on a decentralized network for user privacy and data protection.",
    "link": "https://getsession.org/",
    "winget": "Oxen.Session"
  },
  "WPFInstallsharex": {
    "category": "Multimedia Tools",
    "choco": "sharex",
    "content": "ShareX (Screenshots)",
    "description": "ShareX is a free and open-source screen capture and file sharing tool. It supports various capture methods and offers advanced features for editing and sharing screenshots.",
    "link": "https://getsharex.com/",
    "winget": "ShareX.ShareX"
  },
  "WPFInstallnilesoftShel": {
    "category": "Utilities",
    "choco": "nilesoft-shell",
    "content": "Shell (Expanded Context Menu)",
    "description": "Shell is an expanded context menu tool that adds extra functionality and customization options to the Windows context menu.",
    "link": "https://nilesoft.org/",
    "winget": "Nilesoft.Shell"
  },
  "WPFInstallsidequest": {
    "category": "Games",
    "choco": "sidequest",
    "content": "SideQuestVR",
    "description": "SideQuestVR is a community-driven platform that enables users to discover, install, and manage virtual reality content on Oculus Quest devices.",
    "link": "https://sidequestvr.com/",
    "winget": "SideQuestVR.SideQuest"
  },
  "WPFInstallsignal": {
    "category": "Communications",
    "choco": "signal",
    "content": "Signal",
    "description": "Signal is a privacy-focused messaging app that offers end-to-end encryption for secure and private communication.",
    "link": "https://signal.org/",
    "winget": "OpenWhisperSystems.Signal"
  },
  "WPFInstallsignalrgb": {
    "category": "Utilities",
    "choco": "na",
    "content": "SignalRGB",
    "description": "SignalRGB lets you control and sync your favorite RGB devices with one free application.",
    "link": "https://www.signalrgb.com/",
    "winget": "WhirlwindFX.SignalRgb"
  },
  "WPFInstallsimplenote": {
    "category": "Document",
    "choco": "simplenote",
    "content": "simplenote",
    "description": "Simplenote is an easy way to keep notes, lists, ideas and more.",
    "link": "https://simplenote.com/",
    "winget": "Automattic.Simplenote"
  },
  "WPFInstallsimplewall": {
    "category": "Pro Tools",
    "choco": "simplewall",
    "content": "Simplewall",
    "description": "Simplewall is a free and open-source firewall application for Windows. It allows users to control and manage the inbound and outbound network traffic of applications.",
    "link": "https://github.com/henrypp/simplewall",
    "winget": "Henry++.simplewall"
  },
  "WPFInstallskype": {
    "category": "Communications",
    "choco": "skype",
    "content": "Skype",
    "description": "Skype is a widely used communication platform offering video calls, voice calls, and instant messaging services.",
    "link": "https://www.skype.com/",
    "winget": "Microsoft.Skype"
  },
  "WPFInstallslack": {
    "category": "Communications",
    "choco": "slack",
    "content": "Slack",
    "description": "Slack is a collaboration hub that connects teams and facilitates communication through channels, messaging, and file sharing.",
    "link": "https://slack.com/",
    "winget": "SlackTechnologies.Slack"
  },
  "WPFInstallspacedrive": {
    "category": "Utilities",
    "choco": "na",
    "content": "Spacedrive File Manager",
    "description": "Spacedrive is a file manager that offers cloud storage integration and file synchronization across devices.",
    "link": "https://www.spacedrive.com/",
    "winget": "spacedrive.Spacedrive"
  },
  "WPFInstallspacesniffer": {
    "category": "Utilities",
    "choco": "spacesniffer",
    "content": "SpaceSniffer",
    "description": "A tool application that lets you understand how folders and files are structured on your disks",
    "link": "http://www.uderzo.it/main_products/space_sniffer/",
    "winget": "UderzoSoftware.SpaceSniffer"
  },
  "WPFInstallstarship": {
    "category": "Development",
    "choco": "starship",
    "content": "Starship (Shell Prompt)",
    "description": "Starship is a minimal, fast, and customizable prompt for any shell.",
    "link": "https://starship.rs/",
    "winget": "starship"
  },
  "WPFInstallstartallback": {
    "category": "Utilities",
    "choco": "na",
    "content": "StartAllBack",
    "description": "StartAllBack is a Tool that can be used to edit the Windows appearance by your liking (Taskbar, Start Menu, File Explorer, Control Panel, Context Menu ...)",
    "link": "https://www.startallback.com/",
    "winget": "startallback"
  },
  "WPFInstallsteam": {
    "category": "Games",
    "choco": "steam-client",
    "content": "Steam",
    "description": "Steam is a digital distribution platform for purchasing and playing video games, offering multiplayer gaming, video streaming, and more.",
    "link": "https://store.steampowered.com/about/",
    "winget": "Valve.Steam"
  },
  "WPFInstallstrawberry": {
    "category": "Multimedia Tools",
    "choco": "strawberrymusicplayer",
    "content": "Strawberry (Music Player)",
    "description": "Strawberry is an open-source music player that focuses on music collection management and audio quality. It supports various audio formats and features a clean user interface.",
    "link": "https://www.strawberrymusicplayer.org/",
    "winget": "StrawberryMusicPlayer.Strawberry"
  },
  "WPFInstallstremio": {
    "winget": "Stremio.Stremio",
    "choco": "stremio",
    "category": "Multimedia Tools",
    "content": "Stremio",
    "link": "https://www.stremio.com/",
    "description": "Stremio is a media center application that allows users to organize and stream their favorite movies, TV shows, and video content."
  },
  "WPFInstallsublimemerge": {
    "category": "Development",
    "choco": "sublimemerge",
    "content": "Sublime Merge",
    "description": "Sublime Merge is a Git client with advanced features and a beautiful interface.",
    "link": "https://www.sublimemerge.com/",
    "winget": "SublimeHQ.SublimeMerge"
  },
  "WPFInstallsublimetext": {
    "category": "Development",
    "choco": "sublimetext4",
    "content": "Sublime Text",
    "description": "Sublime Text is a sophisticated text editor for code, markup, and prose.",
    "link": "https://www.sublimetext.com/",
    "winget": "SublimeHQ.SublimeText.4"
  },
  "WPFInstallsumatra": {
    "category": "Document",
    "choco": "sumatrapdf",
    "content": "Sumatra PDF",
    "description": "Sumatra PDF is a lightweight and fast PDF viewer with minimalistic design.",
    "link": "https://www.sumatrapdfreader.org/free-pdf-reader.html",
    "winget": "SumatraPDF.SumatraPDF"
  },
  "WPFInstallpdfgear": {
    "category": "Document",
    "choco": "na",
    "content": "PDFgear",
    "description": "PDFgear is a piece of full-featured PDF management software for Windows, Mac, and mobile, and it&#39;s completely free to use.",
    "link": "https://www.pdfgear.com/",
    "winget": "PDFgear.PDFgear"
  },
  "WPFInstallsunshine": {
    "category": "Games",
    "choco": "sunshine",
    "content": "Sunshine/GameStream Server",
    "description": "Sunshine is a GameStream server that allows you to remotely play PC games on Android devices, offering low-latency streaming.",
    "link": "https://github.com/LizardByte/Sunshine",
    "winget": "LizardByte.Sunshine"
  },
  "WPFInstallsuperf4": {
    "category": "Utilities",
    "choco": "superf4",
    "content": "SuperF4",
    "description": "SuperF4 is a utility that allows you to terminate programs instantly by pressing a customizable hotkey.",
    "link": "https://stefansundin.github.io/superf4/",
    "winget": "StefanSundin.Superf4"
  },
  "WPFInstallswift": {
    "category": "Development",
    "choco": "na",
    "content": "Swift toolchain",
    "description": "Swift is a general-purpose programming language that&#39;s approachable for newcomers and powerful for experts.",
    "link": "https://www.swift.org/",
    "winget": "Swift.Toolchain"
  },
  "WPFInstallsynctrayzor": {
    "category": "Utilities",
    "choco": "synctrayzor",
    "content": "SyncTrayzor",
    "description": "Windows tray utility / filesystem watcher / launcher for Syncthing",
    "link": "https://github.com/canton7/SyncTrayzor/",
    "winget": "SyncTrayzor.SyncTrayzor"
  },
  "WPFInstallsqlmanagementstudio": {
    "category": "Microsoft Tools",
    "choco": "sql-server-management-studio",
    "content": "Microsoft SQL Server Management Studio",
    "description": "SQL Server Management Studio (SSMS) is an integrated environment for managing any SQL infrastructure, from SQL Server to Azure SQL Database. SSMS provides tools to configure, monitor, and administer instances of SQL Server and databases.",
    "link": "https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms?view=sql-server-ver16",
    "winget": "Microsoft.SQLServerManagementStudio"
  },
  "WPFInstalltabby": {
    "category": "Utilities",
    "choco": "tabby",
    "content": "Tabby.sh",
    "description": "Tabby is a highly configurable terminal emulator, SSH and serial client for Windows, macOS and Linux",
    "link": "https://tabby.sh/",
    "winget": "Eugeny.Tabby"
  },
  "WPFInstalltailscale": {
    "category": "Utilities",
    "choco": "tailscale",
    "content": "Tailscale",
    "description": "Tailscale is a secure and easy-to-use VPN solution for connecting your devices and networks.",
    "link": "https://tailscale.com/",
    "winget": "tailscale.tailscale"
  },
  "WPFInstallTcNoAccSwitcher": {
    "category": "Games",
    "choco": "tcno-acc-switcher",
    "content": "TCNO Account Switcher",
    "description": "A Super-fast account switcher for Steam, Battle.net, Epic Games, Origin, Riot, Ubisoft and many others!",
    "link": "https://github.com/TCNOco/TcNo-Acc-Switcher",
    "winget": "TechNobo.TcNoAccountSwitcher"
  },
  "WPFInstalltcpview": {
    "category": "Microsoft Tools",
    "choco": "tcpview",
    "content": "SysInternals TCPView",
    "description": "SysInternals TCPView is a network monitoring tool that displays a detailed list of all TCP and UDP endpoints on your system.",
    "link": "https://docs.microsoft.com/en-us/sysinternals/downloads/tcpview",
    "winget": "Microsoft.Sysinternals.TCPView"
  },
  "WPFInstallteams": {
    "category": "Communications",
    "choco": "microsoft-teams",
    "content": "Teams",
    "description": "Microsoft Teams is a collaboration platform that integrates with Office 365 and offers chat, video conferencing, file sharing, and more.",
    "link": "https://www.microsoft.com/en-us/microsoft-teams/group-chat-software",
    "winget": "Microsoft.Teams"
  },
  "WPFInstallteamviewer": {
    "category": "Utilities",
    "choco": "teamviewer9",
    "content": "TeamViewer",
    "description": "TeamViewer is a popular remote access and support software that allows you to connect to and control remote devices.",
    "link": "https://www.teamviewer.com/",
    "winget": "TeamViewer.TeamViewer"
  },
  "WPFInstalltelegram": {
    "category": "Communications",
    "choco": "telegram",
    "content": "Telegram",
    "description": "Telegram is a cloud-based instant messaging app known for its security features, speed, and simplicity.",
    "link": "https://telegram.org/",
    "winget": "Telegram.TelegramDesktop"
  },
  "WPFInstallunigram": {
    "category": "Communications",
    "choco": "na",
    "content": "Unigram",
    "description": "Unigram - Telegram for Windows",
    "link": "https://unigramdev.github.io/",
    "winget": "Telegram.Unigram"
  },
  "WPFInstallterminal": {
    "category": "Microsoft Tools",
    "choco": "microsoft-windows-terminal",
    "content": "Windows Terminal",
    "description": "Windows Terminal is a modern, fast, and efficient terminal application for command-line users, supporting multiple tabs, panes, and more.",
    "link": "https://aka.ms/terminal",
    "winget": "Microsoft.WindowsTerminal"
  },
  "WPFInstallThonny": {
    "category": "Development",
    "choco": "thonny",
    "content": "Thonny Python IDE",
    "description": "Python IDE for beginners.",
    "link": "https://github.com/thonny/thonny",
    "winget": "AivarAnnamaa.Thonny"
  },
  "WPFInstallthorium": {
    "category": "Browsers",
    "choco": "na",
    "content": "Thorium Browser AVX2",
    "description": "Browser built for speed over vanilla chromium. It is built with AVX2 optimizations and is the fastest browser on the market.",
    "link": "http://thorium.rocks/",
    "winget": "Alex313031.Thorium.AVX2"
  },
  "WPFInstallthunderbird": {
    "category": "Communications",
    "choco": "thunderbird",
    "content": "Thunderbird",
    "description": "Mozilla Thunderbird is a free and open-source email client, news client, and chat client with advanced features.",
    "link": "https://www.thunderbird.net/",
    "winget": "Mozilla.Thunderbird"
  },
  "WPFInstalltidal": {
    "category": "Multimedia Tools",
    "choco": "na",
    "content": "Tidal",
    "description": "Tidal is a music streaming service known for its high-fidelity audio quality and exclusive content. It offers a vast library of songs and curated playlists.",
    "link": "https://tidal.com/",
    "winget": "9NNCB5BS59PH"
  },
  "WPFInstalltor": {
    "category": "Browsers",
    "choco": "tor-browser",
    "content": "Tor Browser",
    "description": "Tor Browser is designed for anonymous web browsing, utilizing the Tor network to protect user privacy and security.",
    "link": "https://www.torproject.org/",
    "winget": "TorProject.TorBrowser"
  },
  "WPFInstalltotalcommander": {
    "category": "Utilities",
    "choco": "TotalCommander",
    "content": "Total Commander",
    "description": "Total Commander is a file manager for Windows that provides a powerful and intuitive interface for file management.",
    "link": "https://www.ghisler.com/",
    "winget": "Ghisler.TotalCommander"
  },
  "WPFInstalltreesize": {
    "category": "Utilities",
    "choco": "treesizefree",
    "content": "TreeSize Free",
    "description": "TreeSize Free is a disk space manager that helps you analyze and visualize the space usage on your drives.",
    "link": "https://www.jam-software.com/treesize_free/",
    "winget": "JAMSoftware.TreeSize.Free"
  },
  "WPFInstallttaskbar": {
    "category": "Utilities",
    "choco": "translucenttb",
    "content": "Translucent Taskbar",
    "description": "Translucent Taskbar is a tool that allows you to customize the transparency of the Windows taskbar.",
    "link": "https://github.com/TranslucentTB/TranslucentTB",
    "winget": "9PF4KZ2VN4W9"
  },
  "WPFInstalltwinkletray": {
    "category": "Utilities",
    "choco": "twinkle-tray",
    "content": "Twinkle Tray",
    "description": "Twinkle Tray lets you easily manage the brightness levels of multiple monitors.",
    "link": "https://twinkletray.com/",
    "winget": "xanderfrangos.twinkletray"
  },
  "WPFInstallubisoft": {
    "category": "Games",
    "choco": "ubisoft-connect",
    "content": "Ubisoft Connect",
    "description": "Ubisoft Connect is Ubisoft&#39;s digital distribution and online gaming service, providing access to Ubisoft&#39;s games and services.",
    "link": "https://ubisoftconnect.com/",
    "winget": "Ubisoft.Connect"
  },
  "WPFInstallungoogled": {
    "category": "Browsers",
    "choco": "ungoogled-chromium",
    "content": "Ungoogled",
    "description": "Ungoogled Chromium is a version of Chromium without Google&#39;s integration for enhanced privacy and control.",
    "link": "https://github.com/Eloston/ungoogled-chromium",
    "winget": "eloston.ungoogled-chromium"
  },
  "WPFInstallunity": {
    "category": "Development",
    "choco": "unityhub",
    "content": "Unity Game Engine",
    "description": "Unity is a powerful game development platform for creating 2D, 3D, augmented reality, and virtual reality games.",
    "link": "https://unity.com/",
    "winget": "Unity.UnityHub"
  },
  "WPFInstallvagrant": {
    "category": "Development",
    "choco": "vagrant",
    "content": "Vagrant",
    "description": "Vagrant is an open-source tool for building and managing virtualized development environments.",
    "link": "https://www.vagrantup.com/",
    "winget": "Hashicorp.Vagrant"
  },
  "WPFInstallvc2015_32": {
    "category": "Microsoft Tools",
    "choco": "na",
    "content": "Visual C++ 2015-2022 32-bit",
    "description": "Visual C++ 2015-2022 32-bit redistributable package installs runtime components of Visual C++ libraries required to run 32-bit applications.",
    "link": "https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads",
    "winget": "Microsoft.VCRedist.2015+.x86"
  },
  "WPFInstallvc2015_64": {
    "category": "Microsoft Tools",
    "choco": "na",
    "content": "Visual C++ 2015-2022 64-bit",
    "description": "Visual C++ 2015-2022 64-bit redistributable package installs runtime components of Visual C++ libraries required to run 64-bit applications.",
    "link": "https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads",
    "winget": "Microsoft.VCRedist.2015+.x64"
  },
  "WPFInstallvencord": {
    "category": "Communications",
    "choco": "na",
    "content": "Vencord",
    "description": "Vencord is a modification for Discord that adds plugins, custom styles, and more!",
    "link": "https://vencord.dev/",
    "winget": "Vendicated.Vencord"
  },
  "WPFInstallventoy": {
    "category": "Pro Tools",
    "choco": "ventoy",
    "content": "Ventoy",
    "description": "Ventoy is an open-source tool for creating bootable USB drives. It supports multiple ISO files on a single USB drive, making it a versatile solution for installing operating systems.",
    "link": "https://www.ventoy.net/",
    "winget": "Ventoy.Ventoy"
  },
  "WPFInstallvesktop": {
    "category": "Communications",
    "choco": "na",
    "content": "Vesktop",
    "description": "A cross platform electron-based desktop app aiming to give you a snappier Discord experience with Vencord pre-installed.",
    "link": "https://github.com/Vencord/Vesktop",
    "winget": "Vencord.Vesktop"
  },
  "WPFInstallviber": {
    "category": "Communications",
    "choco": "viber",
    "content": "Viber",
    "description": "Viber is a free messaging and calling app with features like group chats, video calls, and more.",
    "link": "https://www.viber.com/",
    "winget": "Viber.Viber"
  },
  "WPFInstallvideomass": {
    "category": "Multimedia Tools",
    "choco": "na",
    "content": "Videomass",
    "description": "Videomass by GianlucaPernigotto is a cross-platform GUI for FFmpeg, streamlining multimedia file processing with batch conversions and user-friendly features.",
    "link": "https://jeanslack.github.io/Videomass/",
    "winget": "GianlucaPernigotto.Videomass"
  },
  "WPFInstallvisualstudio": {
    "category": "Development",
    "choco": "visualstudio2022community",
    "content": "Visual Studio 2022",
    "description": "Visual Studio 2022 is an integrated development environment (IDE) for building, debugging, and deploying applications.",
    "link": "https://visualstudio.microsoft.com/",
    "winget": "Microsoft.VisualStudio.2022.Community"
  },
  "WPFInstallvivaldi": {
    "category": "Browsers",
    "choco": "vivaldi",
    "content": "Vivaldi",
    "description": "Vivaldi is a highly customizable web browser with a focus on user personalization and productivity features.",
    "link": "https://vivaldi.com/",
    "winget": "VivaldiTechnologies.Vivaldi"
  },
  "WPFInstallvlc": {
    "category": "Multimedia Tools",
    "choco": "vlc",
    "content": "VLC (Video Player)",
    "description": "VLC Media Player is a free and open-source multimedia player that supports a wide range of audio and video formats. It is known for its versatility and cross-platform compatibility.",
    "link": "https://www.videolan.org/vlc/",
    "winget": "VideoLAN.VLC"
  },
  "WPFInstallvoicemeeter": {
    "category": "Multimedia Tools",
    "choco": "voicemeeter",
    "content": "Voicemeeter (Audio)",
    "description": "Voicemeeter is a virtual audio mixer that allows you to manage and enhance audio streams on your computer. It is commonly used for audio recording and streaming purposes.",
    "link": "https://www.vb-audio.com/Voicemeeter/",
    "winget": "VB-Audio.Voicemeeter"
  },
  "WPFInstallvrdesktopstreamer": {
    "category": "Games",
    "choco": "na",
    "content": "Virtual Desktop Streamer",
    "description": "Virtual Desktop Streamer is a tool that allows you to stream your desktop screen to VR devices.",
    "link": "https://www.vrdesktop.net/",
    "winget": "VirtualDesktop.Streamer"
  },
  "WPFInstallvscode": {
    "category": "Development",
    "choco": "vscode",
    "content": "VS Code",
    "description": "Visual Studio Code is a free, open-source code editor with support for multiple programming languages.",
    "link": "https://code.visualstudio.com/",
    "winget": "Git.Git;Microsoft.VisualStudioCode"
  },
  "WPFInstallvscodium": {
    "category": "Development",
    "choco": "vscodium",
    "content": "VS Codium",
    "description": "VSCodium is a community-driven, freely-licensed binary distribution of Microsoft&#39;s VS Code.",
    "link": "https://vscodium.com/",
    "winget": "Git.Git;VSCodium.VSCodium"
  },
  "WPFInstallwaterfox": {
    "category": "Browsers",
    "choco": "waterfox",
    "content": "Waterfox",
    "description": "Waterfox is a fast, privacy-focused web browser based on Firefox, designed to preserve user choice and privacy.",
    "link": "https://www.waterfox.net/",
    "winget": "Waterfox.Waterfox"
  },
  "WPFInstallwezterm": {
    "category": "Development",
    "choco": "wezterm",
    "content": "Wezterm",
    "description": "WezTerm is a powerful cross-platform terminal emulator and multiplexer",
    "link": "https://wezfurlong.org/wezterm/index.html",
    "winget": "wez.wezterm"
  },
  "WPFInstallwhatsapp": {
    "category": "Communications",
    "choco": "whatsapp",
    "content": "Whatsapp",
    "description": "WhatsApp Desktop is a desktop version of the popular messaging app, allowing users to send and receive messages, share files, and connect with contacts from their computer.",
    "link": "https://www.whatsapp.com/",
    "winget": "WhatsApp.WhatsApp"
  },
  "WPFInstallwindirstat": {
    "category": "Utilities",
    "choco": "windirstat",
    "content": "WinDirStat",
    "description": "WinDirStat is a disk usage statistics viewer and cleanup tool for Windows.",
    "link": "https://windirstat.net/",
    "winget": "WinDirStat.WinDirStat"
  },
  "WPFInstallwindowspchealth": {
    "category": "Utilities",
    "choco": "na",
    "content": "Windows PC Health Check",
    "description": "Windows PC Health Check is a tool that helps you check if your PC meets the system requirements for Windows 11.",
    "link": "https://support.microsoft.com/en-us/windows/how-to-use-the-pc-health-check-app-9c8abd9b-03ba-4e67-81ef-36f37caa7844",
    "winget": "Microsoft.WindowsPCHealthCheck"
  },
  "WPFInstallwingetui": {
    "category": "Utilities",
    "choco": "wingetui",
    "content": "WingetUI",
    "description": "WingetUI is a graphical user interface for Microsoft&#39;s Windows Package Manager (winget).",
    "link": "https://www.marticliment.com/wingetui/",
    "winget": "SomePythonThings.WingetUIStore"
  },
  "WPFInstallwinmerge": {
    "category": "Document",
    "choco": "winmerge",
    "content": "WinMerge",
    "description": "WinMerge is a visual text file and directory comparison tool for Windows.",
    "link": "https://winmerge.org/",
    "winget": "WinMerge.WinMerge"
  },
  "WPFInstallwinpaletter": {
    "category": "Utilities",
    "choco": "WinPaletter",
    "content": "WinPaletter",
    "description": "WinPaletter is a tool for adjusting the color palette of Windows 10, providing customization options for window colors.",
    "link": "https://github.com/Abdelrhman-AK/WinPaletter",
    "winget": "Abdelrhman-AK.WinPaletter"
  },
  "WPFInstallwinrar": {
    "category": "Utilities",
    "choco": "winrar",
    "content": "WinRAR",
    "description": "WinRAR is a powerful archive manager that allows you to create, manage, and extract compressed files.",
    "link": "https://www.win-rar.com/",
    "winget": "RARLab.WinRAR"
  },
  "WPFInstallwinscp": {
    "category": "Pro Tools",
    "choco": "winscp",
    "content": "WinSCP",
    "description": "WinSCP is a popular open-source SFTP, FTP, and SCP client for Windows. It allows secure file transfers between a local and a remote computer.",
    "link": "https://winscp.net/",
    "winget": "WinSCP.WinSCP"
  },
  "WPFInstallwireguard": {
    "category": "Pro Tools",
    "choco": "wireguard",
    "content": "WireGuard",
    "description": "WireGuard is a fast and modern VPN (Virtual Private Network) protocol. It aims to be simpler and more efficient than other VPN protocols, providing secure and reliable connections.",
    "link": "https://www.wireguard.com/",
    "winget": "WireGuard.WireGuard"
  },
  "WPFInstallwireshark": {
    "category": "Pro Tools",
    "choco": "wireshark",
    "content": "Wireshark",
    "description": "Wireshark is a widely-used open-source network protocol analyzer. It allows users to capture and analyze network traffic in real-time, providing detailed insights into network activities.",
    "link": "https://www.wireshark.org/",
    "winget": "WiresharkFoundation.Wireshark"
  },
  "WPFInstallwisetoys": {
    "category": "Utilities",
    "choco": "na",
    "content": "WiseToys",
    "description": "WiseToys is a set of utilities and tools designed to enhance and optimize your Windows experience.",
    "link": "https://toys.wisecleaner.com/",
    "winget": "WiseCleaner.WiseToys"
  },
  "WPFInstallwizfile": {
    "category": "Utilities",
    "choco": "na",
    "content": "WizFile",
    "description": "Find files by name on your hard drives almost instantly.",
    "link": "https://antibody-software.com/wizfile/",
    "winget": "AntibodySoftware.WizFile"
  },
  "WPFInstallwiztree": {
    "category": "Utilities",
    "choco": "wiztree",
    "content": "WizTree",
    "description": "WizTree is a fast disk space analyzer that helps you quickly find the files and folders consuming the most space on your hard drive.",
    "link": "https://wiztreefree.com/",
    "winget": "AntibodySoftware.WizTree"
  },
  "WPFInstallxdm": {
    "category": "Utilities",
    "choco": "xdm",
    "content": "Xtreme Download Manager",
    "description": "Xtreme Download Manager is an advanced download manager with support for various protocols and browsers.*Browser integration deprecated by google store. No official release.*",
    "link": "https://xtremedownloadmanager.com/",
    "winget": "subhra74.XtremeDownloadManager"
  },
  "WPFInstallxeheditor": {
    "category": "Utilities",
    "choco": "HxD",
    "content": "HxD Hex Editor",
    "description": "HxD is a free hex editor that allows you to edit, view, search, and analyze binary files.",
    "link": "https://mh-nexus.de/en/hxd/",
    "winget": "MHNexus.HxD"
  },
  "WPFInstallxemu": {
    "category": "Games",
    "choco": "na",
    "content": "XEMU",
    "description": "XEMU is an open-source Xbox emulator that allows you to play Xbox games on your PC, aiming for accuracy and compatibility.",
    "link": "https://xemu.app/",
    "winget": "xemu-project.xemu"
  },
  "WPFInstallxnview": {
    "category": "Utilities",
    "choco": "xnview",
    "content": "XnView classic",
    "description": "XnView is an efficient image viewer, browser and converter for Windows.",
    "link": "https://www.xnview.com/en/xnview/",
    "winget": "XnSoft.XnView.Classic"
  },
  "WPFInstallxournal": {
    "category": "Document",
    "choco": "xournalplusplus",
    "content": "Xournal++",
    "description": "Xournal++ is an open-source handwriting notetaking software with PDF annotation capabilities.",
    "link": "https://xournalpp.github.io/",
    "winget": "Xournal++.Xournal++"
  },
  "WPFInstallxpipe": {
    "category": "Pro Tools",
    "choco": "xpipe",
    "content": "XPipe",
    "description": "XPipe is an open-source tool for orchestrating containerized applications. It simplifies the deployment and management of containerized services in a distributed environment.",
    "link": "https://xpipe.io/",
    "winget": "xpipe-io.xpipe"
  },
  "WPFInstallyarn": {
    "category": "Development",
    "choco": "yarn",
    "content": "Yarn",
    "description": "Yarn is a fast, reliable, and secure dependency management tool for JavaScript projects.",
    "link": "https://yarnpkg.com/",
    "winget": "Yarn.Yarn"
  },
  "WPFInstallytdlp": {
    "category": "Multimedia Tools",
    "choco": "yt-dlp",
    "content": "Yt-dlp",
    "description": "Command-line tool that allows you to download videos from YouTube and other supported sites. It is an improved version of the popular youtube-dl.",
    "link": "https://github.com/yt-dlp/yt-dlp",
    "winget": "yt-dlp.yt-dlp"
  },
  "WPFInstallzerotierone": {
    "category": "Utilities",
    "choco": "zerotier-one",
    "content": "ZeroTier One",
    "description": "ZeroTier One is a software-defined networking tool that allows you to create secure and scalable networks.",
    "link": "https://zerotier.com/",
    "winget": "ZeroTier.ZeroTierOne"
  },
  "WPFInstallzim": {
    "category": "Document",
    "choco": "zim",
    "content": "Zim Desktop Wiki",
    "description": "Zim Desktop Wiki is a graphical text editor used to maintain a collection of wiki pages.",
    "link": "https://zim-wiki.org/",
    "winget": "Zimwiki.Zim"
  },
  "WPFInstallznote": {
    "category": "Document",
    "choco": "na",
    "content": "Znote",
    "description": "Znote is a note-taking application.",
    "link": "https://znote.io/",
    "winget": "alagrede.znote"
  },
  "WPFInstallzoom": {
    "category": "Communications",
    "choco": "zoom",
    "content": "Zoom",
    "description": "Zoom is a popular video conferencing and web conferencing service for online meetings, webinars, and collaborative projects.",
    "link": "https://zoom.us/",
    "winget": "Zoom.Zoom"
  },
  "WPFInstallzotero": {
    "category": "Document",
    "choco": "zotero",
    "content": "Zotero",
    "description": "Zotero is a free, easy-to-use tool to help you collect, organize, cite, and share your research materials.",
    "link": "https://www.zotero.org/",
    "winget": "DigitalScholar.Zotero"
  },
  "WPFInstallzoxide": {
    "category": "Utilities",
    "choco": "zoxide",
    "content": "Zoxide",
    "description": "Zoxide is a fast and efficient directory changer (cd) that helps you navigate your file system with ease.",
    "link": "https://github.com/ajeetdsouza/zoxide",
    "winget": "ajeetdsouza.zoxide"
  },
  "WPFInstallzulip": {
    "category": "Communications",
    "choco": "zulip",
    "content": "Zulip",
    "description": "Zulip is an open-source team collaboration tool with chat streams for productive and organized communication.",
    "link": "https://zulipchat.com/",
    "winget": "Zulip.Zulip"
  },
  "WPFInstallsyncthingtray": {
    "category": "Utilities",
    "choco": "syncthingtray",
    "content": "Syncthingtray",
    "description": "Might be the alternative for Synctrayzor. Windows tray utility / filesystem watcher / launcher for Syncthing",
    "link": "https://github.com/Martchus/syncthingtray",
    "winget": "Martchus.syncthingtray"
  },
  "WPFInstallminiconda": {
    "category": "Development",
    "choco": "miniconda3",
    "content": "Miniconda",
    "description": "Miniconda is a free minimal installer for conda. It is a small bootstrap version of Anaconda that includes only conda, Python, the packages they both depend on, and a small number of other useful packages (like pip, zlib, and a few others).",
    "link": "https://docs.conda.io/projects/miniconda",
    "winget": "Anaconda.Miniconda3"
  },
  "WPFInstalltemurin": {
    "category": "Development",
    "choco": "temurin",
    "content": "Eclipse Temurin",
    "description": "Eclipse Temurin is the open source Java SE build based upon OpenJDK.",
    "link": "https://adoptium.net/temurin/",
    "winget": "EclipseAdoptium.Temurin.21.JDK"
  },
  "WPFInstallintelpresentmon": {
    "category": "Utilities",
    "choco": "na",
    "content": "Intel-PresentMon",
    "description": "A new gaming performance overlay and telemetry application to monitor and measure your gaming experience.",
    "link": "https://game.intel.com/us/stories/intel-presentmon/",
    "winget": "Intel.PresentMon.Beta"
  },
  "WPFInstallpyenvwin": {
    "category": "Development",
    "choco": "pyenv-win",
    "content": "Python Version Manager (pyenv-win)",
    "description": "pyenv for Windows is a simple python version management tool. It lets you easily switch between multiple versions of Python.",
    "link": "https://pyenv-win.github.io/pyenv-win/",
    "winget": "na"
  },
  "WPFInstalltightvnc": {
    "category": "Utilities",
    "choco": "TightVNC",
    "content": "TightVNC",
    "description": "TightVNC is a free and Open Source remote desktop software that lets you access and control a computer over the network. With its intuitive interface, you can interact with the remote screen as if you were sitting in front of it. You can open files, launch applications, and perform other actions on the remote desktop almost as if you were physically there",
    "link": "https://www.tightvnc.com/",
    "winget": "GlavSoft.TightVNC"
  },
  "WPFInstallultravnc": {
    "category": "Utilities",
    "choco": "ultravnc",
    "content": "UltraVNC",
    "description": "UltraVNC is a powerful, easy to use and free - remote pc access softwares - that can display the screen of another computer (via internet or network) on your own screen. The program allows you to use your mouse and keyboard to control the other PC remotely. It means that you can work on a remote computer, as if you were sitting in front of it, right from your current location.",
    "link": "https://uvnc.com/",
    "winget": "uvncbvba.UltraVnc"
  },
  "WPFInstallwindowsfirewallcontrol": {
    "category": "Utilities",
    "choco": "windowsfirewallcontrol",
    "content": "Windows Firewall Control",
    "description": "Windows Firewall Control is a powerful tool which extends the functionality of Windows Firewall and provides new extra features which makes Windows Firewall better.",
    "link": "https://www.binisoft.org/wfc",
    "winget": "BiniSoft.WindowsFirewallControl"
  },
  "WPFInstallvistaswitcher": {
    "category": "Utilities",
    "choco": "na",
    "content": "VistaSwitcher",
    "description": "VistaSwitcher makes it easier for you to locate windows and switch focus, even on multi-monitor systems. The switcher window consists of an easy-to-read list of all tasks running with clearly shown titles and a full-sized preview of the selected task.",
    "link": "https://www.ntwind.com/freeware/vistaswitcher.html",
    "winget": "ntwind.VistaSwitcher"
  },
  "WPFInstallautodarkmode": {
    "category": "Utilities",
    "choco": "auto-dark-mode",
    "content": "Windows Auto Dark Mode",
    "description": "Automatically switches between the dark and light theme of Windows 10 and Windows 11",
    "link": "https://github.com/AutoDarkMode/Windows-Auto-Night-Mode",
    "winget": "Armin2208.WindowsAutoNightMode"
  },
  "WPFInstallmagicwormhole": {
    "category": "Utilities",
    "choco": "magic-wormhole",
    "content": "Magic Wormhole",
    "description": "get things from one computer to another, safely",
    "link": "https://github.com/magic-wormhole/magic-wormhole",
    "winget": "magic-wormhole.magic-wormhole"
  }
}' | convertfrom-json
$sync.configs.dns = '{
  "Google": {
    "Primary": "8.8.8.8",
    "Secondary": "8.8.4.4"
  },
  "Cloudflare": {
    "Primary": "1.1.1.1",
    "Secondary": "1.0.0.1"
  },
  "Cloudflare_Malware": {
    "Primary": "1.1.1.2",
    "Secondary": "1.0.0.2"
  },
  "Cloudflare_Malware_Adult": {
    "Primary": "1.1.1.3",
    "Secondary": "1.0.0.3"
  },
  "Level3": {
    "Primary": "4.2.2.2",
    "Secondary": "4.2.2.1"
  },
  "Open_DNS": {
    "Primary": "208.67.222.222",
    "Secondary": "208.67.220.220"
  },
  "Quad9": {
    "Primary": "9.9.9.9",
    "Secondary": "149.112.112.112"
  }
}' | convertfrom-json
$sync.configs.feature = '{
  "WPFFeaturesdotnet": {
    "Content": "All .Net Framework (2,3,4)",
    "Description": ".NET and .NET Framework is a developer platform made up of tools, programming languages, and libraries for building many different types of applications.",
    "category": "Features",
    "panel": "1",
    "Order": "a010_",
    "feature": [
      "NetFx4-AdvSrvs",
      "NetFx3"
    ],
    "InvokeScript": []
  },
  "WPFFeatureshyperv": {
    "Content": "HyperV Virtualization",
    "Description": "Hyper-V is a hardware virtualization product developed by Microsoft that allows users to create and manage virtual machines.",
    "category": "Features",
    "panel": "1",
    "Order": "a011_",
    "feature": [
      "HypervisorPlatform",
      "Microsoft-Hyper-V-All",
      "Microsoft-Hyper-V",
      "Microsoft-Hyper-V-Tools-All",
      "Microsoft-Hyper-V-Management-PowerShell",
      "Microsoft-Hyper-V-Hypervisor",
      "Microsoft-Hyper-V-Services",
      "Microsoft-Hyper-V-Management-Clients"
    ],
    "InvokeScript": [
      "Start-Process -FilePath cmd.exe -ArgumentList ''/c bcdedit /set hypervisorschedulertype classic'' -Wait"
    ]
  },
  "WPFFeatureslegacymedia": {
    "Content": "Legacy Media (WMP, DirectPlay)",
    "Description": "Enables legacy programs from previous versions of windows",
    "category": "Features",
    "panel": "1",
    "Order": "a012_",
    "feature": [
      "WindowsMediaPlayer",
      "MediaPlayback",
      "DirectPlay",
      "LegacyComponents"
    ],
    "InvokeScript": []
  },
  "WPFFeaturewsl": {
    "Content": "Windows Subsystem for Linux",
    "Description": "Windows Subsystem for Linux is an optional feature of Windows that allows Linux programs to run natively on Windows without the need for a separate virtual machine or dual booting.",
    "category": "Features",
    "panel": "1",
    "Order": "a020_",
    "feature": [
      "VirtualMachinePlatform",
      "Microsoft-Windows-Subsystem-Linux"
    ],
    "InvokeScript": []
  },
  "WPFFeaturenfs": {
    "Content": "NFS - Network File System",
    "Description": "Network File System (NFS) is a mechanism for storing files on a network.",
    "category": "Features",
    "panel": "1",
    "Order": "a014_",
    "feature": [
      "ServicesForNFS-ClientOnly",
      "ClientForNFS-Infrastructure",
      "NFS-Administration"
    ],
    "InvokeScript": [
      "nfsadmin client stop",
      "Set-ItemProperty -Path ''HKLM:\\SOFTWARE\\Microsoft\\ClientForNFS\\CurrentVersion\\Default'' -Name ''AnonymousUID'' -Type DWord -Value 0",
      "Set-ItemProperty -Path ''HKLM:\\SOFTWARE\\Microsoft\\ClientForNFS\\CurrentVersion\\Default'' -Name ''AnonymousGID'' -Type DWord -Value 0",
      "nfsadmin client start",
      "nfsadmin client localhost config fileaccess=755 SecFlavors=+sys -krb5 -krb5i"
    ]
  },
  "WPFFeatureEnableSearchSuggestions": {
    "Content": "Enable Search Box Web Suggestions in Registry(explorer restart)",
    "Description": "Enables web suggestions when searching using Windows Search.",
    "category": "Features",
    "panel": "1",
    "Order": "a015_",
    "feature": [],
    "InvokeScript": [
      "
      If (!(Test-Path ''HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer'')) {
            New-Item -Path ''HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer'' -Force | Out-Null
      }
      New-ItemProperty -Path ''HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer'' -Name ''DisableSearchBoxSuggestions'' -Type DWord -Value 0 -Force
      Stop-Process -name explorer -force
      "
    ]
  },
  "WPFFeatureDisableSearchSuggestions": {
    "Content": "Disable Search Box Web Suggestions in Registry(explorer restart)",
    "Description": "Disables web suggestions when searching using Windows Search.",
    "category": "Features",
    "panel": "1",
    "Order": "a016_",
    "feature": [],
    "InvokeScript": [
      "
      If (!(Test-Path ''HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer'')) {
            New-Item -Path ''HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer'' -Force | Out-Null
      }
      New-ItemProperty -Path ''HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer'' -Name ''DisableSearchBoxSuggestions'' -Type DWord -Value 1 -Force
      Stop-Process -name explorer -force
      "
    ]
  },
  "WPFFeatureRegBackup": {
    "Content": "Enable Daily Registry Backup Task 12.30am",
    "Description": "Enables daily registry backup, previously disabled by Microsoft in Windows 10 1803.",
    "category": "Features",
    "panel": "1",
    "Order": "a017_",
    "feature": [],
    "InvokeScript": [
      "
      New-ItemProperty -Path ''HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager'' -Name ''EnablePeriodicBackup'' -Type DWord -Value 1 -Force
      New-ItemProperty -Path ''HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager'' -Name ''BackupCount'' -Type DWord -Value 2 -Force
      $action = New-ScheduledTaskAction -Execute ''schtasks'' -Argument ''/run /i /tn \"\\Microsoft\\Windows\\Registry\\RegIdleBackup\"''
      $trigger = New-ScheduledTaskTrigger -Daily -At 00:30
      Register-ScheduledTask -Action $action -Trigger $trigger -TaskName ''AutoRegBackup'' -Description ''Create System Registry Backups'' -User ''System''
      "
    ]
  },
  "WPFFeatureEnableLegacyRecovery": {
    "Content": "Enable Legacy F8 Boot Recovery",
    "Description": "Enables Advanced Boot Options screen that lets you start Windows in advanced troubleshooting modes.",
    "category": "Features",
    "panel": "1",
    "Order": "a018_",
    "feature": [],
    "InvokeScript": [
      "
      If (!(Test-Path ''HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager\\LastKnownGood'')) {
            New-Item -Path ''HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager\\LastKnownGood'' -Force | Out-Null
      }
      New-ItemProperty -Path ''HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager\\LastKnownGood'' -Name ''Enabled'' -Type DWord -Value 1 -Force
      Start-Process -FilePath cmd.exe -ArgumentList ''/c bcdedit /Set {Current} BootMenuPolicy Legacy'' -Wait
      "
    ]
  },
  "WPFFeatureDisableLegacyRecovery": {
    "Content": "Disable Legacy F8 Boot Recovery",
    "Description": "Disables Advanced Boot Options screen that lets you start Windows in advanced troubleshooting modes.",
    "category": "Features",
    "panel": "1",
    "Order": "a019_",
    "feature": [],
    "InvokeScript": [
      "
      If (!(Test-Path ''HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager\\LastKnownGood'')) {
            New-Item -Path ''HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager\\LastKnownGood'' -Force | Out-Null
      }
      New-ItemProperty -Path ''HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Configuration Manager\\LastKnownGood'' -Name ''Enabled'' -Type DWord -Value 0 -Force
      Start-Process -FilePath cmd.exe -ArgumentList ''/c bcdedit /Set {Current} BootMenuPolicy Standard'' -Wait
      "
    ]
  },
  "WPFFeaturesandbox": {
    "Content": "Windows Sandbox",
    "category": "Features",
    "panel": "1",
    "Order": "a021_",
    "Description": "Windows Sandbox is a lightweight virtual machine that provides a temporary desktop environment to safely run applications and programs in isolation."
  },
  "WPFFeatureInstall": {
    "Content": "Install Features",
    "category": "Features",
    "panel": "1",
    "Order": "a060_",
    "Type": "150"
  },
  "WPFPanelAutologin": {
    "Content": "Set Up Autologin",
    "category": "Fixes",
    "Order": "a040_",
    "panel": "1",
    "Type": "300"
  },
  "WPFFixesUpdate": {
    "Content": "Reset Windows Update",
    "category": "Fixes",
    "panel": "1",
    "Order": "a041_",
    "Type": "300"
  },
  "WPFFixesNetwork": {
    "Content": "Reset Network",
    "category": "Fixes",
    "Order": "a042_",
    "panel": "1",
    "Type": "300"
  },
  "WPFPanelDISM": {
    "Content": "System Corruption Scan",
    "category": "Fixes",
    "panel": "1",
    "Order": "a043_",
    "Type": "300"
  },
  "WPFFixesWinget": {
    "Content": "WinGet Reinstall",
    "category": "Fixes",
    "panel": "1",
    "Order": "a044_",
    "Type": "300"
  },
  "WPFRunAdobeCCCleanerTool": {
    "Content": "Remove Adobe Creative Cloud",
    "category": "Fixes",
    "panel": "1",
    "Order": "a045_",
    "Type": "300"
  },
  "WPFPanelnetwork": {
    "Content": "Network Connections",
    "category": "Legacy Windows Panels",
    "panel": "2",
    "Type": "200"
  },
  "WPFPanelcontrol": {
    "Content": "Control Panel",
    "category": "Legacy Windows Panels",
    "panel": "2",
    "Type": "200"
  },
  "WPFPanelpower": {
    "Content": "Power Panel",
    "category": "Legacy Windows Panels",
    "panel": "2",
    "Type": "200"
  },
  "WPFPanelregion": {
    "Content": "Region",
    "category": "Legacy Windows Panels",
    "panel": "2",
    "Type": "200"
  },
  "WPFPanelsound": {
    "Content": "Sound Settings",
    "category": "Legacy Windows Panels",
    "panel": "2",
    "Type": "200"
  },
  "WPFPanelsystem": {
    "Content": "System Properties",
    "category": "Legacy Windows Panels",
    "panel": "2",
    "Type": "200"
  },
  "WPFPaneluser": {
    "Content": "User Accounts",
    "category": "Legacy Windows Panels",
    "panel": "2",
    "Type": "200"
  }
}' | convertfrom-json
$sync.configs.preset = '{
  "desktop": [
    "WPFTweaksAH",
    "WPFTweaksDVR",
    "WPFTweaksHiber",
    "WPFTweaksHome",
    "WPFTweaksLoc",
    "WPFTweaksOO",
    "WPFTweaksServices",
    "WPFTweaksStorage",
    "WPFTweaksTele",
    "WPFTweaksWifi"
  ],
  "laptop": [
    "WPFTweaksAH",
    "WPFTweaksDVR",
    "WPFTweaksHome",
    "WPFTweaksLoc",
    "WPFTweaksOO",
    "WPFTweaksServices",
    "WPFTweaksStorage",
    "WPFTweaksTele",
    "WPFTweaksWifi",
    "WPFMiscTweaksLapPower"
  ],
  "minimal": [
    "WPFTweaksHome",
    "WPFTweaksOO",
    "WPFTweaksServices",
    "WPFTweaksTele"
  ]
}' | convertfrom-json
$sync.configs.themes = '{
  "Classic": {
    "ComboBoxBackgroundColor": "#FFFFFF",
    "LabelboxForegroundColor": "#000000",
    "MainForegroundColor": "#000000",
    "MainBackgroundColor": "#FFFFFF",
    "LabelBackgroundColor": "#FAFAFA",
    "LinkForegroundColor": "#000000",
    "LinkHoverForegroundColor": "#000000",
    "GroupBorderBackgroundColor": "#000000",
    "ComboBoxForegroundColor": "#000000",
    "ButtonInstallBackgroundColor": "#FFFFFF",
    "ButtonTweaksBackgroundColor": "#FFFFFF",
    "ButtonConfigBackgroundColor": "#FFFFFF",
    "ButtonUpdatesBackgroundColor": "#FFFFFF",
    "ButtonInstallForegroundColor": "#000000",
    "ButtonTweaksForegroundColor": "#000000",
    "ButtonConfigForegroundColor": "#000000",
    "ButtonUpdatesForegroundColor": "#000000",
    "ButtonBackgroundColor": "#F5F5F5",
    "ButtonBackgroundPressedColor": "#1A1A1A",
    "CheckboxMouseOverColor": "#999999",
    "ButtonBackgroundMouseoverColor": "#C2C2C2",
    "ButtonBackgroundSelectedColor": "#F0F0F0",
    "ButtonForegroundColor": "#000000",
    "ButtonBorderThickness": "1",
    "ButtonMargin": "1",
    "ButtonCornerRadius": "2",
    "ToggleButtonHeight": "25",
    "BorderColor": "#000000",
    "BorderOpacity": "0.2",
    "ShadowPulse": "Forever"
  },
  "Matrix": {
    "ComboBoxBackgroundColor": "#000000",
    "LabelboxForegroundColor": "#FFEE58",
    "MainForegroundColor": "#9CCC65",
    "MainBackgroundColor": "#000000",
    "LabelBackgroundColor": "#000000",
    "LinkForegroundColor": "#add8e6",
    "LinkHoverForegroundColor": "#FFFFFF",
    "ComboBoxForegroundColor": "#FFEE58",
    "ButtonInstallBackgroundColor": "#222222",
    "ButtonTweaksBackgroundColor": "#333333",
    "ButtonConfigBackgroundColor": "#444444",
    "ButtonUpdatesBackgroundColor": "#555555",
    "ButtonInstallForegroundColor": "#FFFFFF",
    "ButtonTweaksForegroundColor": "#FFFFFF",
    "ButtonConfigForegroundColor": "#FFFFFF",
    "ButtonUpdatesForegroundColor": "#FFFFFF",
    "ButtonBackgroundColor": "#000019",
    "ButtonBackgroundPressedColor": "#FFFFFF",
    "ButtonBackgroundMouseoverColor": "#A55A64",
    "ButtonBackgroundSelectedColor": "#FF5733",
    "ButtonForegroundColor": "#9CCC65",
    "ButtonBorderThickness": "1",
    "ButtonMargin": "1",
    "ButtonCornerRadius": "2",
    "ToggleButtonHeight": "25",
    "BorderColor": "#FFAC1C",
    "BorderOpacity": "0.8",
    "ShadowPulse": "0:0:3"
  },
  "Dark": {
    "ComboBoxBackgroundColor": "#000000",
    "LabelboxForegroundColor": "#FFEE58",
    "MainForegroundColor": "#9CCC65",
    "MainBackgroundColor": "#000000",
    "LabelBackgroundColor": "#000000",
    "LinkForegroundColor": "#add8e6",
    "LinkHoverForegroundColor": "#FFFFFF",
    "ComboBoxForegroundColor": "#FFEE58",
    "ButtonInstallBackgroundColor": "#222222",
    "ButtonTweaksBackgroundColor": "#333333",
    "ButtonConfigBackgroundColor": "#444444",
    "ButtonUpdatesBackgroundColor": "#555555",
    "ButtonInstallForegroundColor": "#FFFFFF",
    "ButtonTweaksForegroundColor": "#FFFFFF",
    "ButtonConfigForegroundColor": "#FFFFFF",
    "ButtonUpdatesForegroundColor": "#FFFFFF",
    "ButtonBackgroundColor": "#000019",
    "ButtonBackgroundPressedColor": "#9CCC65",
    "ButtonBackgroundMouseoverColor": "#FF5733",
    "ButtonBackgroundSelectedColor": "#FF5733",
    "ButtonForegroundColor": "#9CCC65",
    "ButtonBorderThickness": "1",
    "ButtonMargin": "1",
    "ButtonCornerRadius": "2",
    "ToggleButtonHeight": "25",
    "BorderColor": "#FFAC1C",
    "BorderOpacity": "0.2",
    "ShadowPulse": "Forever"
  }
}' | convertfrom-json
$sync.configs.tweaks = '{
  "WPFTweaksAH": {
    "Content": "Disable Activity History",
    "Description": "This erases recent docs, clipboard, and run history.",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a005_",
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        "Name": "EnableActivityFeed",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        "Name": "PublishUserActivities",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        "Name": "UploadUserActivities",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "WPFTweaksHiber": {
    "Content": "Disable Hibernation",
    "Description": "Hibernation is really meant for laptops as it saves what&#39;s in memory before turning the pc off. It really should never be used, but some people are lazy and rely on it. Don&#39;t be like Bob. Bob likes hibernation.",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a011_",
    "registry": [
      {
        "Path": "HKLM:\\System\\CurrentControlSet\\Control\\Session Manager\\Power",
        "Name": "HibernateEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FlyoutMenuSettings",
        "Name": "ShowHibernateOption",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ],
    "InvokeScript": [
      "powercfg.exe /hibernate off"
    ],
    "UndoScript": [
      "powercfg.exe /hibernate on"
    ]
  },
  "WPFTweaksHome": {
    "Content": "Disable Homegroup",
    "Description": "Disables HomeGroup - HomeGroup is a password-protected home networking service that lets you share your stuff with other PCs that are currently running and connected to your network.",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a009_",
    "service": [
      {
        "Name": "HomeGroupListener",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "HomeGroupProvider",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      }
    ]
  },
  "WPFTweaksLoc": {
    "Content": "Disable Location Tracking",
    "Description": "Disables Location Tracking...DUH!",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a008_",
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\location",
        "Name": "Value",
        "Type": "String",
        "Value": "Deny",
        "OriginalValue": "Allow"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Sensor\\Overrides\\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}",
        "Name": "SensorPermissionState",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\lfsvc\\Service\\Configuration",
        "Name": "Status",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SYSTEM\\Maps",
        "Name": "AutoUpdateEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "WPFTweaksServices": {
    "Content": "Set Services to Manual",
    "Description": "Turns a bunch of system services to manual that don&#39;t need to be running all the time. This is pretty harmless as if the service is needed, it will simply start on demand.",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a014_",
    "service": [
      {
        "Name": "AJRouter",
        "StartupType": "Disabled",
        "OriginalType": "Manual"
      },
      {
        "Name": "ALG",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "AppIDSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "AppMgmt",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "AppReadiness",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "AppVClient",
        "StartupType": "Disabled",
        "OriginalType": "Disabled"
      },
      {
        "Name": "AppXSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Appinfo",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "AssignedAccessManagerSvc",
        "StartupType": "Disabled",
        "OriginalType": "Manual"
      },
      {
        "Name": "AudioEndpointBuilder",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "AudioSrv",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "Audiosrv",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "AxInstSV",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "BDESVC",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "BFE",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "BITS",
        "StartupType": "AutomaticDelayedStart",
        "OriginalType": "Automatic"
      },
      {
        "Name": "BTAGService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "BcastDVRUserService_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "BluetoothUserService_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "BrokerInfrastructure",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "Browser",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "BthAvctpSvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "BthHFSrv",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "CDPSvc",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "CDPUserSvc_*",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "COMSysApp",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "CaptureService_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "CertPropSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "ClipSVC",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "ConsentUxUserSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "CoreMessagingRegistrar",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "CredentialEnrollmentManagerUserSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "CryptSvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "CscService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "DPS",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "DcomLaunch",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "DcpSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "DevQueryBroker",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "DeviceAssociationBrokerSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "DeviceAssociationService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "DeviceInstall",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "DevicePickerUserSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "DevicesFlowUserSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Dhcp",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "DiagTrack",
        "StartupType": "Disabled",
        "OriginalType": "Automatic"
      },
      {
        "Name": "DialogBlockingService",
        "StartupType": "Disabled",
        "OriginalType": "Disabled"
      },
      {
        "Name": "DispBrokerDesktopSvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "DisplayEnhancementService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "DmEnrollmentSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Dnscache",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "DoSvc",
        "StartupType": "AutomaticDelayedStart",
        "OriginalType": "Automatic"
      },
      {
        "Name": "DsSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "DsmSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "DusmSvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "EFS",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "EapHost",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "EntAppSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "EventLog",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "EventSystem",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "FDResPub",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Fax",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "FontCache",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "FrameServer",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "FrameServerMonitor",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "GraphicsPerfSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "HomeGroupListener",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "HomeGroupProvider",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "HvHost",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "IEEtwCollectorService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "IKEEXT",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "InstallService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "InventorySvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "IpxlatCfgSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "KeyIso",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "KtmRm",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "LSM",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "LanmanServer",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "LanmanWorkstation",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "LicenseManager",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "LxpSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "MSDTC",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "MSiSCSI",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "MapsBroker",
        "StartupType": "AutomaticDelayedStart",
        "OriginalType": "Automatic"
      },
      {
        "Name": "McpManagementService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "MessagingService_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "MicrosoftEdgeElevationService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "MixedRealityOpenXRSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "MpsSvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "MsKeyboardFilter",
        "StartupType": "Manual",
        "OriginalType": "Disabled"
      },
      {
        "Name": "NPSMSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "NaturalAuthentication",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "NcaSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "NcbService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "NcdAutoSetup",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "NetSetupSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "NetTcpPortSharing",
        "StartupType": "Disabled",
        "OriginalType": "Disabled"
      },
      {
        "Name": "Netlogon",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "Netman",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "NgcCtnrSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "NgcSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "NlaSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "OneSyncSvc_*",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "P9RdrService_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "PNRPAutoReg",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "PNRPsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "PcaSvc",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "PeerDistSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "PenService_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "PerfHost",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "PhoneSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "PimIndexMaintenanceSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "PlugPlay",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "PolicyAgent",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Power",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "PrintNotify",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "PrintWorkflowUserSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "ProfSvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "PushToInstall",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "QWAVE",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "RasAuto",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "RasMan",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "RemoteAccess",
        "StartupType": "Disabled",
        "OriginalType": "Disabled"
      },
      {
        "Name": "RemoteRegistry",
        "StartupType": "Disabled",
        "OriginalType": "Disabled"
      },
      {
        "Name": "RetailDemo",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "RmSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "RpcEptMapper",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "RpcLocator",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "RpcSs",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "SCPolicySvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SCardSvr",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SDRSVC",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SEMgrSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SENS",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "SNMPTRAP",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SNMPTrap",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SSDPSRV",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SamSs",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "ScDeviceEnum",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Schedule",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "SecurityHealthService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Sense",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SensorDataService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SensorService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SensrSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SessionEnv",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SgrmBroker",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "SharedAccess",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "SharedRealitySvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "ShellHWDetection",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "SmsRouter",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Spooler",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "SstpSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "StateRepository",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "StiSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "StorSvc",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "SysMain",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "SystemEventsBroker",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "TabletInputService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "TapiSrv",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "TermService",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "TextInputManagementService",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "Themes",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "TieringEngineService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "TimeBroker",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "TimeBrokerSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "TokenBroker",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "TrkWks",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "TroubleshootingSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "TrustedInstaller",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "UI0Detect",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "UdkUserSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "UevAgentService",
        "StartupType": "Disabled",
        "OriginalType": "Disabled"
      },
      {
        "Name": "UmRdpService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "UnistoreSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "UserDataSvc_*",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "UserManager",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "UsoSvc",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "VGAuthService",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "VMTools",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "VSS",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "VacSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "VaultSvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "W32Time",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WEPHOSTSVC",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WFDSConMgrSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WMPNetworkSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WManSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WPDBusEnum",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WSService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WSearch",
        "StartupType": "AutomaticDelayedStart",
        "OriginalType": "Automatic"
      },
      {
        "Name": "WaaSMedicSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WalletService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WarpJITSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WbioSrvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Wcmsvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "WcsPlugInService",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WdNisSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WdiServiceHost",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WdiSystemHost",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WebClient",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Wecsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WerSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WiaRpc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WinDefend",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "WinHttpAutoProxySvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WinRM",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "Winmgmt",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "WlanSvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "WpcMonSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "WpnService",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "WpnUserService_*",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "WwanSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "XblAuthManager",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "XblGameSave",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "XboxGipSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "XboxNetApiSvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "autotimesvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "bthserv",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "camsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "cbdhsvc_*",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "cloudidsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "dcsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "defragsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "diagnosticshub.standardcollector.service",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "diagsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "dmwappushservice",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "dot3svc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "edgeupdate",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "edgeupdatem",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "embeddedmode",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "fdPHost",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "fhsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "gpsvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "hidserv",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "icssvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "iphlpsvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "lfsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "lltdsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "lmhosts",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "mpssvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "msiserver",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "netprofm",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "nsi",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "p2pimsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "p2psvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "perceptionsimulation",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "pla",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "seclogon",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "shpamsvc",
        "StartupType": "Disabled",
        "OriginalType": "Disabled"
      },
      {
        "Name": "smphost",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "spectrum",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "sppsvc",
        "StartupType": "AutomaticDelayedStart",
        "OriginalType": "Automatic"
      },
      {
        "Name": "ssh-agent",
        "StartupType": "Disabled",
        "OriginalType": "Disabled"
      },
      {
        "Name": "svsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "swprv",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "tiledatamodelsvc",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "tzautoupdate",
        "StartupType": "Disabled",
        "OriginalType": "Disabled"
      },
      {
        "Name": "uhssvc",
        "StartupType": "Disabled",
        "OriginalType": "Disabled"
      },
      {
        "Name": "upnphost",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "vds",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "vm3dservice",
        "StartupType": "Manual",
        "OriginalType": "Automatic"
      },
      {
        "Name": "vmicguestinterface",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "vmicheartbeat",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "vmickvpexchange",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "vmicrdv",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "vmicshutdown",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "vmictimesync",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "vmicvmsession",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "vmicvss",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "vmvss",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "wbengine",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "wcncsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "webthreatdefsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "webthreatdefusersvc_*",
        "StartupType": "Automatic",
        "OriginalType": "Automatic"
      },
      {
        "Name": "wercplsupport",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "wisvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "wlidsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "wlpasvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "wmiApSrv",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "workfolderssvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "wscsvc",
        "StartupType": "AutomaticDelayedStart",
        "OriginalType": "Automatic"
      },
      {
        "Name": "wuauserv",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      },
      {
        "Name": "wudfsvc",
        "StartupType": "Manual",
        "OriginalType": "Manual"
      }
    ]
  },
  "WPFTweaksTele": {
    "Content": "Disable Telemetry",
    "Description": "Disables Microsoft Telemetry. Note: This will lock many Edge Browser settings. Microsoft spies heavily on you when using the Edge browser.",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a003_",
    "ScheduledTask": [
      {
        "Name": "Microsoft\\Windows\\Application Experience\\Microsoft Compatibility Appraiser",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Application Experience\\ProgramDataUpdater",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Autochk\\Proxy",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Customer Experience Improvement Program\\Consolidator",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Customer Experience Improvement Program\\UsbCeip",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\DiskDiagnostic\\Microsoft-Windows-DiskDiagnosticDataCollector",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Feedback\\Siuf\\DmClient",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Feedback\\Siuf\\DmClientOnScenarioDownload",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Windows Error Reporting\\QueueReporting",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Application Experience\\MareBackup",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Application Experience\\StartupAppTask",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Application Experience\\PcaPatchDbTask",
        "State": "Disabled",
        "OriginalState": "Enabled"
      },
      {
        "Name": "Microsoft\\Windows\\Maps\\MapsUpdateTask",
        "State": "Disabled",
        "OriginalState": "Enabled"
      }
    ],
    "registry": [
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\DataCollection",
        "Type": "DWord",
        "Value": "0",
        "Name": "AllowTelemetry",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection",
        "OriginalValue": "1",
        "Name": "AllowTelemetry",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "Name": "ContentDeliveryAllowed",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "Name": "OemPreInstalledAppsEnabled",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "Name": "PreInstalledAppsEnabled",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "Name": "PreInstalledAppsEverEnabled",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "Name": "SilentInstalledAppsEnabled",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "Name": "SubscribedContent-338387Enabled",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "Name": "SubscribedContent-338388Enabled",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "Name": "SubscribedContent-338389Enabled",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "Name": "SubscribedContent-353698Enabled",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
        "OriginalValue": "1",
        "Name": "SystemPaneSuggestionsEnabled",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent",
        "OriginalValue": "0",
        "Name": "DisableWindowsConsumerFeatures",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Siuf\\Rules",
        "OriginalValue": "0",
        "Name": "NumberOfSIUFInPeriod",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection",
        "OriginalValue": "0",
        "Name": "DoNotShowFeedbackNotifications",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent",
        "OriginalValue": "0",
        "Name": "DisableTailoredExperiencesWithDiagnosticData",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\AdvertisingInfo",
        "OriginalValue": "0",
        "Name": "DisabledByGroupPolicy",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\Windows Error Reporting",
        "OriginalValue": "0",
        "Name": "Disabled",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\DeliveryOptimization\\Config",
        "OriginalValue": "1",
        "Name": "DODownloadMode",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Remote Assistance",
        "OriginalValue": "1",
        "Name": "fAllowToGetHelp",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\OperationStatusManager",
        "OriginalValue": "0",
        "Name": "EnthusiastMode",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "Name": "ShowTaskViewButton",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\\People",
        "OriginalValue": "1",
        "Name": "PeopleBand",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "Name": "LaunchTo",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem",
        "OriginalValue": "0",
        "Name": "LongPathsEnabled",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "_Comment": "Driver searching is a function that should be left in",
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\DriverSearching",
        "OriginalValue": "1",
        "Name": "SearchOrderConfig",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile",
        "OriginalValue": "1",
        "Name": "SystemResponsiveness",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile",
        "OriginalValue": "1",
        "Name": "NetworkThrottlingIndex",
        "Value": "4294967295",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Control Panel\\Desktop",
        "OriginalValue": "1",
        "Name": "MenuShowDelay",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Control Panel\\Desktop",
        "OriginalValue": "1",
        "Name": "AutoEndTasks",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management",
        "OriginalValue": "0",
        "Name": "ClearPageFileAtShutdown",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SYSTEM\\ControlSet001\\Services\\Ndu",
        "OriginalValue": "1",
        "Name": "Start",
        "Value": "2",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Control Panel\\Mouse",
        "OriginalValue": "400",
        "Name": "MouseHoverTime",
        "Value": "400",
        "Type": "String"
      },
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\LanmanServer\\Parameters",
        "OriginalValue": "20",
        "Name": "IRPStackSize",
        "Value": "30",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Windows Feeds",
        "OriginalValue": "1",
        "Name": "EnableFeeds",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Feeds",
        "OriginalValue": "1",
        "Name": "ShellFeedsTaskbarViewMode",
        "Value": "2",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer",
        "OriginalValue": "1",
        "Name": "HideSCAMeetNow",
        "Value": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\Tasks\\Games",
        "OriginalValue": "1",
        "Name": "GPU Priority",
        "Value": "8",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\Tasks\\Games",
        "OriginalValue": "1",
        "Name": "Priority",
        "Value": "6",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\Tasks\\Games",
        "OriginalValue": "High",
        "Name": "Scheduling Category",
        "Value": "High",
        "Type": "String"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\UserProfileEngagement",
        "OriginalValue": "1",
        "Name": "ScoobeSystemSettingEnabled",
        "Value": "0",
        "Type": "DWord"
      }
    ],
    "InvokeScript": [
      "
      bcdedit /set `{current`} bootmenupolicy Legacy | Out-Null
        If ((get-ItemProperty -Path \"HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\" -Name CurrentBuild).CurrentBuild -lt 22557) {
            $taskmgr = Start-Process -WindowStyle Hidden -FilePath taskmgr.exe -PassThru
            Do {
                Start-Sleep -Milliseconds 100
                $preferences = Get-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\TaskManager\" -Name \"Preferences\" -ErrorAction SilentlyContinue
            } Until ($preferences)
            Stop-Process $taskmgr
            $preferences.Preferences[28] = 0
            Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\TaskManager\" -Name \"Preferences\" -Type Binary -Value $preferences.Preferences
        }
        Remove-Item -Path \"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\MyComputer\\NameSpace\\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}\" -Recurse -ErrorAction SilentlyContinue

        # Fix Managed by your organization in Edge if regustry path exists then remove it

        If (Test-Path \"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge\") {
            Remove-Item -Path \"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge\" -Recurse -ErrorAction SilentlyContinue
        }

        # Group svchost.exe processes
        $ram = (Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1kb
        Set-ItemProperty -Path \"HKLM:\\SYSTEM\\CurrentControlSet\\Control\" -Name \"SvcHostSplitThresholdInKB\" -Type DWord -Value $ram -Force

        $autoLoggerDir = \"$env:PROGRAMDATA\\Microsoft\\Diagnosis\\ETLLogs\\AutoLogger\"
        If (Test-Path \"$autoLoggerDir\\AutoLogger-Diagtrack-Listener.etl\") {
            Remove-Item \"$autoLoggerDir\\AutoLogger-Diagtrack-Listener.etl\"
        }
        icacls $autoLoggerDir /deny SYSTEM:`(OI`)`(CI`)F | Out-Null

        # Disable Defender Auto Sample Submission
        Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue | Out-Null
        "
    ]
  },
  "WPFTweaksWifi": {
    "Content": "Disable Wifi-Sense",
    "Description": "Wifi Sense is a spying service that phones home all nearby scanned wifi networks and your current geo location.",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a004_",
    "registry": [
      {
        "Path": "HKLM:\\Software\\Microsoft\\PolicyManager\\default\\WiFi\\AllowWiFiHotSpotReporting",
        "Name": "Value",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      },
      {
        "Path": "HKLM:\\Software\\Microsoft\\PolicyManager\\default\\WiFi\\AllowAutoConnectToWiFiSenseHotspots",
        "Name": "Value",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "WPFTweaksUTC": {
    "Content": "Set Time to UTC (Dual Boot)",
    "Description": "Essential for computers that are dual booting. Fixes the time sync with Linux Systems.",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a022_",
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\TimeZoneInformation",
        "Name": "RealTimeIsUniversal",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "0"
      }
    ]
  },
  "WPFTweaksDisplay": {
    "Content": "Set Display for Performance",
    "Description": "Sets the system preferences to performance. You can do this manually with sysdm.cpl as well.",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a021_",
    "registry": [
      {
        "Path": "HKCU:\\Control Panel\\Desktop",
        "OriginalValue": "1",
        "Name": "DragFullWindows",
        "Value": "0",
        "Type": "String"
      },
      {
        "Path": "HKCU:\\Control Panel\\Desktop",
        "OriginalValue": "1",
        "Name": "MenuShowDelay",
        "Value": "200",
        "Type": "String"
      },
      {
        "Path": "HKCU:\\Control Panel\\Desktop\\WindowMetrics",
        "OriginalValue": "1",
        "Name": "MinAnimate",
        "Value": "0",
        "Type": "String"
      },
      {
        "Path": "HKCU:\\Control Panel\\Keyboard",
        "OriginalValue": "1",
        "Name": "KeyboardDelay",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "Name": "ListviewAlphaSelect",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "Name": "ListviewShadow",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "Name": "TaskbarAnimations",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\VisualEffects",
        "OriginalValue": "1",
        "Name": "VisualFXSetting",
        "Value": "3",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\DWM",
        "OriginalValue": "1",
        "Name": "EnableAeroPeek",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "Name": "TaskbarMn",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "Name": "TaskbarDa",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
        "OriginalValue": "1",
        "Name": "ShowTaskViewButton",
        "Value": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search",
        "OriginalValue": "1",
        "Name": "SearchboxTaskbarMode",
        "Value": "0",
        "Type": "DWord"
      }
    ],
    "InvokeScript": [
      "Set-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"UserPreferencesMask\" -Type Binary -Value ([byte[]](144,18,3,128,16,0,0,0))"
    ],
    "UndoScript": [
      "Remove-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"UserPreferencesMask\""
    ]
  },
  "WPFTweaksDeBloat": {
    "Content": "Remove ALL MS Store Apps - NOT RECOMMENDED",
    "Description": "USE WITH CAUTION!!!!! This will remove ALL Microsoft store apps other than the essentials to make winget work. Games installed by MS Store ARE INCLUDED!",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a025_",
    "appx": [
      "Microsoft.Microsoft3DViewer",
      "Microsoft.AppConnector",
      "Microsoft.BingFinance",
      "Microsoft.BingNews",
      "Microsoft.BingSports",
      "Microsoft.BingTranslator",
      "Microsoft.BingWeather",
      "Microsoft.BingFoodAndDrink",
      "Microsoft.BingHealthAndFitness",
      "Microsoft.BingTravel",
      "Microsoft.MinecraftUWP",
      "Microsoft.GamingServices",
      "Microsoft.GetHelp",
      "Microsoft.Getstarted",
      "Microsoft.Messaging",
      "Microsoft.Microsoft3DViewer",
      "Microsoft.MicrosoftSolitaireCollection",
      "Microsoft.NetworkSpeedTest",
      "Microsoft.News",
      "Microsoft.Office.Lens",
      "Microsoft.Office.Sway",
      "Microsoft.Office.OneNote",
      "Microsoft.OneConnect",
      "Microsoft.People",
      "Microsoft.Print3D",
      "Microsoft.SkypeApp",
      "Microsoft.Wallet",
      "Microsoft.Whiteboard",
      "Microsoft.WindowsAlarms",
      "microsoft.windowscommunicationsapps",
      "Microsoft.WindowsFeedbackHub",
      "Microsoft.WindowsMaps",
      "Microsoft.WindowsPhone",
      "Microsoft.WindowsSoundRecorder",
      "Microsoft.XboxApp",
      "Microsoft.ConnectivityStore",
      "Microsoft.CommsPhone",
      "Microsoft.ScreenSketch",
      "Microsoft.Xbox.TCUI",
      "Microsoft.XboxGameOverlay",
      "Microsoft.XboxGameCallableUI",
      "Microsoft.XboxSpeechToTextOverlay",
      "Microsoft.MixedReality.Portal",
      "Microsoft.XboxIdentityProvider",
      "Microsoft.ZuneMusic",
      "Microsoft.ZuneVideo",
      "Microsoft.Getstarted",
      "Microsoft.MicrosoftOfficeHub",
      "*EclipseManager*",
      "*ActiproSoftwareLLC*",
      "*AdobeSystemsIncorporated.AdobePhotoshopExpress*",
      "*Duolingo-LearnLanguagesforFree*",
      "*PandoraMediaInc*",
      "*CandyCrush*",
      "*BubbleWitch3Saga*",
      "*Wunderlist*",
      "*Flipboard*",
      "*Twitter*",
      "*Facebook*",
      "*Royal Revolt*",
      "*Sway*",
      "*Speed Test*",
      "*Dolby*",
      "*Viber*",
      "*ACGMediaPlayer*",
      "*Netflix*",
      "*OneCalendar*",
      "*LinkedInforWindows*",
      "*HiddenCityMysteryofShadows*",
      "*Hulu*",
      "*HiddenCity*",
      "*AdobePhotoshopExpress*",
      "*HotspotShieldFreeVPN*",
      "*Microsoft.Advertising.Xaml*"
    ],
    "InvokeScript": [
      "
        $TeamsPath = [System.IO.Path]::Combine($env:LOCALAPPDATA, ''Microsoft'', ''Teams'')
        $TeamsUpdateExePath = [System.IO.Path]::Combine($TeamsPath, ''Update.exe'')

        Write-Host \"Stopping Teams process...\"
        Stop-Process -Name \"*teams*\" -Force -ErrorAction SilentlyContinue

        Write-Host \"Uninstalling Teams from AppData\\Microsoft\\Teams\"
        if ([System.IO.File]::Exists($TeamsUpdateExePath)) {
            # Uninstall app
            $proc = Start-Process $TeamsUpdateExePath \"-uninstall -s\" -PassThru
            $proc.WaitForExit()
        }

        Write-Host \"Removing Teams AppxPackage...\"
        Get-AppxPackage \"*Teams*\" | Remove-AppxPackage -ErrorAction SilentlyContinue
        Get-AppxPackage \"*Teams*\" -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

        Write-Host \"Deleting Teams directory\"
        if ([System.IO.Directory]::Exists($TeamsPath)) {
            Remove-Item $TeamsPath -Force -Recurse -ErrorAction SilentlyContinue
        }

        Write-Host \"Deleting Teams uninstall registry key\"
        # Uninstall from Uninstall registry key UninstallString
        $us = (Get-ChildItem -Path HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall, HKLM:\\SOFTWARE\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall | Get-ItemProperty | Where-Object { $_.DisplayName -like ''*Teams*''}).UninstallString
        if ($us.Length -gt 0) {
            $us = ($us.Replace(''/I'', ''/uninstall '') + '' /quiet'').Replace(''  '', '' '')
            $FilePath = ($us.Substring(0, $us.IndexOf(''.exe'') + 4).Trim())
            $ProcessArgs = ($us.Substring($us.IndexOf(''.exe'') + 5).Trim().replace(''  '', '' ''))
            $proc = Start-Process -FilePath $FilePath -Args $ProcessArgs -PassThru
            $proc.WaitForExit()
        }
      "
    ]
  },
  "WPFTweaksRestorePoint": {
    "Content": "Create Restore Point",
    "Description": "Creates a restore point at runtime in case a revert is needed from WinUtil modifications",
    "category": "Essential Tweaks",
    "panel": "1",
    "Checked": "True",
    "Order": "a001_",
    "InvokeScript": [
      "
        # Check if the user has administrative privileges
        if (-Not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host \"Please run this script as an administrator.\"
            return
        }
    
        # Check if System Restore is enabled for the main drive
        try {
            # Try getting restore points to check if System Restore is enabled
            Enable-ComputerRestore -Drive \"$env:SystemDrive\"
        } catch {
            Write-Host \"An error occurred while enabling System Restore: $_\"
        }
    
        # Check if the SystemRestorePointCreationFrequency value exists
        $exists = Get-ItemProperty -path \"HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\SystemRestore\" -Name \"SystemRestorePointCreationFrequency\" -ErrorAction SilentlyContinue
        if($null -eq $exists){
            write-host ''Changing system to allow multiple restore points per day''
            Set-ItemProperty -Path \"HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\SystemRestore\" -Name \"SystemRestorePointCreationFrequency\" -Value \"0\" -Type DWord -Force -ErrorAction Stop | Out-Null
        }
    
        # Attempt to load the required module for Get-ComputerRestorePoint
        try {
            Import-Module Microsoft.PowerShell.Management -ErrorAction Stop
        } catch {
            Write-Host \"Failed to load the Microsoft.PowerShell.Management module: $_\"
            return
        }
    
        # Get all the restore points for the current day
        try {
            $existingRestorePoints = Get-ComputerRestorePoint | Where-Object { $_.CreationTime.Date -eq (Get-Date).Date }
        } catch {
            Write-Host \"Failed to retrieve restore points: $_\"
            return
        }
    
        # Check if there is already a restore point created today
        if ($existingRestorePoints.Count -eq 0) {
            $description = \"System Restore Point created by WinUtil\"
    
            Checkpoint-Computer -Description $description -RestorePointType \"MODIFY_SETTINGS\"
            Write-Host -ForegroundColor Green \"System Restore Point Created Successfully\"
        }
      "
    ]
  },
  "WPFTweaksEndTaskOnTaskbar": {
    "Content": "Enable End Task With Right Click",
    "Description": "Enables option to end task when right clicking a program in the taskbar",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a002_",
    "InvokeScript": [
      "
      Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\\TaskbarDeveloperSettings\" -Name \"TaskbarEndTask\" -Type \"DWord\" -Value \"1\"
      "
    ],
    "UndoScript": [
      "
      Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\\TaskbarDeveloperSettings\" -Name \"TaskbarEndTask\" -Type \"DWord\" -Value \"0\"
      "
    ]
  },
  "WPFTweaksOO": {
    "Content": "Run OO Shutup",
    "Description": "Runs OO Shutup and applies the recommended Tweaks. https://www.oo-software.com/en/shutup10",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a002_",
    "ToolTip": "Runs OO Shutup and applies the recommended Tweaks https://www.oo-software.com/en/shutup10",
    "InvokeScript": [
      "Invoke-WPFOOSU -action \"recommended\""
    ],
    "UndoScript": [
      "Invoke-WPFOOSU -action \"undo\""
    ]
  },
  "WPFTweaksStorage": {
    "Content": "Disable Storage Sense",
    "Description": "Storage Sense deletes temp files automatically.",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a010_",
    "InvokeScript": [
      "Set-ItemProperty -Path \"HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\StorageSense\\Parameters\\StoragePolicy\" -Name \"01\" -Value 0 -Type Dword -Force"
    ],
    "UndoScript": [
      "Set-ItemProperty -Path \"HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\StorageSense\\Parameters\\StoragePolicy\" -Name \"01\" -Value 1 -Type Dword -Force"
    ]
  },
  "WPFTweaksRemoveEdge": {
    "Content": "Remove Microsoft Edge - NOT RECOMMENDED",
    "Description": "Removes MS Edge when it gets reinstalled by updates.",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a026_",
    "InvokeScript": [
      "
        #:: Standalone script by AveYo Source: https://raw.githubusercontent.com/AveYo/fox/main/Edge_Removal.bat

        curl.exe -s \"https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/edgeremoval.bat\" -o $ENV:temp\\edgeremoval.bat
        Start-Process $ENV:temp\\edgeremoval.bat

        "
    ],
    "UndoScript": [
      "
      Write-Host \"Install Microsoft Edge\"
      Start-Process -FilePath winget -ArgumentList \"install -e --accept-source-agreements --accept-package-agreements --silent Microsoft.Edge \" -NoNewWindow -Wait
      "
    ]
  },
  "WPFTweaksRemoveOnedrive": {
    "Content": "Remove OneDrive",
    "Description": "Copies OneDrive files to Default Home Folders and Uninstalls it.",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a027_",
    "InvokeScript": [
      "

        Write-Host \"Kill OneDrive process\"
        taskkill.exe /F /IM \"OneDrive.exe\"
        taskkill.exe /F /IM \"explorer.exe\"

        Write-Host \"Copy all OneDrive to Root UserProfile\"
        Start-Process -FilePath powershell -ArgumentList \"robocopy ''$($env:USERPROFILE.TrimEnd())\\OneDrive'' ''$($env:USERPROFILE.TrimEnd())\\'' /e /xj\" -NoNewWindow -Wait

        Write-Host \"Remove OneDrive\"
        Start-Process -FilePath winget -ArgumentList \"uninstall -e --purge --force --silent Microsoft.OneDrive \" -NoNewWindow -Wait

        Write-Host \"Removing OneDrive leftovers\"
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue \"$env:localappdata\\Microsoft\\OneDrive\"
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue \"$env:localappdata\\OneDrive\"
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue \"$env:programdata\\Microsoft OneDrive\"
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue \"$env:systemdrive\\OneDriveTemp\"
        # check if directory is empty before removing:
        If ((Get-ChildItem \"$env:userprofile\\OneDrive\" -Recurse | Measure-Object).Count -eq 0) {
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue \"$env:userprofile\\OneDrive\"
        }

        Write-Host \"Remove Onedrive from explorer sidebar\"
        Set-ItemProperty -Path \"HKCR:\\CLSID\\{018D5C66-4533-4307-9B53-224DE2ED1FE6}\" -Name \"System.IsPinnedToNameSpaceTree\" -Value 0
        Set-ItemProperty -Path \"HKCR:\\Wow6432Node\\CLSID\\{018D5C66-4533-4307-9B53-224DE2ED1FE6}\" -Name \"System.IsPinnedToNameSpaceTree\" -Value 0

        Write-Host \"Removing run hook for new users\"
        reg load \"hku\\Default\" \"C:\\Users\\Default\\NTUSER.DAT\"
        reg delete \"HKEY_USERS\\Default\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run\" /v \"OneDriveSetup\" /f
        reg unload \"hku\\Default\"

        Write-Host \"Removing startmenu entry\"
        Remove-Item -Force -ErrorAction SilentlyContinue \"$env:userprofile\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\OneDrive.lnk\"

        Write-Host \"Removing scheduled task\"
        Get-ScheduledTask -TaskPath ''\\'' -TaskName ''OneDrive*'' -ea SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

        # Add Shell folders restoring default locations
        Write-Host \"Shell Fixing\"
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"AppData\" -Value \"$env:userprofile\\AppData\\Roaming\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Cache\" -Value \"$env:userprofile\\AppData\\Local\\Microsoft\\Windows\\INetCache\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Cookies\" -Value \"$env:userprofile\\AppData\\Local\\Microsoft\\Windows\\INetCookies\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Favorites\" -Value \"$env:userprofile\\Favorites\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"History\" -Value \"$env:userprofile\\AppData\\Local\\Microsoft\\Windows\\History\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Local AppData\" -Value \"$env:userprofile\\AppData\\Local\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"My Music\" -Value \"$env:userprofile\\Music\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"My Video\" -Value \"$env:userprofile\\Videos\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"NetHood\" -Value \"$env:userprofile\\AppData\\Roaming\\Microsoft\\Windows\\Network Shortcuts\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"PrintHood\" -Value \"$env:userprofile\\AppData\\Roaming\\Microsoft\\Windows\\Printer Shortcuts\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Programs\" -Value \"$env:userprofile\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Recent\" -Value \"$env:userprofile\\AppData\\Roaming\\Microsoft\\Windows\\Recent\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"SendTo\" -Value \"$env:userprofile\\AppData\\Roaming\\Microsoft\\Windows\\SendTo\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Start Menu\" -Value \"$env:userprofile\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Startup\" -Value \"$env:userprofile\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Templates\" -Value \"$env:userprofile\\AppData\\Roaming\\Microsoft\\Windows\\Templates\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"{374DE290-123F-4565-9164-39C4925E467B}\" -Value \"$env:userprofile\\Downloads\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Desktop\" -Value \"$env:userprofile\\Desktop\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"My Pictures\" -Value \"$env:userprofile\\Pictures\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"Personal\" -Value \"$env:userprofile\\Documents\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"{F42EE2D3-909F-4907-8871-4C22FC0BF756}\" -Value \"$env:userprofile\\Documents\" -Type ExpandString
        Set-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders\" -Name \"{0DDD015D-B06C-45D5-8C4C-F59713854639}\" -Value \"$env:userprofile\\Pictures\" -Type ExpandString
        Write-Host \"Restarting explorer\"
        Start-Process \"explorer.exe\"

        Write-Host \"Waiting for explorer to complete loading\"
        Write-Host \"Please Note - OneDrive folder may still have items in it. You must manually delete it, but all the files should already be copied to the base user folder.\"
        Start-Sleep 5
        "
    ],
    "UndoScript": [
      "
      Write-Host \"Install OneDrive\"
      Start-Process -FilePath winget -ArgumentList \"install -e --accept-source-agreements --accept-package-agreements --silent Microsoft.OneDrive \" -NoNewWindow -Wait
      "
    ]
  },
  "WPFTweaksDisableNotifications": {
    "Content": "Disable Notification Tray/Calendar",
    "Description": "Disables all Notifications INCLUDING Calendar",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a024_",
    "registry": [
      {
        "Path": "HKCU:\\Software\\Policies\\Microsoft\\Windows\\Explorer",
        "Name": "DisableNotificationCenter",
        "Type": "DWord",
        "Value": "1",
        "OriginalValue": "0"
      },
      {
        "Path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications",
        "Name": "ToastEnabled",
        "Type": "DWord",
        "Value": "0",
        "OriginalValue": "1"
      }
    ]
  },
  "WPFTweaksRightClickMenu": {
    "Content": "Set Classic Right-Click Menu ",
    "Description": "Great Windows 11 tweak to bring back good context menus when right clicking things in explorer.",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a028_",
    "InvokeScript": [
      "
      New-Item -Path \"HKCU:\\Software\\Classes\\CLSID\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\" -Name \"InprocServer32\" -force -value \"\"
      Write-Host Restarting explorer.exe ...
      $process = Get-Process -Name \"explorer\"
      Stop-Process -InputObject $process
      "
    ],
    "UndoScript": [
      "
      Remove-Item -Path \"HKCU:\\Software\\Classes\\CLSID\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\" -Recurse -Confirm:$false -Force
      # Restarting Explorer in the Undo Script might not be necessary, as the Registry change without restarting Explorer does work, but just to make sure.
      Write-Host Restarting explorer.exe ...
      $process = Get-Process -Name \"explorer\"
      Stop-Process -InputObject $process
      "
    ]
  },
  "WPFTweaksDiskCleanup": {
    "Content": "Run Disk Cleanup",
    "Description": "Runs Disk Cleanup on Drive C: and removes old Windows Updates.",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a007_",
    "InvokeScript": [
      "
      cleanmgr.exe /d C: /VERYLOWDISK
      Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase
      "
    ]
  },
  "WPFTweaksDeleteTempFiles": {
    "Content": "Delete Temporary Files",
    "Description": "Erases TEMP Folders",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a006_",
    "InvokeScript": [
      "Get-ChildItem -Path \"C:\\Windows\\Temp\" *.* -Recurse | Remove-Item -Force -Recurse
    Get-ChildItem -Path $env:TEMP *.* -Recurse | Remove-Item -Force -Recurse"
    ]
  },
  "WPFTweaksDVR": {
    "Content": "Disable GameDVR",
    "Description": "GameDVR is a Windows App that is a dependency for some Store Games. I&#39;ve never met someone that likes it, but it&#39;s there for the XBOX crowd.",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a012_",
    "registry": [
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_FSEBehavior",
        "Value": "2",
        "OriginalValue": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_Enabled",
        "Value": "0",
        "OriginalValue": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_DXGIHonorFSEWindowsCompatible",
        "Value": "1",
        "OriginalValue": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_HonorUserFSEBehaviorMode",
        "Value": "1",
        "OriginalValue": "0",
        "Type": "DWord"
      },
      {
        "Path": "HKCU:\\System\\GameConfigStore",
        "Name": "GameDVR_EFSEFeatureFlags",
        "Value": "0",
        "OriginalValue": "1",
        "Type": "DWord"
      },
      {
        "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\GameDVR",
        "Name": "AllowGameDVR",
        "Value": "0",
        "OriginalValue": "1",
        "Type": "DWord"
      }
    ]
  },
  "WPFTweaksTeredo": {
    "Content": "Disable Teredo",
    "Description": "Teredo network tunneling is a ipv6 feature that can cause additional latency.",
    "category": "Essential Tweaks",
    "panel": "1",
    "Order": "a013_",
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters",
        "Name": "DisabledComponents",
        "Value": "1",
        "OriginalValue": "0",
        "Type": "DWord"
      }
    ],
    "InvokeScript": [
      "netsh interface teredo set state disabled"
    ],
    "UndoScript": [
      "netsh interface teredo set state default"
    ]
  },
  "WPFTweaksDisableipsix": {
    "Content": "Disable IPv6",
    "Description": "Disables IPv6.",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a031_",
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters",
        "Name": "DisabledComponents",
        "Value": "255",
        "OriginalValue": "0",
        "Type": "DWord"
      }
    ],
    "InvokeScript": [
      "Disable-NetAdapterBinding -Name \"*\" -ComponentID ms_tcpip6"
    ],
    "UndoScript": [
      "Enable-NetAdapterBinding -Name \"*\" -ComponentID ms_tcpip6"
    ]
  },
  "WPFTweaksEnableipsix": {
    "Content": "Enable IPv6",
    "Description": "Enables IPv6.",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a030_",
    "registry": [
      {
        "Path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters",
        "Name": "DisabledComponents",
        "Value": "0",
        "OriginalValue": "0",
        "Type": "DWord"
      }
    ],
    "InvokeScript": [
      "Enable-NetAdapterBinding -Name \"*\" -ComponentID ms_tcpip6"
    ],
    "UndoScript": [
      "Disable-NetAdapterBinding -Name \"*\" -ComponentID ms_tcpip6"
    ]
  },
  "WPFToggleDarkMode": {
    "Content": "Dark Theme",
    "Description": "Enable/Disable Dark Mode.",
    "category": "Customize Preferences",
    "panel": "2",
    "Order": "a060_",
    "Type": "Toggle"
  },
  "WPFToggleBingSearch": {
    "Content": "Bing Search in Start Menu",
    "Description": "If enable then includes web search results from Bing in your Start Menu search.",
    "category": "Customize Preferences",
    "panel": "2",
    "Order": "a061_",
    "Type": "Toggle"
  },
  "WPFToggleNumLock": {
    "Content": "NumLock on Startup",
    "Description": "Toggle the Num Lock key state when your computer starts.",
    "category": "Customize Preferences",
    "panel": "2",
    "Order": "a062_",
    "Type": "Toggle"
  },
  "WPFToggleVerboseLogon": {
    "Content": "Verbose Logon Messages",
    "Description": "Show detailed messages during the login process for troubleshooting and diagnostics.",
    "category": "Customize Preferences",
    "panel": "2",
    "Order": "a063_",
    "Type": "Toggle"
  },
  "WPFToggleShowExt": {
    "Content": "Show File Extensions",
    "Description": "If enabled then File extensions (e.g., .txt, .jpg) are visible.",
    "category": "Customize Preferences",
    "panel": "2",
    "Order": "a064_",
    "Type": "Toggle"
  },
  "WPFToggleSnapFlyout": {
    "Content": "Snap Assist Flyout",
    "Description": "If enabled then Snap preview is disabled when maximize button is hovered.",
    "category": "Customize Preferences",
    "panel": "2",
    "Order": "a065_",
    "Type": "Toggle"
  },
  "WPFToggleMouseAcceleration": {
    "Content": "Mouse Acceleration",
    "Description": "If Enabled then Cursor movement is affected by the speed of your physical mouse movements.",
    "category": "Customize Preferences",
    "panel": "2",
    "Order": "a066_",
    "Type": "Toggle"
  },
  "WPFToggleStickyKeys": {
    "Content": "Sticky Keys",
    "Description": "If Enabled then Sticky Keys is activated - Sticky keys is an accessibility feature of some graphical user interfaces which assists users who have physical disabilities or help users reduce repetitive strain injury.",
    "category": "Customize Preferences",
    "panel": "2",
    "Order": "a067_",
    "Type": "Toggle"
  },
  "WPFOOSUbutton": {
    "Content": "Customize OO Shutup Tweaks",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a039_",
    "Type": "220"
  },
  "WPFToggleTaskbarWidgets": {
    "Content": "Taskbar Widgets",
    "Description": "If Enabled then Widgets Icon in Taskbar will be shown.",
    "category": "Customize Preferences",
    "panel": "2",
    "Order": "a068_",
    "Type": "Toggle"
  },
  "WPFchangedns": {
    "Content": "DNS",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a040_",
    "Type": "Combobox",
    "ComboItems": "Default DHCP Google Cloudflare Cloudflare_Malware Cloudflare_Malware_Adult Level3 Open_DNS Quad9"
  },
  "WPFTweaksbutton": {
    "Content": "Run Tweaks",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a041_",
    "Type": "160"
  },
  "WPFUndoall": {
    "Content": "Undo Selected Tweaks",
    "category": "z__Advanced Tweaks - CAUTION",
    "panel": "1",
    "Order": "a042_",
    "Type": "160"
  },
  "WPFAddUltPerf": {
    "Content": "Add and Activate Ultimate Performance Profile",
    "category": "Performance Plans",
    "panel": "2",
    "Order": "a080_",
    "Type": "300"
  },
  "WPFRemoveUltPerf": {
    "Content": "Remove Ultimate Performance Profile",
    "category": "Performance Plans",
    "panel": "2",
    "Order": "a081_",
    "Type": "300"
  },
  "WPFWinUtilShortcut": {
    "Content": "Create WinUtil Shortcut",
    "category": "Shortcuts",
    "panel": "2",
    "Order": "a082_",
    "Type": "300"
  }
}' | convertfrom-json
$inputXML =  '<Window x:Class="WinUtility.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:WinUtility"
        mc:Ignorable="d"
        Background="{MainBackgroundColor}"
        WindowStartupLocation="CenterScreen"
        UseLayoutRounding="True"
        WindowStyle="None"
        Title="Chris Titus Tech''s Windows Utility" Height="800" Width="1280">
    <WindowChrome.WindowChrome>
        <WindowChrome CaptionHeight="0" CornerRadius="10"/>
    </WindowChrome.WindowChrome>
    <Window.Resources>
    <!--Scrollbar Thumbs-->
    <Style x:Key="ScrollThumbs" TargetType="{x:Type Thumb}">
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type Thumb}">
                    <Grid x:Name="Grid">
                        <Rectangle HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Width="Auto" Height="Auto" Fill="Transparent" />
                        <Border x:Name="Rectangle1" CornerRadius="5" HorizontalAlignment="Stretch" VerticalAlignment="Stretch" Width="Auto" Height="Auto"  Background="{TemplateBinding Background}" />
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="Tag" Value="Horizontal">
                            <Setter TargetName="Rectangle1" Property="Width" Value="Auto" />
                            <Setter TargetName="Rectangle1" Property="Height" Value="7" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType="TextBlock" x:Key="HoverTextBlockStyle">
        <Setter Property="Foreground" Value="{LinkForegroundColor}" />
        <Setter Property="TextDecorations" Value="Underline" />
        <Style.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Foreground" Value="{LinkHoverForegroundColor}" />
                <Setter Property="TextDecorations" Value="Underline" />
                <Setter Property="Cursor" Value="Hand" />
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style TargetType="Button" x:Key="HoverButtonStyle">
        <Setter Property="Foreground" Value="{MainForegroundColor}" />
        <Setter Property="FontWeight" Value="Normal" />
        <Setter Property="Background" Value="{MainBackgroundColor}" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border Background="{TemplateBinding Background}">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter Property="FontWeight" Value="Bold" />
                            <Setter Property="Foreground" Value="{MainForegroundColor}" />
                            <Setter Property="Cursor" Value="Hand" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!--ScrollBars-->
    <Style x:Key="{x:Type ScrollBar}" TargetType="{x:Type ScrollBar}">
        <Setter Property="Stylus.IsFlicksEnabled" Value="false" />
        <Setter Property="Foreground" Value="{MainForegroundColor}" />
        <Setter Property="Background" Value="{MainBackgroundColor}" />
        <Setter Property="Width" Value="6" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type ScrollBar}">
                    <Grid x:Name="GridRoot" Width="7" Background="{TemplateBinding Background}" >
                        <Grid.RowDefinitions>
                            <RowDefinition Height="0.00001*" />
                        </Grid.RowDefinitions>

                        <Track x:Name="PART_Track" Grid.Row="0" IsDirectionReversed="true" Focusable="false">
                            <Track.Thumb>
                                <Thumb x:Name="Thumb" Background="{TemplateBinding Foreground}" Style="{DynamicResource ScrollThumbs}" />
                            </Track.Thumb>
                            <Track.IncreaseRepeatButton>
                                <RepeatButton x:Name="PageUp" Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="false" />
                            </Track.IncreaseRepeatButton>
                            <Track.DecreaseRepeatButton>
                                <RepeatButton x:Name="PageDown" Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="false" />
                            </Track.DecreaseRepeatButton>
                        </Track>
                    </Grid>

                    <ControlTemplate.Triggers>
                        <Trigger SourceName="Thumb" Property="IsMouseOver" Value="true">
                            <Setter Value="{ButtonBackgroundMouseoverColor}" TargetName="Thumb" Property="Background" />
                        </Trigger>
                        <Trigger SourceName="Thumb" Property="IsDragging" Value="true">
                            <Setter Value="{ButtonBackgroundSelectedColor}" TargetName="Thumb" Property="Background" />
                        </Trigger>

                        <Trigger Property="IsEnabled" Value="false">
                            <Setter TargetName="Thumb" Property="Visibility" Value="Collapsed" />
                        </Trigger>
                        <Trigger Property="Orientation" Value="Horizontal">
                            <Setter TargetName="GridRoot" Property="LayoutTransform">
                                <Setter.Value>
                                    <RotateTransform Angle="-90" />
                                </Setter.Value>
                            </Setter>
                            <Setter TargetName="PART_Track" Property="LayoutTransform">
                                <Setter.Value>
                                    <RotateTransform Angle="-90" />
                                </Setter.Value>
                            </Setter>
                            <Setter Property="Width" Value="Auto" />
                            <Setter Property="Height" Value="8" />
                            <Setter TargetName="Thumb" Property="Tag" Value="Horizontal" />
                            <Setter TargetName="PageDown" Property="Command" Value="ScrollBar.PageLeftCommand" />
                            <Setter TargetName="PageUp" Property="Command" Value="ScrollBar.PageRightCommand" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Foreground" Value="{ComboBoxForegroundColor}" />
            <Setter Property="Background" Value="{ComboBoxBackgroundColor}" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton"
                                          Background="{TemplateBinding Background}"
                                          BorderBrush="{TemplateBinding Background}"
                                          BorderThickness="0"
                                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                          ClickMode="Press">
                                <TextBlock Text="{TemplateBinding SelectionBoxItem}"
                                           Foreground="{TemplateBinding Foreground}"
                                           Background="Transparent"
                                            HorizontalAlignment="Center" VerticalAlignment="Center" Margin="2"
                                           />
                            </ToggleButton>
                            <Popup x:Name="Popup"
                                   IsOpen="{TemplateBinding IsDropDownOpen}"
                                   Placement="Bottom"
                                   Focusable="False"
                                   AllowsTransparency="True"
                                   PopupAnimation="Slide">
                                <Border x:Name="DropDownBorder"
                                        Background="{TemplateBinding Background}"
                                        BorderBrush="{TemplateBinding Foreground}"
                                        BorderThickness="1"
                                        CornerRadius="4">
                                    <ScrollViewer>
                                        <ItemsPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="2"/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="{LabelboxForegroundColor}"/>
            <Setter Property="Background" Value="{LabelBackgroundColor}"/>
        </Style>

        <!-- TextBlock template -->
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="{LabelboxForegroundColor}"/>
            <Setter Property="Background" Value="{LabelBackgroundColor}"/>
        </Style>
        <!-- Toggle button template x:Key="TabToggleButton" -->
        <Style TargetType="{x:Type ToggleButton}">
            <Setter Property="Margin" Value="{ButtonMargin}"/>
            <Setter Property="Content" Value=""/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ToggleButton">
                        <Grid>
                            <Border x:Name="ButtonGlow" 
                                        Background="{TemplateBinding Background}"
                                        BorderBrush="{ButtonForegroundColor}"
                                        BorderThickness="{ButtonBorderThickness}"
                                        CornerRadius="{ButtonCornerRadius}">
                                <Grid>
                                    <Border x:Name="BackgroundBorder"
                                        Background="{TemplateBinding Background}"
                                        BorderBrush="{ButtonBackgroundColor}"
                                        BorderThickness="{ButtonBorderThickness}"
                                        CornerRadius="{ButtonCornerRadius}">
                                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" 
                                            Margin="10,2,10,2"/>
                                    </Border>
                                </Grid>
                            </Border>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{ButtonBackgroundMouseoverColor}"/>
                                <Setter Property="Effect">
                                    <Setter.Value>
                                        <DropShadowEffect Opacity="1" ShadowDepth="5" Color="Gold" Direction="-100" BlurRadius="45"/>
                                    </Setter.Value>
                                </Setter>
                                <Setter Property="Panel.ZIndex" Value="2000"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter Property="BorderBrush" Value="Pink"/>
                                <Setter Property="BorderThickness" Value="2"/>
                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{ButtonBackgroundSelectedColor}"/>
                                <Setter Property="Effect">
                                    <Setter.Value>
                                        <DropShadowEffect Opacity="1" ShadowDepth="2" Color="Gold" Direction="-111" BlurRadius="25"/>
                                    </Setter.Value>
                                </Setter>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="False">
                                <Setter Property="BorderBrush" Value="Transparent"/>
                                <Setter Property="BorderThickness" Value="{ButtonBorderThickness}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <!-- Button Template -->
        <Style TargetType="Button">
            <Setter Property="Margin" Value="{ButtonMargin}"/>
            <Setter Property="Foreground" Value="{ButtonForegroundColor}"/>
            <Setter Property="Background" Value="{ButtonBackgroundColor}"/>
            <Setter Property="Height" Value="{ToggleButtonHeight}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Grid>
                            <Border x:Name="BackgroundBorder"
                                    Background="{TemplateBinding Background}"
                                    BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{ButtonBorderThickness}"
                                    CornerRadius="{ButtonCornerRadius}">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="10,2,10,2"/>
                            </Border>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{ButtonBackgroundPressedColor}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{ButtonBackgroundMouseoverColor}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="BackgroundBorder" Property="Background" Value="{ButtonBackgroundSelectedColor}"/>
                                <Setter Property="Foreground" Value="DimGray"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ClearButtonStyle" TargetType="Button">
            <Setter Property="FontFamily" Value="Arial"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Content" Value="X"/>
            <Setter Property="Height" Value="14"/>
            <Setter Property="Width" Value="14"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{MainForegroundColor}"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Foreground" Value="Red"/>
                    <Setter Property="Background" Value="Transparent"/>
                    <Setter Property="BorderThickness" Value="10"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <!-- Checkbox template -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="{MainForegroundColor}"/>
            <Setter Property="Background" Value="{MainBackgroundColor}"/>
            <!-- <Setter Property="FontSize" Value="15" /> -->
            <!-- <Setter Property="TextElement.FontFamily" Value="Consolas, sans-serif"/> -->
             <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Grid Background="{TemplateBinding Background}">
                            <BulletDecorator Background="Transparent">
                                <BulletDecorator.Bullet>
                                    <Grid Width="16" Height="16">
                                        <Border x:Name="Border"
                                                BorderBrush="{TemplateBinding BorderBrush}"
                                                Background="{ButtonBackgroundColor}"
                                                BorderThickness="1"
                                                Width="14"
                                                Height="14"
                                                Margin="1"
                                                SnapsToDevicePixels="True"/>
                                        <Path x:Name="CheckMark"
                                              Stroke="{TemplateBinding Foreground}"
                                              StrokeThickness="2"
                                              Data="M 0 5 L 5 10 L 12 0"
                                              Visibility="Collapsed"/>
                                    </Grid>
                                </BulletDecorator.Bullet>
                                <ContentPresenter Margin="4,0,0,0"
                                                  HorizontalAlignment="Left"
                                                  VerticalAlignment="Center"
                                                  RecognizesAccessKey="True"/>
                            </BulletDecorator>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <!--Setter TargetName="Border" Property="Background" Value="{ButtonBackgroundPressedColor}"/-->
                                <Setter Property="Foreground" Value="{ButtonBackgroundPressedColor}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                 </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ToggleSwitchStyle" TargetType="CheckBox">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel>
                            <Grid>
                                <Border Width="45"
                                        Height="20"
                                        Background="#555555"
                                        CornerRadius="10"
                                        Margin="5,0"
                                />
                                <Border Name="WPFToggleSwitchButton"
                                        Width="25"
                                        Height="25"
                                        Background="Black"
                                        CornerRadius="12.5"
                                        HorizontalAlignment="Left"
                                />
                                <ContentPresenter Name="WPFToggleSwitchContent"
                                                  Margin="10,0,0,0"
                                                  Content="{TemplateBinding Content}"
                                                  VerticalAlignment="Center"
                                />
                            </Grid>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="false">
                                <Trigger.ExitActions>
                                    <RemoveStoryboard BeginStoryboardName="WPFToggleSwitchLeft" />
                                    <BeginStoryboard x:Name="WPFToggleSwitchRight">
                                        <Storyboard>
                                            <ThicknessAnimation Storyboard.TargetProperty="Margin"
                                                    Storyboard.TargetName="WPFToggleSwitchButton"
                                                    Duration="0:0:0:0"
                                                    From="0,0,0,0"
                                                    To="28,0,0,0">
                                            </ThicknessAnimation>
                                        </Storyboard>
                                    </BeginStoryboard>
                                </Trigger.ExitActions>
                                <Setter TargetName="WPFToggleSwitchButton"
                                        Property="Background"
                                        Value="#fff9f4f4"
                                />
                            </Trigger>
                            <Trigger Property="IsChecked" Value="true">
                                <Trigger.ExitActions>
                                    <RemoveStoryboard BeginStoryboardName="WPFToggleSwitchRight" />
                                    <BeginStoryboard x:Name="WPFToggleSwitchLeft">
                                        <Storyboard>
                                            <ThicknessAnimation Storyboard.TargetProperty="Margin"
                                                    Storyboard.TargetName="WPFToggleSwitchButton"
                                                    Duration="0:0:0:0"
                                                    From="28,0,0,0"
                                                    To="0,0,0,0">
                                            </ThicknessAnimation>
                                        </Storyboard>
                                    </BeginStoryboard>
                                </Trigger.ExitActions>
                                <Setter TargetName="WPFToggleSwitchButton"
                                        Property="Background"
                                        Value="#ff060600"
                                />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ColorfulToggleSwitchStyle" TargetType="{x:Type CheckBox}">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ToggleButton}">
                        <Grid x:Name="toggleSwitch">
                            <Border x:Name="Border" CornerRadius="10"
                                    Background="#FFFFFFFF"
                                    Width="70" Height="25">
                                <Border.Effect>
                                    <DropShadowEffect ShadowDepth="0.5" Direction="0" Opacity="0.3" />
                                </Border.Effect>
                                <Ellipse x:Name="Ellipse" Fill="#FFFFFFFF" Stretch="Uniform"
                                        Margin="2 2 2 1"
                                        Stroke="Gray" StrokeThickness="0.2"
                                        HorizontalAlignment="Left" Width="22">
                                    <Ellipse.Effect>
                                        <DropShadowEffect BlurRadius="10" ShadowDepth="1" Opacity="0.3" Direction="260" />
                                    </Ellipse.Effect>
                                </Ellipse>
                            </Border>

                            <TextBlock x:Name="txtDisable" Text="Disable " VerticalAlignment="Center" FontWeight="DemiBold" HorizontalAlignment="Right" Foreground="White" FontSize="12" />
                            <TextBlock x:Name="txtEnable" Text="  Enable" VerticalAlignment="Center" FontWeight="DemiBold" Foreground="White" HorizontalAlignment="Left" FontSize="12" />
                        </Grid>

                        <ControlTemplate.Triggers>
                            <Trigger Property="ToggleButton.IsChecked" Value="False">
                                <Setter TargetName="Border" Property="Background" Value="#C2283B" />
                                <Setter TargetName="Ellipse" Property="Margin" Value="2 2 2 1" />
                                <Setter TargetName="txtDisable" Property="Opacity" Value="1.0" />
                                <Setter TargetName="txtEnable" Property="Opacity" Value="0.0" />
                            </Trigger>

                            <Trigger Property="ToggleButton.IsChecked" Value="True">
                                <Trigger.EnterActions>
                                    <BeginStoryboard>
                                        <Storyboard>
                                            <ColorAnimation Storyboard.TargetName="Border"
                                                    Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)"
                                                    To="#34A543" Duration="0:0:0.1" />

                                            <ThicknessAnimation Storyboard.TargetName="Ellipse"
                                                    Storyboard.TargetProperty="Margin"
                                                    To="46 2 2 1" Duration="0:0:0.1" />

                                            <DoubleAnimation Storyboard.TargetName="txtDisable"
                                                    Storyboard.TargetProperty="(TextBlock.Opacity)"
                                                    To="0.0" Duration="0:0:0:0.1" />

                                            <DoubleAnimation Storyboard.TargetName="txtEnable"
                                                    Storyboard.TargetProperty="(TextBlock.Opacity)"
                                                    To="1.0" Duration="0:0:0:0.1" />
                                        </Storyboard>
                                    </BeginStoryboard>
                                </Trigger.EnterActions>

                                <!-- Some out fading -->
                                <Trigger.ExitActions>
                                    <BeginStoryboard>
                                        <Storyboard>
                                            <ColorAnimation Storyboard.TargetName="Border"
                                                    Storyboard.TargetProperty="(Border.Background).(SolidColorBrush.Color)"
                                                    To="#C2283B" Duration="0:0:0.1" />

                                            <ThicknessAnimation Storyboard.TargetName="Ellipse"
                                                    Storyboard.TargetProperty="Margin"
                                                    To="2 2 2 1" Duration="0:0:0.1" />

                                            <DoubleAnimation Storyboard.TargetName="txtDisable"
                                                    Storyboard.TargetProperty="(TextBlock.Opacity)"
                                                    To="1.0" Duration="0:0:0:0.1" />

                                            <DoubleAnimation Storyboard.TargetName="txtEnable"
                                                    Storyboard.TargetProperty="(TextBlock.Opacity)"
                                                    To="0.0" Duration="0:0:0:0.1" />
                                        </Storyboard>
                                    </BeginStoryboard>
                                </Trigger.ExitActions>

                                <Setter Property="Foreground" Value="{DynamicResource IdealForegroundColorBrush}" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="VerticalContentAlignment" Value="Center" />
        </Style>
        <Style x:Key="labelfortweaks" TargetType="{x:Type Label}">
            <Setter Property="Foreground" Value="{MainForegroundColor}" />
            <Setter Property="Background" Value="{MainBackgroundColor}" />
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Foreground" Value="White" />
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="Border">
            <Setter Property="Background" Value="{MainBackgroundColor}"/>
            <Setter Property="BorderBrush" Value="{BorderColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="5"/>
            <Setter Property="Padding" Value="5"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="Effect">
                <Setter.Value>
                    <DropShadowEffect ShadowDepth="5" BlurRadius="5" Opacity="{BorderOpacity}" Color="{BorderColor}"/>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <EventTrigger RoutedEvent="Loaded">
                    <BeginStoryboard>
                        <Storyboard RepeatBehavior="Forever">
                            <!-- <DoubleAnimation
                                Storyboard.TargetProperty="Effect.(DropShadowEffect.ShadowDepth)"
                                From="6" To="15" Duration="{ShadowPulse}" AutoReverse="True"/> -->
                            <!-- <DoubleAnimation
                                Storyboard.TargetProperty="Effect.(DropShadowEffect.Direction)"
                                From="0" To="360" Duration="Forever"/> -->
                            <DoubleAnimation
                                Storyboard.TargetProperty="Effect.(DropShadowEffect.Opacity)"
                                From="0.5" To="0.94" Duration="{ShadowPulse}" AutoReverse="True"/>
                            <DoubleAnimation
                                Storyboard.TargetProperty="Effect.(DropShadowEffect.BlurRadius)"
                                From="5" To="15" Duration="{ShadowPulse}" AutoReverse="True"/>
                        </Storyboard>
                    </BeginStoryboard>
                </EventTrigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{MainBackgroundColor}"/>
            <Setter Property="BorderBrush" Value="{MainForegroundColor}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Foreground" Value="{MainForegroundColor}"/>
            <Setter Property="Padding" Value="5"/>
            <Setter Property="HorizontalAlignment" Value="Stretch"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Background="{TemplateBinding Background}" 
                                BorderBrush="{TemplateBinding BorderBrush}" 
                                BorderThickness="{TemplateBinding BorderThickness}" 
                                CornerRadius="5">
                            <Grid>
                                <ScrollViewer x:Name="PART_ContentHost" />
                            </Grid>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="Effect">
                <Setter.Value>
                    <DropShadowEffect ShadowDepth="5" BlurRadius="5" Opacity="{BorderOpacity}" Color="{BorderColor}"/>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Background="{MainBackgroundColor}" ShowGridLines="False" Name="WPFMainGrid" Width="Auto" Height="Auto" HorizontalAlignment="Stretch">
        <Grid.RowDefinitions>
            <RowDefinition Height="50px"/>
            <RowDefinition Height=".9*"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <DockPanel HorizontalAlignment="Stretch" Background="{MainBackgroundColor}" SnapsToDevicePixels="True" Grid.Row="0" Width="Auto">
            <Image Height="{ToggleButtonHeight}" Width="{ToggleButtonHeight}" Name="WPFIcon" 
                SnapsToDevicePixels="True" Source="https://christitus.com/images/logo-full.png" Margin="10"/>
            <ToggleButton HorizontalAlignment="Left" Height="{ToggleButtonHeight}" Width="100"
                Background="{ButtonInstallBackgroundColor}" Foreground="white" FontWeight="Bold" Name="WPFTab1BT">
                <ToggleButton.Content>
                    <TextBlock Background="Transparent" Foreground="{ButtonInstallForegroundColor}" >
                        <Underline>I</Underline>nstall
                    </TextBlock>
                </ToggleButton.Content>
            </ToggleButton>
            <ToggleButton HorizontalAlignment="Left" Height="{ToggleButtonHeight}" Width="100"
                Background="{ButtonTweaksBackgroundColor}" Foreground="{ButtonTweaksForegroundColor}" FontWeight="Bold" Name="WPFTab2BT">
                <ToggleButton.Content>
                    <TextBlock Background="Transparent" Foreground="{ButtonTweaksForegroundColor}">
                        <Underline>T</Underline>weaks
                    </TextBlock>
                </ToggleButton.Content>
            </ToggleButton>
            <ToggleButton HorizontalAlignment="Left" Height="{ToggleButtonHeight}" Width="100"
                Background="{ButtonConfigBackgroundColor}" Foreground="{ButtonConfigForegroundColor}" FontWeight="Bold" Name="WPFTab3BT">
                <ToggleButton.Content>
                    <TextBlock Background="Transparent" Foreground="{ButtonConfigForegroundColor}">
                        <Underline>C</Underline>onfig
                    </TextBlock>
                </ToggleButton.Content>
            </ToggleButton>
            <ToggleButton HorizontalAlignment="Left" Height="{ToggleButtonHeight}" Width="100"
                Background="{ButtonUpdatesBackgroundColor}" Foreground="{ButtonUpdatesForegroundColor}" FontWeight="Bold" Name="WPFTab4BT">
                <ToggleButton.Content>
                    <TextBlock Background="Transparent" Foreground="{ButtonUpdatesForegroundColor}">
                        <Underline>U</Underline>pdates
                    </TextBlock>
                </ToggleButton.Content>
            </ToggleButton>
            <ToggleButton HorizontalAlignment="Left" Height="{ToggleButtonHeight}" Width="100"
                Background="{ButtonUpdatesBackgroundColor}" Foreground="{ButtonUpdatesForegroundColor}" FontWeight="Bold" Name="WPFTab5BT">
                <ToggleButton.Content>
                    <TextBlock Background="Transparent" Foreground="{ButtonUpdatesForegroundColor}">
                        <Underline>M</Underline>icroWin
                    </TextBlock>
                </ToggleButton.Content>
            </ToggleButton>
            <Grid Background="{MainBackgroundColor}" ShowGridLines="False" Width="Auto" Height="Auto" HorizontalAlignment="Stretch">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="50px"/>
                    <ColumnDefinition Width="50px"/>
                </Grid.ColumnDefinitions>
                
                <TextBox
                    Grid.Column="0"
                    Width="200" 
                    FontSize="14"
                    VerticalAlignment="Center" HorizontalAlignment="Left" 
                    Height="25" Margin="10,0,0,0" BorderThickness="1" Padding="22,2,2,2"
                    Name="CheckboxFilter"
                    Foreground="{MainForegroundColor}" Background="{MainBackgroundColor}"
                    ToolTip="Press Ctrl-F and type app name to filter application list below. Press Esc to reset the filter">
                </TextBox>
                <TextBlock 
                    Grid.Column="0"
                    VerticalAlignment="Center" HorizontalAlignment="Left" 
                    FontFamily="Segoe MDL2 Assets" 
                    FontSize="14" Margin="16,0,0,0">&#xE721;</TextBlock>
                <Button Grid.Column="0" 
                    VerticalAlignment="Center" HorizontalAlignment="Left" 
                    Name="CheckboxFilterClear" 
                    Style="{StaticResource ClearButtonStyle}" 
                    Margin="193,0,0,0" Visibility="Collapsed"/>

                <Button Name="SettingsButton"
                    Style="{StaticResource HoverButtonStyle}"
                    Grid.Column="1" BorderBrush="Transparent" 
                    Background="{MainBackgroundColor}"
                    Foreground="{MainForegroundColor}"
                    FontSize="18"
                    Width="35" Height="35" 
                    HorizontalAlignment="Right" VerticalAlignment="Top" 
                    Margin="0,5,5,0" 
                    FontFamily="Segoe MDL2 Assets" 
                    Content="&#xE713;"/>
                <Popup Grid.Column="1" Name="SettingsPopup" 
                    IsOpen="False"
                    PlacementTarget="{Binding ElementName=SettingsButton}" Placement="Bottom"  
                    HorizontalAlignment="Right" VerticalAlignment="Top">
                    <Border Background="{MainBackgroundColor}" BorderBrush="{MainForegroundColor}" BorderThickness="1" CornerRadius="0" Margin="0">
                        <StackPanel Background="{MainBackgroundColor}" HorizontalAlignment="Stretch" VerticalAlignment="Stretch">
                            <MenuItem Header="Import" Name="ImportMenuItem" Foreground="{MainForegroundColor}"/>
                            <MenuItem Header="Export" Name="ExportMenuItem" Foreground="{MainForegroundColor}"/>
                            <Separator/>
                            <MenuItem Header="About" Name="AboutMenuItem" Foreground="{MainForegroundColor}"/>
                        </StackPanel>
                    </Border>
                </Popup>
 
            <Button 
                Grid.Column="2"
                Content="&#xD7;" BorderThickness="0" 
                BorderBrush="Transparent"
                Background="{MainBackgroundColor}"
                Width="35" Height="35" 
                HorizontalAlignment="Right" VerticalAlignment="Top" 
                Margin="0,5,5,0" 
                FontFamily="Arial"
                Foreground="{MainForegroundColor}" FontSize="18" Name="WPFCloseButton" />
            </Grid>
           
        </DockPanel>
       
        <TabControl Name="WPFTabNav" Background="Transparent" Width="Auto" Height="Auto" BorderBrush="Transparent" BorderThickness="0" Grid.Row="1" Grid.Column="0" Padding="-1">
            <TabItem Header="Install" Visibility="Collapsed" Name="WPFTab1">
                <Grid Background="Transparent" >
                   
                    <Grid.RowDefinitions>
                        <RowDefinition Height="45px"/>
                        <RowDefinition Height="0.95*"/>
                    </Grid.RowDefinitions>
                    <StackPanel Background="{MainBackgroundColor}" Orientation="Horizontal" Grid.Row="0" HorizontalAlignment="Left" VerticalAlignment="Top" Grid.Column="0" Grid.ColumnSpan="3" Margin="5">
                        <Button Name="WPFinstall" Content=" Install/Upgrade Selected" Margin="2" />
                        <Button Name="WPFInstallUpgrade" Content=" Upgrade All" Margin="2"/>
                        <Button Name="WPFuninstall" Content=" Uninstall Selection" Margin="2"/>
                        <Button Name="WPFGetInstalled" Content=" Get Installed" Margin="2"/>
                        <Button Name="WPFclearWinget" Content=" Clear Selection" Margin="2"/>
                    </StackPanel>

                    <ScrollViewer Grid.Row="1" Grid.Column="0" Padding="-1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" 
                        BorderBrush="Transparent" BorderThickness="0" HorizontalAlignment="Stretch" VerticalAlignment="Stretch">
                        <Grid HorizontalAlignment="Stretch" VerticalAlignment="Stretch">
                        <Grid.ColumnDefinitions>
<ColumnDefinition Width="*"/>
<ColumnDefinition Width="*"/>
<ColumnDefinition Width="*"/>
<ColumnDefinition Width="*"/>
<ColumnDefinition Width="*"/>
</Grid.ColumnDefinitions>
<Border Grid.Row="1" Grid.Column="0">
<StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
<Label Content="Browsers" FontSize="16"/>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallbrave" Content="Brave" ToolTip="Brave is a privacy-focused web browser that blocks ads and trackers, offering a faster and safer browsing experience." Margin="0,0,2,0"/><TextBlock Name="WPFInstallbraveLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.brave.com" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallchrome" Content="Chrome" ToolTip="Google Chrome is a widely used web browser known for its speed, simplicity, and seamless integration with Google services." Margin="0,0,2,0"/><TextBlock Name="WPFInstallchromeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.google.com/chrome/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallchromium" Content="Chromium" ToolTip="Chromium is the open-source project that serves as the foundation for various web browsers, including Chrome." Margin="0,0,2,0"/><TextBlock Name="WPFInstallchromiumLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/Hibbiki/chromium-win64" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalledge" Content="Edge" ToolTip="Microsoft Edge is a modern web browser built on Chromium, offering performance, security, and integration with Microsoft services." Margin="0,0,2,0"/><TextBlock Name="WPFInstalledgeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.microsoft.com/edge" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfalkon" Content="Falkon" ToolTip="Falkon is a lightweight and fast web browser with a focus on user privacy and efficiency." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfalkonLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.falkon.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfirefox" Content="Firefox" ToolTip="Mozilla Firefox is an open-source web browser known for its customization options, privacy features, and extensions." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfirefoxLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.mozilla.org/en-US/firefox/new/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfirefoxesr" Content="Firefox ESR" ToolTip="Mozilla Firefox is an open-source web browser known for its customization options, privacy features, and extensions. Firefox ESR (Extended Support Release) receives major updates every 42 weeks with minor updates such as crash fixes, security fixes and policy updates as needed, but at least every four weeks." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfirefoxesrLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.mozilla.org/en-US/firefox/enterprise/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfloorp" Content="Floorp" ToolTip="Floorp is an open-source web browser project that aims to provide a simple and fast browsing experience." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfloorpLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://floorp.app/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalllibrewolf" Content="LibreWolf" ToolTip="LibreWolf is a privacy-focused web browser based on Firefox, with additional privacy and security enhancements." Margin="0,0,2,0"/><TextBlock Name="WPFInstalllibrewolfLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://librewolf-community.gitlab.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmullvadbrowser" Content="Mullvad Browser" ToolTip="Mullvad Browser is a privacy-focused web browser, developed in partnership with the Tor Project." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmullvadbrowserLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://mullvad.net/browser" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallthorium" Content="Thorium Browser AVX2" ToolTip="Browser built for speed over vanilla chromium. It is built with AVX2 optimizations and is the fastest browser on the market." Margin="0,0,2,0"/><TextBlock Name="WPFInstallthoriumLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="http://thorium.rocks/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltor" Content="Tor Browser" ToolTip="Tor Browser is designed for anonymous web browsing, utilizing the Tor network to protect user privacy and security." Margin="0,0,2,0"/><TextBlock Name="WPFInstalltorLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.torproject.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallungoogled" Content="Ungoogled" ToolTip="Ungoogled Chromium is a version of Chromium without Google&#39;s integration for enhanced privacy and control." Margin="0,0,2,0"/><TextBlock Name="WPFInstallungoogledLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/Eloston/ungoogled-chromium" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvivaldi" Content="Vivaldi" ToolTip="Vivaldi is a highly customizable web browser with a focus on user personalization and productivity features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvivaldiLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://vivaldi.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwaterfox" Content="Waterfox" ToolTip="Waterfox is a fast, privacy-focused web browser based on Firefox, designed to preserve user choice and privacy." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwaterfoxLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.waterfox.net/" />
</StackPanel>
<Label Content="Communications" FontSize="16"/>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallchatterino" Content="Chatterino" ToolTip="Chatterino is a chat client for Twitch chat that offers a clean and customizable interface for a better streaming experience." Margin="0,0,2,0"/><TextBlock Name="WPFInstallchatterinoLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.chatterino.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldiscord" Content="Discord" ToolTip="Discord is a popular communication platform with voice, video, and text chat, designed for gamers but used by a wide range of communities." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldiscordLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://discord.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallferdium" Content="Ferdium" ToolTip="Ferdium is a messaging application that combines multiple messaging services into a single app for easy management." Margin="0,0,2,0"/><TextBlock Name="WPFInstallferdiumLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://ferdium.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallguilded" Content="Guilded" ToolTip="Guilded is a communication and productivity platform that includes chat, scheduling, and collaborative tools for gaming and communities." Margin="0,0,2,0"/><TextBlock Name="WPFInstallguildedLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.guilded.gg/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallhexchat" Content="Hexchat" ToolTip="HexChat is a free, open-source IRC (Internet Relay Chat) client with a graphical interface for easy communication." Margin="0,0,2,0"/><TextBlock Name="WPFInstallhexchatLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://hexchat.github.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljami" Content="Jami" ToolTip="Jami is a secure and privacy-focused communication platform that offers audio and video calls, messaging, and file sharing." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljamiLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://jami.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalllinphone" Content="Linphone" ToolTip="Linphone is an open-source voice over IP (VoIPservice that allows for audio and video calls, messaging, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstalllinphoneLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.linphone.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmatrix" Content="Matrix" ToolTip="Matrix is an open network for secure, decentralized communication with features like chat, VoIP, and collaboration tools." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmatrixLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://element.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallqtox" Content="QTox" ToolTip="QTox is a free and open-source messaging app that prioritizes user privacy and security in its design." Margin="0,0,2,0"/><TextBlock Name="WPFInstallqtoxLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://qtox.github.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallrevolt" Content="Revolt" ToolTip="Find your community, connect with the world. Revolt is one of the best ways to stay connected with your friends and community without sacrificing any usability." Margin="0,0,2,0"/><TextBlock Name="WPFInstallrevoltLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://revolt.chat/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsession" Content="Session" ToolTip="Session is a private and secure messaging app built on a decentralized network for user privacy and data protection." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsessionLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://getsession.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsignal" Content="Signal" ToolTip="Signal is a privacy-focused messaging app that offers end-to-end encryption for secure and private communication." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsignalLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://signal.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallskype" Content="Skype" ToolTip="Skype is a widely used communication platform offering video calls, voice calls, and instant messaging services." Margin="0,0,2,0"/><TextBlock Name="WPFInstallskypeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.skype.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallslack" Content="Slack" ToolTip="Slack is a collaboration hub that connects teams and facilitates communication through channels, messaging, and file sharing." Margin="0,0,2,0"/><TextBlock Name="WPFInstallslackLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://slack.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallteams" Content="Teams" ToolTip="Microsoft Teams is a collaboration platform that integrates with Office 365 and offers chat, video conferencing, file sharing, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallteamsLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.microsoft.com/en-us/microsoft-teams/group-chat-software" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltelegram" Content="Telegram" ToolTip="Telegram is a cloud-based instant messaging app known for its security features, speed, and simplicity." Margin="0,0,2,0"/><TextBlock Name="WPFInstalltelegramLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://telegram.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallthunderbird" Content="Thunderbird" ToolTip="Mozilla Thunderbird is a free and open-source email client, news client, and chat client with advanced features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallthunderbirdLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.thunderbird.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallunigram" Content="Unigram" ToolTip="Unigram - Telegram for Windows" Margin="0,0,2,0"/><TextBlock Name="WPFInstallunigramLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://unigramdev.github.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvencord" Content="Vencord" ToolTip="Vencord is a modification for Discord that adds plugins, custom styles, and more!" Margin="0,0,2,0"/><TextBlock Name="WPFInstallvencordLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://vencord.dev/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvesktop" Content="Vesktop" ToolTip="A cross platform electron-based desktop app aiming to give you a snappier Discord experience with Vencord pre-installed." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvesktopLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/Vencord/Vesktop" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallviber" Content="Viber" ToolTip="Viber is a free messaging and calling app with features like group chats, video calls, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallviberLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.viber.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwhatsapp" Content="Whatsapp" ToolTip="WhatsApp Desktop is a desktop version of the popular messaging app, allowing users to send and receive messages, share files, and connect with contacts from their computer." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwhatsappLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.whatsapp.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallzoom" Content="Zoom" ToolTip="Zoom is a popular video conferencing and web conferencing service for online meetings, webinars, and collaborative projects." Margin="0,0,2,0"/><TextBlock Name="WPFInstallzoomLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://zoom.us/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallzulip" Content="Zulip" ToolTip="Zulip is an open-source team collaboration tool with chat streams for productive and organized communication." Margin="0,0,2,0"/><TextBlock Name="WPFInstallzulipLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://zulipchat.com/" />
</StackPanel>
<Label Content="Development" FontSize="16"/>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallanaconda3" Content="Anaconda" ToolTip="Anaconda is a distribution of the Python and R programming languages for scientific computing." Margin="0,0,2,0"/><TextBlock Name="WPFInstallanaconda3Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.anaconda.com/products/distribution" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallclink" Content="Clink" ToolTip="Clink is a powerful Bash-compatible command-line interface (CLIenhancement for Windows, adding features like syntax highlighting and improved history)." Margin="0,0,2,0"/><TextBlock Name="WPFInstallclinkLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://mridgers.github.io/clink/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallcmake" Content="CMake" ToolTip="CMake is an open-source, cross-platform family of tools designed to build, test and package software." Margin="0,0,2,0"/><TextBlock Name="WPFInstallcmakeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://cmake.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallDaxStudio" Content="DaxStudio" ToolTip="DAX (Data Analysis eXpressions) Studio is the ultimate tool for executing and analyzing DAX queries against Microsoft Tabular models." Margin="0,0,2,0"/><TextBlock Name="WPFInstallDaxStudioLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://daxstudio.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldockerdesktop" Content="Docker Desktop" ToolTip="Docker Desktop is a powerful tool for containerized application development and deployment." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldockerdesktopLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.docker.com/products/docker-desktop" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgit" Content="Git" ToolTip="Git is a distributed version control system widely used for tracking changes in source code during software development." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgitLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://git-scm.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgitextensions" Content="Git Extensions" ToolTip="Git Extensions is a graphical user interface for Git, providing additional features for easier source code management." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgitextensionsLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://gitextensions.github.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgithubcli" Content="GitHub CLI" ToolTip="GitHub CLI is a command-line tool that simplifies working with GitHub directly from the terminal." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgithubcliLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://cli.github.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgithubdesktop" Content="GitHub Desktop" ToolTip="GitHub Desktop is a visual Git client that simplifies collaboration on GitHub repositories with an easy-to-use interface." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgithubdesktopLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://desktop.github.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgolang" Content="GoLang" ToolTip="GoLang (or Golang) is a statically typed, compiled programming language designed for simplicity, reliability, and efficiency." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgolangLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://golang.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallhelix" Content="Helix" ToolTip="Helix is a neovim alternative built in rust." Margin="0,0,2,0"/><TextBlock Name="WPFInstallhelixLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://helix-editor.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljava11runtime" Content="Eclipse Temurin JRE 11" ToolTip="Eclipse Temurin JRE is the open source Java SE build based upon OpenJRE." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljava11runtimeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://adoptium.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljava16" Content="OpenJDK Java 16" ToolTip="OpenJDK Java 16 is the latest version of the open-source Java development kit." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljava16Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://adoptopenjdk.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljava17runtime" Content="Eclipse Temurin JRE 17" ToolTip="Eclipse Temurin JRE is the open source Java SE build based upon OpenJRE." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljava17runtimeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://adoptium.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljava18" Content="Oracle Java 18" ToolTip="Oracle Java 18 is the latest version of the official Java development kit from Oracle." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljava18Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.oracle.com/java/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljava18runtime" Content="Eclipse Temurin JRE 18" ToolTip="Eclipse Temurin JRE is the open source Java SE build based upon OpenJRE." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljava18runtimeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://adoptium.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljava19runtime" Content="Eclipse Temurin JRE 19" ToolTip="Eclipse Temurin JRE is the open source Java SE build based upon OpenJRE." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljava19runtimeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://adoptium.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljava20" Content="Azul Zulu JDK 20" ToolTip="Azul Zulu JDK 20 is a distribution of the OpenJDK with long-term support, performance enhancements, and security updates." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljava20Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.azul.com/downloads/zulu-community/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljava21" Content="Azul Zulu JDK 21" ToolTip="Azul Zulu JDK 21 is a distribution of the OpenJDK with long-term support, performance enhancements, and security updates." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljava21Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.azul.com/downloads/zulu-community/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljava8" Content="OpenJDK Java 8" ToolTip="OpenJDK Java 8 is an open-source implementation of the Java Platform, Standard Edition." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljava8Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://adoptopenjdk.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljetbrains" Content="Jetbrains Toolbox" ToolTip="Jetbrains Toolbox is a platform for easy installation and management of JetBrains developer tools." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljetbrainsLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.jetbrains.com/toolbox/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalllazygit" Content="Lazygit" ToolTip="Simple terminal UI for git commands" Margin="0,0,2,0"/><TextBlock Name="WPFInstalllazygitLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/jesseduffield/lazygit/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallminiconda" Content="Miniconda" ToolTip="Miniconda is a free minimal installer for conda. It is a small bootstrap version of Anaconda that includes only conda, Python, the packages they both depend on, and a small number of other useful packages (like pip, zlib, and a few others)." Margin="0,0,2,0"/><TextBlock Name="WPFInstallminicondaLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://docs.conda.io/projects/miniconda" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallneovim" Content="Neovim" ToolTip="Neovim is a highly extensible text editor and an improvement over the original Vim editor." Margin="0,0,2,0"/><TextBlock Name="WPFInstallneovimLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://neovim.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnodejs" Content="NodeJS" ToolTip="NodeJS is a JavaScript runtime built on Chrome&#39;s V8 JavaScript engine for building server-side and networking applications." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnodejsLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://nodejs.org/" />
</StackPanel>

</StackPanel>
</Border>
<Border Grid.Row="1" Grid.Column="1">
<StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnodejslts" Content="NodeJS LTS" ToolTip="NodeJS LTS provides Long-Term Support releases for stable and reliable server-side JavaScript development." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnodejsltsLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://nodejs.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnvm" Content="Node Version Manager" ToolTip="Node Version Manager (NVM) for Windows allows you to easily switch between multiple Node.js versions." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnvmLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/coreybutler/nvm-windows" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallposh" Content="Oh My Posh (Prompt)" ToolTip="Oh My Posh is a cross-platform prompt theme engine for any shell." Margin="0,0,2,0"/><TextBlock Name="WPFInstallposhLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://ohmyposh.dev/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpostman" Content="Postman" ToolTip="Postman is a collaboration platform for API development that simplifies the process of developing APIs." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpostmanLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.postman.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpyenvwin" Content="Python Version Manager (pyenv-win)" ToolTip="pyenv for Windows is a simple python version management tool. It lets you easily switch between multiple versions of Python." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpyenvwinLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://pyenv-win.github.io/pyenv-win/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpython3" Content="Python3" ToolTip="Python is a versatile programming language used for web development, data analysis, artificial intelligence, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpython3Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.python.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallrustlang" Content="Rust" ToolTip="Rust is a programming language designed for safety and performance, particularly focused on systems programming." Margin="0,0,2,0"/><TextBlock Name="WPFInstallrustlangLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.rust-lang.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallstarship" Content="Starship (Shell Prompt)" ToolTip="Starship is a minimal, fast, and customizable prompt for any shell." Margin="0,0,2,0"/><TextBlock Name="WPFInstallstarshipLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://starship.rs/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsublimemerge" Content="Sublime Merge" ToolTip="Sublime Merge is a Git client with advanced features and a beautiful interface." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsublimemergeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.sublimemerge.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsublimetext" Content="Sublime Text" ToolTip="Sublime Text is a sophisticated text editor for code, markup, and prose." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsublimetextLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.sublimetext.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallswift" Content="Swift toolchain" ToolTip="Swift is a general-purpose programming language that&#39;s approachable for newcomers and powerful for experts." Margin="0,0,2,0"/><TextBlock Name="WPFInstallswiftLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.swift.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltemurin" Content="Eclipse Temurin" ToolTip="Eclipse Temurin is the open source Java SE build based upon OpenJDK." Margin="0,0,2,0"/><TextBlock Name="WPFInstalltemurinLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://adoptium.net/temurin/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallThonny" Content="Thonny Python IDE" ToolTip="Python IDE for beginners." Margin="0,0,2,0"/><TextBlock Name="WPFInstallThonnyLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/thonny/thonny" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallunity" Content="Unity Game Engine" ToolTip="Unity is a powerful game development platform for creating 2D, 3D, augmented reality, and virtual reality games." Margin="0,0,2,0"/><TextBlock Name="WPFInstallunityLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://unity.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvagrant" Content="Vagrant" ToolTip="Vagrant is an open-source tool for building and managing virtualized development environments." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvagrantLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.vagrantup.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvisualstudio" Content="Visual Studio 2022" ToolTip="Visual Studio 2022 is an integrated development environment (IDE) for building, debugging, and deploying applications." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvisualstudioLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://visualstudio.microsoft.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvscode" Content="VS Code" ToolTip="Visual Studio Code is a free, open-source code editor with support for multiple programming languages." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvscodeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://code.visualstudio.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvscodium" Content="VS Codium" ToolTip="VSCodium is a community-driven, freely-licensed binary distribution of Microsoft&#39;s VS Code." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvscodiumLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://vscodium.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwezterm" Content="Wezterm" ToolTip="WezTerm is a powerful cross-platform terminal emulator and multiplexer" Margin="0,0,2,0"/><TextBlock Name="WPFInstallweztermLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://wezfurlong.org/wezterm/index.html" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallyarn" Content="Yarn" ToolTip="Yarn is a fast, reliable, and secure dependency management tool for JavaScript projects." Margin="0,0,2,0"/><TextBlock Name="WPFInstallyarnLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://yarnpkg.com/" />
</StackPanel>
<Label Content="Document" FontSize="16"/>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalladobe" Content="Adobe Acrobat Reader" ToolTip="Adobe Acrobat Reader is a free PDF viewer with essential features for viewing, printing, and annotating PDF documents." Margin="0,0,2,0"/><TextBlock Name="WPFInstalladobeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.adobe.com/acrobat/pdf-reader.html" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallanki" Content="Anki" ToolTip="Anki is a flashcard application that helps you memorize information with intelligent spaced repetition." Margin="0,0,2,0"/><TextBlock Name="WPFInstallankiLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://apps.ankiweb.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallcalibre" Content="Calibre" ToolTip="Calibre is a powerful and easy-to-use e-book manager, viewer, and converter." Margin="0,0,2,0"/><TextBlock Name="WPFInstallcalibreLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://calibre-ebook.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfoxpdfeditor" Content="Foxit PDF Editor" ToolTip="Foxit PDF Editor is a feature-rich PDF editor and viewer with a familiar ribbon-style interface." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfoxpdfeditorLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.foxit.com/pdf-editor/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfoxpdfreader" Content="Foxit PDF Reader" ToolTip="Foxit PDF Reader is a free PDF viewer with a familiar ribbon-style interface." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfoxpdfreaderLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.foxit.com/pdf-reader/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljoplin" Content="Joplin (FOSS Notes)" ToolTip="Joplin is an open-source note-taking and to-do application with synchronization capabilities." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljoplinLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://joplinapp.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalllibreoffice" Content="LibreOffice" ToolTip="LibreOffice is a powerful and free office suite, compatible with other major office suites." Margin="0,0,2,0"/><TextBlock Name="WPFInstalllibreofficeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.libreoffice.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalllogseq" Content="Logseq" ToolTip="Logseq is a versatile knowledge management and note-taking application designed for the digital thinker. With a focus on the interconnectedness of ideas, Logseq allows users to seamlessly organize their thoughts through a combination of hierarchical outlines and bi-directional linking. It supports both structured and unstructured content, enabling users to create a personalized knowledge graph that adapts to their evolving ideas and insights." Margin="0,0,2,0"/><TextBlock Name="WPFInstalllogseqLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://logseq.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmasscode" Content="massCode (Snippet Manager)" ToolTip="massCode is a fast and efficient open-source code snippet manager for developers." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmasscodeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://masscode.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnaps2" Content="NAPS2 (Document Scanner)" ToolTip="NAPS2 is a document scanning application that simplifies the process of creating electronic documents." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnaps2Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.naps2.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnotepadplus" Content="Notepad++" ToolTip="Notepad++ is a free, open-source code editor and Notepad replacement with support for multiple languages." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnotepadplusLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://notepad-plus-plus.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallobsidian" Content="Obsidian" ToolTip="Obsidian is a powerful note-taking and knowledge management application." Margin="0,0,2,0"/><TextBlock Name="WPFInstallobsidianLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://obsidian.md/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallokular" Content="Okular" ToolTip="Okular is a versatile document viewer with advanced features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallokularLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://okular.kde.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallonlyoffice" Content="ONLYOffice Desktop" ToolTip="ONLYOffice Desktop is a comprehensive office suite for document editing and collaboration." Margin="0,0,2,0"/><TextBlock Name="WPFInstallonlyofficeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.onlyoffice.com/desktop.aspx" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallopenoffice" Content="Apache OpenOffice" ToolTip="Apache OpenOffice is an open-source office software suite for word processing, spreadsheets, presentations, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallopenofficeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.openoffice.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpdf24creator" Content="PDF24 creator" ToolTip="Free and easy-to-use online/desktop PDF tools that make you more productive" Margin="0,0,2,0"/><TextBlock Name="WPFInstallpdf24creatorLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://tools.pdf24.org/en/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpdfgear" Content="PDFgear" ToolTip="PDFgear is a piece of full-featured PDF management software for Windows, Mac, and mobile, and it&#39;s completely free to use." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpdfgearLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.pdfgear.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpdfsam" Content="PDFsam Basic" ToolTip="PDFsam Basic is a free and open-source tool for splitting, merging, and rotating PDF files." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpdfsamLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://pdfsam.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsimplenote" Content="simplenote" ToolTip="Simplenote is an easy way to keep notes, lists, ideas and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsimplenoteLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://simplenote.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsumatra" Content="Sumatra PDF" ToolTip="Sumatra PDF is a lightweight and fast PDF viewer with minimalistic design." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsumatraLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.sumatrapdfreader.org/free-pdf-reader.html" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwinmerge" Content="WinMerge" ToolTip="WinMerge is a visual text file and directory comparison tool for Windows." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwinmergeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://winmerge.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallxournal" Content="Xournal++" ToolTip="Xournal++ is an open-source handwriting notetaking software with PDF annotation capabilities." Margin="0,0,2,0"/><TextBlock Name="WPFInstallxournalLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://xournalpp.github.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallzim" Content="Zim Desktop Wiki" ToolTip="Zim Desktop Wiki is a graphical text editor used to maintain a collection of wiki pages." Margin="0,0,2,0"/><TextBlock Name="WPFInstallzimLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://zim-wiki.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallznote" Content="Znote" ToolTip="Znote is a note-taking application." Margin="0,0,2,0"/><TextBlock Name="WPFInstallznoteLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://znote.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallzotero" Content="Zotero" ToolTip="Zotero is a free, easy-to-use tool to help you collect, organize, cite, and share your research materials." Margin="0,0,2,0"/><TextBlock Name="WPFInstallzoteroLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.zotero.org/" />
</StackPanel>
<Label Content="Games" FontSize="16"/>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallATLauncher" Content="ATLauncher" ToolTip="ATLauncher is a Launcher for Minecraft which integrates multiple different ModPacks to allow you to download and install ModPacks easily and quickly." Margin="0,0,2,0"/><TextBlock Name="WPFInstallATLauncherLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/ATLauncher/ATLauncher" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallbluestacks" Content="Bluestacks" ToolTip="Bluestacks is an Android emulator for running mobile apps and games on a PC." Margin="0,0,2,0"/><TextBlock Name="WPFInstallbluestacksLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.bluestacks.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallcemu" Content="Cemu" ToolTip="Cemu is a highly experimental software to emulate Wii U applications on PC." Margin="0,0,2,0"/><TextBlock Name="WPFInstallcemuLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://cemu.info/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallclonehero" Content="Clone Hero" ToolTip="Clone Hero is a free rhythm game, which can be played with any 5 or 6 button guitar controller." Margin="0,0,2,0"/><TextBlock Name="WPFInstallcloneheroLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://clonehero.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalleaapp" Content="EA App" ToolTip="EA App is a platform for accessing and playing Electronic Arts games." Margin="0,0,2,0"/><TextBlock Name="WPFInstalleaappLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.ea.com/ea-app" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallemulationstation" Content="Emulation Station" ToolTip="Emulation Station is a graphical and themeable emulator front-end that allows you to access all your favorite games in one place." Margin="0,0,2,0"/><TextBlock Name="WPFInstallemulationstationLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://emulationstation.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallepicgames" Content="Epic Games Launcher" ToolTip="Epic Games Launcher is the client for accessing and playing games from the Epic Games Store." Margin="0,0,2,0"/><TextBlock Name="WPFInstallepicgamesLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.epicgames.com/store/en-US/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgeforcenow" Content="GeForce NOW" ToolTip="GeForce NOW is a cloud gaming service that allows you to play high-quality PC games on your device." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgeforcenowLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.nvidia.com/en-us/geforce-now/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgog" Content="GOG Galaxy" ToolTip="GOG Galaxy is a gaming client that offers DRM-free games, additional content, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgogLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.gog.com/galaxy" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallheroiclauncher" Content="Heroic Games Launcher" ToolTip="Heroic Games Launcher is an open-source alternative game launcher for Epic Games Store." Margin="0,0,2,0"/><TextBlock Name="WPFInstallheroiclauncherLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://heroicgameslauncher.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallitch" Content="Itch.io" ToolTip="Itch.io is a digital distribution platform for indie games and creative projects." Margin="0,0,2,0"/><TextBlock Name="WPFInstallitchLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://itch.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmoonlight" Content="Moonlight/GameStream Client" ToolTip="Moonlight/GameStream Client allows you to stream PC games to other devices over your local network." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmoonlightLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://moonlight-stream.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallplaynite" Content="Playnite" ToolTip="Playnite is an open-source video game library manager with one simple goal: To provide a unified interface for all of your games." Margin="0,0,2,0"/><TextBlock Name="WPFInstallplayniteLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://playnite.link/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallprismlauncher" Content="Prism Launcher" ToolTip="Prism Launcher is a game launcher and manager designed to provide a clean and intuitive interface for organizing and launching your games." Margin="0,0,2,0"/><TextBlock Name="WPFInstallprismlauncherLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://prismlauncher.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpsremoteplay" Content="PS Remote Play" ToolTip="PS Remote Play is a free application that allows you to stream games from your PlayStation console to a PC or mobile device." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpsremoteplayLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://remoteplay.dl.playstation.net/remoteplay/lang/gb/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsidequest" Content="SideQuestVR" ToolTip="SideQuestVR is a community-driven platform that enables users to discover, install, and manage virtual reality content on Oculus Quest devices." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsidequestLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://sidequestvr.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsteam" Content="Steam" ToolTip="Steam is a digital distribution platform for purchasing and playing video games, offering multiplayer gaming, video streaming, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsteamLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://store.steampowered.com/about/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsunshine" Content="Sunshine/GameStream Server" ToolTip="Sunshine is a GameStream server that allows you to remotely play PC games on Android devices, offering low-latency streaming." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsunshineLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/LizardByte/Sunshine" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallTcNoAccSwitcher" Content="TCNO Account Switcher" ToolTip="A Super-fast account switcher for Steam, Battle.net, Epic Games, Origin, Riot, Ubisoft and many others!" Margin="0,0,2,0"/><TextBlock Name="WPFInstallTcNoAccSwitcherLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/TCNOco/TcNo-Acc-Switcher" />
</StackPanel>

</StackPanel>
</Border>
<Border Grid.Row="1" Grid.Column="2">
<StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallubisoft" Content="Ubisoft Connect" ToolTip="Ubisoft Connect is Ubisoft&#39;s digital distribution and online gaming service, providing access to Ubisoft&#39;s games and services." Margin="0,0,2,0"/><TextBlock Name="WPFInstallubisoftLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://ubisoftconnect.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvrdesktopstreamer" Content="Virtual Desktop Streamer" ToolTip="Virtual Desktop Streamer is a tool that allows you to stream your desktop screen to VR devices." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvrdesktopstreamerLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.vrdesktop.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallxemu" Content="XEMU" ToolTip="XEMU is an open-source Xbox emulator that allows you to play Xbox games on your PC, aiming for accuracy and compatibility." Margin="0,0,2,0"/><TextBlock Name="WPFInstallxemuLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://xemu.app/" />
</StackPanel>
<Label Content="Microsoft Tools" FontSize="16"/>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallautoruns" Content="Autoruns" ToolTip="This utility shows you what programs are configured to run during system bootup or login" Margin="0,0,2,0"/><TextBlock Name="WPFInstallautorunsLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallazuredatastudio" Content="Microsoft Azure Data Studio" ToolTip="Azure Data Studio is a data management tool that enables you to work with SQL Server, Azure SQL DB and SQL DW from Windows, macOS and Linux." Margin="0,0,2,0"/><TextBlock Name="WPFInstallazuredatastudioLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://docs.microsoft.com/sql/azure-data-studio/what-is-azure-data-studio" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldotnet3" Content=".NET Desktop Runtime 3.1" ToolTip=".NET Desktop Runtime 3.1 is a runtime environment required for running applications developed with .NET Core 3.1." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldotnet3Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://dotnet.microsoft.com/download/dotnet/3.1" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldotnet5" Content=".NET Desktop Runtime 5" ToolTip=".NET Desktop Runtime 5 is a runtime environment required for running applications developed with .NET 5." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldotnet5Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://dotnet.microsoft.com/download/dotnet/5.0" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldotnet6" Content=".NET Desktop Runtime 6" ToolTip=".NET Desktop Runtime 6 is a runtime environment required for running applications developed with .NET 6." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldotnet6Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://dotnet.microsoft.com/download/dotnet/6.0" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldotnet7" Content=".NET Desktop Runtime 7" ToolTip=".NET Desktop Runtime 7 is a runtime environment required for running applications developed with .NET 7." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldotnet7Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://dotnet.microsoft.com/download/dotnet/7.0" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldotnet8" Content=".NET Desktop Runtime 8" ToolTip=".NET Desktop Runtime 8 is a runtime environment required for running applications developed with .NET 8." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldotnet8Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://dotnet.microsoft.com/download/dotnet/8.0" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnuget" Content="NuGet" ToolTip="NuGet is a package manager for the .NET framework, enabling developers to manage and share libraries in their .NET applications." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnugetLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.nuget.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallonedrive" Content="OneDrive" ToolTip="OneDrive is a cloud storage service provided by Microsoft, allowing users to store and share files securely across devices." Margin="0,0,2,0"/><TextBlock Name="WPFInstallonedriveLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://onedrive.live.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpowerautomate" Content="Power Automate" ToolTip="Using Power Automate Desktop you can automate tasks on the desktop as well as the Web." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpowerautomateLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.microsoft.com/en-us/power-platform/products/power-automate" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpowerbi" Content="Power BI" ToolTip="Create stunning reports and visualizations with Power BI Desktop. It puts visual analytics at your fingertips with intuitive report authoring. Drag-and-drop to place content exactly where you want it on the flexible and fluid canvas. Quickly discover patterns as you explore a single unified view of linked, interactive visualizations." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpowerbiLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.microsoft.com/en-us/power-platform/products/power-bi/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpowershell" Content="PowerShell" ToolTip="PowerShell is a task automation framework and scripting language designed for system administrators, offering powerful command-line capabilities." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpowershellLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/PowerShell/PowerShell" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpowertoys" Content="PowerToys" ToolTip="PowerToys is a set of utilities for power users to enhance productivity, featuring tools like FancyZones, PowerRename, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpowertoysLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/microsoft/PowerToys" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallprocessmonitor" Content="SysInternals Process Monitor" ToolTip="SysInternals Process Monitor is an advanced monitoring tool that shows real-time file system, registry, and process/thread activity." Margin="0,0,2,0"/><TextBlock Name="WPFInstallprocessmonitorLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://docs.microsoft.com/en-us/sysinternals/downloads/procmon" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsqlmanagementstudio" Content="Microsoft SQL Server Management Studio" ToolTip="SQL Server Management Studio (SSMS) is an integrated environment for managing any SQL infrastructure, from SQL Server to Azure SQL Database. SSMS provides tools to configure, monitor, and administer instances of SQL Server and databases." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsqlmanagementstudioLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://learn.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms?view=sql-server-ver16" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltcpview" Content="SysInternals TCPView" ToolTip="SysInternals TCPView is a network monitoring tool that displays a detailed list of all TCP and UDP endpoints on your system." Margin="0,0,2,0"/><TextBlock Name="WPFInstalltcpviewLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://docs.microsoft.com/en-us/sysinternals/downloads/tcpview" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallterminal" Content="Windows Terminal" ToolTip="Windows Terminal is a modern, fast, and efficient terminal application for command-line users, supporting multiple tabs, panes, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallterminalLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://aka.ms/terminal" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvc2015_32" Content="Visual C++ 2015-2022 32-bit" ToolTip="Visual C++ 2015-2022 32-bit redistributable package installs runtime components of Visual C++ libraries required to run 32-bit applications." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvc2015_32Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvc2015_64" Content="Visual C++ 2015-2022 64-bit" ToolTip="Visual C++ 2015-2022 64-bit redistributable package installs runtime components of Visual C++ libraries required to run 64-bit applications." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvc2015_64Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads" />
</StackPanel>
<Label Content="Multimedia Tools" FontSize="16"/>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallaimp" Content="AIMP (Music Player)" ToolTip="AIMP is a feature-rich music player with support for various audio formats, playlists, and customizable user interface." Margin="0,0,2,0"/><TextBlock Name="WPFInstallaimpLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.aimp.ru/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallaudacity" Content="Audacity" ToolTip="Audacity is a free and open-source audio editing software known for its powerful recording and editing capabilities." Margin="0,0,2,0"/><TextBlock Name="WPFInstallaudacityLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.audacityteam.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallblender" Content="Blender (3D Graphics)" ToolTip="Blender is a powerful open-source 3D creation suite, offering modeling, sculpting, animation, and rendering tools." Margin="0,0,2,0"/><TextBlock Name="WPFInstallblenderLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.blender.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallclementine" Content="Clementine" ToolTip="Clementine is a modern music player and library organizer, supporting various audio formats and online radio services." Margin="0,0,2,0"/><TextBlock Name="WPFInstallclementineLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.clementine-player.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldarktable" Content="darktable" ToolTip="Open-source photo editing tool, offering an intuitive interface, advanced editing capabilities, and a non-destructive workflow for seamless image enhancement." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldarktableLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.darktable.org/install/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldigikam" Content="digiKam" ToolTip="digiKam is an advanced open-source photo management software with features for organizing, editing, and sharing photos." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldigikamLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.digikam.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalleartrumpet" Content="EarTrumpet (Audio)" ToolTip="EarTrumpet is an audio control app for Windows, providing a simple and intuitive interface for managing sound settings." Margin="0,0,2,0"/><TextBlock Name="WPFInstalleartrumpetLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://eartrumpet.app/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallffmpeg" Content="FFmpeg (full)" ToolTip="FFmpeg is a powerful multimedia processing tool that enables users to convert, edit, and stream audio and video files with a vast range of codecs and formats." Margin="0,0,2,0"/><TextBlock Name="WPFInstallffmpegLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://ffmpeg.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfirealpaca" Content="Fire Alpaca" ToolTip="Fire Alpaca is a free digital painting software that provides a wide range of drawing tools and a user-friendly interface." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfirealpacaLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://firealpaca.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallflameshot" Content="Flameshot (Screenshots)" ToolTip="Flameshot is a powerful yet simple to use screenshot software, offering annotation and editing features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallflameshotLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://flameshot.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfoobar" Content="foobar2000 (Music Player)" ToolTip="foobar2000 is a highly customizable and extensible music player for Windows, known for its modular design and advanced features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfoobarLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.foobar2000.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfreecad" Content="FreeCAD" ToolTip="FreeCAD is a parametric 3D CAD modeler, designed for product design and engineering tasks, with a focus on flexibility and extensibility." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfreecadLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.freecadweb.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfxsound" Content="FxSound" ToolTip="FxSound is a cutting-edge audio enhancement software that elevates your listening experience across all media." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfxsoundLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.fxsound.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgimp" Content="GIMP (Image Editor)" ToolTip="GIMP is a versatile open-source raster graphics editor used for tasks such as photo retouching, image editing, and image composition." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgimpLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.gimp.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgreenshot" Content="Greenshot (Screenshots)" ToolTip="Greenshot is a light-weight screenshot software tool with built-in image editor and customizable capture options." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgreenshotLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://getgreenshot.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallhandbrake" Content="HandBrake" ToolTip="HandBrake is an open-source video transcoder, allowing you to convert video from nearly any format to a selection of widely supported codecs." Margin="0,0,2,0"/><TextBlock Name="WPFInstallhandbrakeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://handbrake.fr/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallharmonoid" Content="Harmonoid" ToolTip="Plays and manages your music library. Looks beautiful and juicy. Playlists, visuals, synced lyrics, pitch shift, volume boost and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallharmonoidLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://harmonoid.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallimageglass" Content="ImageGlass (Image Viewer)" ToolTip="ImageGlass is a versatile image viewer with support for various image formats and a focus on simplicity and speed." Margin="0,0,2,0"/><TextBlock Name="WPFInstallimageglassLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://imageglass.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallimgburn" Content="ImgBurn" ToolTip="ImgBurn is a lightweight CD, DVD, HD-DVD, and Blu-ray burning application with advanced features for creating and burning disc images." Margin="0,0,2,0"/><TextBlock Name="WPFInstallimgburnLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="http://www.imgburn.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallinkscape" Content="Inkscape" ToolTip="Inkscape is a powerful open-source vector graphics editor, suitable for tasks such as illustrations, icons, logos, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallinkscapeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://inkscape.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallitunes" Content="iTunes" ToolTip="iTunes is a media player, media library, and online radio broadcaster application developed by Apple Inc." Margin="0,0,2,0"/><TextBlock Name="WPFInstallitunesLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.apple.com/itunes/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljellyfinmediaplayer" Content="Jellyfin Media Player" ToolTip="Jellyfin Media Player is a client application for the Jellyfin media server, providing access to your media library." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljellyfinmediaplayerLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/jellyfin/jellyfin-media-playerf" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljellyfinserver" Content="Jellyfin Server" ToolTip="Jellyfin Server is an open-source media server software, allowing you to organize and stream your media library." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljellyfinserverLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://jellyfin.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallkdenlive" Content="Kdenlive (Video Editor)" ToolTip="Kdenlive is an open-source video editing software with powerful features for creating and editing professional-quality videos." Margin="0,0,2,0"/><TextBlock Name="WPFInstallkdenliveLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://kdenlive.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallklite" Content="K-Lite Codec Standard" ToolTip="K-Lite Codec Pack Standard is a collection of audio and video codecs and related tools, providing essential components for media playback." Margin="0,0,2,0"/><TextBlock Name="WPFInstallkliteLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.codecguide.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallkodi" Content="Kodi Media Center" ToolTip="Kodi is an open-source media center application that allows you to play and view most videos, music, podcasts, and other digital media files." Margin="0,0,2,0"/><TextBlock Name="WPFInstallkodiLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://kodi.tv/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallkrita" Content="Krita (Image Editor)" ToolTip="Krita is a powerful open-source painting application. It is designed for concept artists, illustrators, matte and texture artists, and the VFX industry." Margin="0,0,2,0"/><TextBlock Name="WPFInstallkritaLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://krita.org/en/features/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalllightshot" Content="Lightshot (Screenshots)" ToolTip="Ligthshot is an Easy-to-use, light-weight screenshot software tool, where you can optionally edit your screenshots using different tools, share them via Internet and/or save to disk, and customize the available options." Margin="0,0,2,0"/><TextBlock Name="WPFInstalllightshotLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://app.prntscr.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmpc" Content="Media Player Classic (Video Player)" ToolTip="Media Player Classic is a lightweight, open-source media player that supports a wide range of audio and video formats. It includes features like customizable toolbars and support for subtitles." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmpcLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://mpc-hc.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmusescore" Content="MuseScore" ToolTip="Create, play back and print beautiful sheet music with free and easy to use music notation software MuseScore." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmusescoreLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://musescore.org/en" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmusicbee" Content="MusicBee (Music Player)" ToolTip="MusicBee is a customizable music player with support for various audio formats. It includes features like an integrated search function, tag editing, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmusicbeeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://getmusicbee.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnglide" Content="nGlide (3dfx compatibility)" ToolTip="nGlide is a 3Dfx Voodoo Glide wrapper. It allows you to play games that use Glide API on modern graphics cards without the need for a 3Dfx Voodoo graphics card." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnglideLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="http://www.zeus-software.com/downloads/nglide" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnomacs" Content="Nomacs (Image viewer)" ToolTip="Nomacs is a free, open-source image viewer that supports multiple platforms. It features basic image editing capabilities and supports a variety of image formats." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnomacsLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://nomacs.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallobs" Content="OBS Studio" ToolTip="OBS Studio is a free and open-source software for video recording and live streaming. It supports real-time video/audio capturing and mixing, making it popular among content creators." Margin="0,0,2,0"/><TextBlock Name="WPFInstallobsLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://obsproject.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallopenscad" Content="OpenSCAD" ToolTip="OpenSCAD is a free and open-source script-based 3D CAD modeler. It is especially useful for creating parametric designs for 3D printing." Margin="0,0,2,0"/><TextBlock Name="WPFInstallopenscadLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.openscad.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallorcaslicer" Content="OrcaSlicer" ToolTip="G-code generator for 3D printers (Bambu, Prusa, Voron, VzBot, RatRig, Creality, etc.)" Margin="0,0,2,0"/><TextBlock Name="WPFInstallorcaslicerLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/SoftFever/OrcaSlicer" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallPaintdotnet" Content="Paint.NET" ToolTip="Paint.NET is a free image and photo editing software for Windows. It features an intuitive user interface and supports a wide range of powerful editing tools." Margin="0,0,2,0"/><TextBlock Name="WPFInstallPaintdotnetLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.getpaint.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallplex" Content="Plex Media Server" ToolTip="Plex Media Server is a media server software that allows you to organize and stream your media library. It supports various media formats and offers a wide range of features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallplexLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.plex.tv/your-media/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsharex" Content="ShareX (Screenshots)" ToolTip="ShareX is a free and open-source screen capture and file sharing tool. It supports various capture methods and offers advanced features for editing and sharing screenshots." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsharexLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://getsharex.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallstrawberry" Content="Strawberry (Music Player)" ToolTip="Strawberry is an open-source music player that focuses on music collection management and audio quality. It supports various audio formats and features a clean user interface." Margin="0,0,2,0"/><TextBlock Name="WPFInstallstrawberryLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.strawberrymusicplayer.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallstremio" Content="Stremio" ToolTip="Stremio is a media center application that allows users to organize and stream their favorite movies, TV shows, and video content." Margin="0,0,2,0"/><TextBlock Name="WPFInstallstremioLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.stremio.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltidal" Content="Tidal" ToolTip="Tidal is a music streaming service known for its high-fidelity audio quality and exclusive content. It offers a vast library of songs and curated playlists." Margin="0,0,2,0"/><TextBlock Name="WPFInstalltidalLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://tidal.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvideomass" Content="Videomass" ToolTip="Videomass by GianlucaPernigotto is a cross-platform GUI for FFmpeg, streamlining multimedia file processing with batch conversions and user-friendly features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvideomassLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://jeanslack.github.io/Videomass/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvlc" Content="VLC (Video Player)" ToolTip="VLC Media Player is a free and open-source multimedia player that supports a wide range of audio and video formats. It is known for its versatility and cross-platform compatibility." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvlcLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.videolan.org/vlc/" />
</StackPanel>

</StackPanel>
</Border>
<Border Grid.Row="1" Grid.Column="3">
<StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvoicemeeter" Content="Voicemeeter (Audio)" ToolTip="Voicemeeter is a virtual audio mixer that allows you to manage and enhance audio streams on your computer. It is commonly used for audio recording and streaming purposes." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvoicemeeterLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.vb-audio.com/Voicemeeter/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallytdlp" Content="Yt-dlp" ToolTip="Command-line tool that allows you to download videos from YouTube and other supported sites. It is an improved version of the popular youtube-dl." Margin="0,0,2,0"/><TextBlock Name="WPFInstallytdlpLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/yt-dlp/yt-dlp" />
</StackPanel>
<Label Content="Pro Tools" FontSize="16"/>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalladvancedip" Content="Advanced IP Scanner" ToolTip="Advanced IP Scanner is a fast and easy-to-use network scanner. It is designed to analyze LAN networks and provides information about connected devices." Margin="0,0,2,0"/><TextBlock Name="WPFInstalladvancedipLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.advanced-ip-scanner.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallangryipscanner" Content="Angry IP Scanner" ToolTip="Angry IP Scanner is an open-source and cross-platform network scanner. It is used to scan IP addresses and ports, providing information about network connectivity." Margin="0,0,2,0"/><TextBlock Name="WPFInstallangryipscannerLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://angryip.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallefibooteditor" Content="EFI Boot Editor" ToolTip="EFI Boot Editor is a tool for managing the EFI/UEFI boot entries on your system. It allows you to customize the boot configuration of your computer." Margin="0,0,2,0"/><TextBlock Name="WPFInstallefibooteditorLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.easyuefi.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallheidisql" Content="HeidiSQL" ToolTip="HeidiSQL is a powerful and easy-to-use client for MySQL, MariaDB, Microsoft SQL Server, and PostgreSQL databases. It provides tools for database management and development." Margin="0,0,2,0"/><TextBlock Name="WPFInstallheidisqlLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.heidisql.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmremoteng" Content="mRemoteNG" ToolTip="mRemoteNG is a free and open-source remote connections manager. It allows you to view and manage multiple remote sessions in a single interface." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmremotengLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://mremoteng.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnmap" Content="Nmap" ToolTip="Nmap (Network Mapper) is an open-source tool for network exploration and security auditing. It discovers devices on a network and provides information about their ports and services." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnmapLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://nmap.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallOpenVPN" Content="OpenVPN Connect" ToolTip="OpenVPN Connect is an open-source VPN client that allows you to connect securely to a VPN server. It provides a secure and encrypted connection for protecting your online privacy." Margin="0,0,2,0"/><TextBlock Name="WPFInstallOpenVPNLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://openvpn.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallPortmaster" Content="Portmaster" ToolTip="Portmaster is a free and open-source application that puts you back in charge over all your computers network connections." Margin="0,0,2,0"/><TextBlock Name="WPFInstallPortmasterLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://safing.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallputty" Content="PuTTY" ToolTip="PuTTY is a free and open-source terminal emulator, serial console, and network file transfer application. It supports various network protocols such as SSH, Telnet, and SCP." Margin="0,0,2,0"/><TextBlock Name="WPFInstallputtyLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.chiark.greenend.org.uk/~sgtatham/putty/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallrustdesk" Content="RustDesk" ToolTip="RustDesk is a free and open-source remote desktop application. It provides a secure way to connect to remote machines and access desktop environments." Margin="0,0,2,0"/><TextBlock Name="WPFInstallrustdeskLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://rustdesk.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsimplewall" Content="Simplewall" ToolTip="Simplewall is a free and open-source firewall application for Windows. It allows users to control and manage the inbound and outbound network traffic of applications." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsimplewallLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/henrypp/simplewall" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallventoy" Content="Ventoy" ToolTip="Ventoy is an open-source tool for creating bootable USB drives. It supports multiple ISO files on a single USB drive, making it a versatile solution for installing operating systems." Margin="0,0,2,0"/><TextBlock Name="WPFInstallventoyLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.ventoy.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwinscp" Content="WinSCP" ToolTip="WinSCP is a popular open-source SFTP, FTP, and SCP client for Windows. It allows secure file transfers between a local and a remote computer." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwinscpLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://winscp.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwireguard" Content="WireGuard" ToolTip="WireGuard is a fast and modern VPN (Virtual Private Network) protocol. It aims to be simpler and more efficient than other VPN protocols, providing secure and reliable connections." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwireguardLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.wireguard.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwireshark" Content="Wireshark" ToolTip="Wireshark is a widely-used open-source network protocol analyzer. It allows users to capture and analyze network traffic in real-time, providing detailed insights into network activities." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwiresharkLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.wireshark.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallxpipe" Content="XPipe" ToolTip="XPipe is an open-source tool for orchestrating containerized applications. It simplifies the deployment and management of containerized services in a distributed environment." Margin="0,0,2,0"/><TextBlock Name="WPFInstallxpipeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://xpipe.io/" />
</StackPanel>
<Label Content="Utilities" FontSize="16"/>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstall1password" Content="1Password" ToolTip="1Password is a password manager that allows you to store and manage your passwords securely." Margin="0,0,2,0"/><TextBlock Name="WPFInstall1passwordLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://1password.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstall7zip" Content="7-Zip" ToolTip="7-Zip is a free and open-source file archiver utility. It supports several compression formats and provides a high compression ratio, making it a popular choice for file compression." Margin="0,0,2,0"/><TextBlock Name="WPFInstall7zipLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.7-zip.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallalacritty" Content="Alacritty Terminal" ToolTip="Alacritty is a fast, cross-platform, and GPU-accelerated terminal emulator. It is designed for performance and aims to be the fastest terminal emulator available." Margin="0,0,2,0"/><TextBlock Name="WPFInstallalacrittyLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://alacritty.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallanydesk" Content="AnyDesk" ToolTip="AnyDesk is a remote desktop software that enables users to access and control computers remotely. It is known for its fast connection and low latency." Margin="0,0,2,0"/><TextBlock Name="WPFInstallanydeskLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://anydesk.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallauthy" Content="Authy" ToolTip="Simple and cross-platform 2FA app" Margin="0,0,2,0"/><TextBlock Name="WPFInstallauthyLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://authy.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallautodarkmode" Content="Windows Auto Dark Mode" ToolTip="Automatically switches between the dark and light theme of Windows 10 and Windows 11" Margin="0,0,2,0"/><TextBlock Name="WPFInstallautodarkmodeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/AutoDarkMode/Windows-Auto-Night-Mode" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallautohotkey" Content="AutoHotkey" ToolTip="AutoHotkey is a scripting language for Windows that allows users to create custom automation scripts and macros. It is often used for automating repetitive tasks and customizing keyboard shortcuts." Margin="0,0,2,0"/><TextBlock Name="WPFInstallautohotkeyLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.autohotkey.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallbarrier" Content="Barrier" ToolTip="Barrier is an open-source software KVM (keyboard, video, and mouseswitch). It allows users to control multiple computers with a single keyboard and mouse, even if they have different operating systems." Margin="0,0,2,0"/><TextBlock Name="WPFInstallbarrierLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/debauchee/barrier" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallbat" Content="Bat (Cat)" ToolTip="Bat is a cat command clone with syntax highlighting. It provides a user-friendly and feature-rich alternative to the traditional cat command for viewing and concatenating files." Margin="0,0,2,0"/><TextBlock Name="WPFInstallbatLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/sharkdp/bat" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallbitcomet" Content="BitComet" ToolTip="BitComet is a free and open-source BitTorrent client that supports HTTP/FTP downloads and provides download management features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallbitcometLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.bitcomet.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallbitwarden" Content="Bitwarden" ToolTip="Bitwarden is an open-source password management solution. It allows users to store and manage their passwords in a secure and encrypted vault, accessible across multiple devices." Margin="0,0,2,0"/><TextBlock Name="WPFInstallbitwardenLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://bitwarden.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallbleachbit" Content="BleachBit" ToolTip="Clean Your System and Free Disk Space" Margin="0,0,2,0"/><TextBlock Name="WPFInstallbleachbitLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.bleachbit.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallbulkcrapuninstaller" Content="Bulk Crap Uninstaller" ToolTip="Bulk Crap Uninstaller is a free and open-source uninstaller utility for Windows. It helps users remove unwanted programs and clean up their system by uninstalling multiple applications at once." Margin="0,0,2,0"/><TextBlock Name="WPFInstallbulkcrapuninstallerLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.bcuninstaller.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallbulkrenameutility" Content="Bulk Rename Utility" ToolTip="Bulk Rename Utility allows you to easily rename files and folders recursively based upon find-replace, character place, fields, sequences, regular expressions, EXIF data, and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallbulkrenameutilityLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.bulkrenameutility.co.uk" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallcapframex" Content="CapFrameX" ToolTip="Frametimes capture and analysis tool based on Intel&#39;s PresentMon. Overlay provided by Rivatuner Statistics Server." Margin="0,0,2,0"/><TextBlock Name="WPFInstallcapframexLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.capframex.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallcarnac" Content="Carnac" ToolTip="Carnac is a keystroke visualizer for Windows. It displays keystrokes in an overlay, making it useful for presentations, tutorials, and live demonstrations." Margin="0,0,2,0"/><TextBlock Name="WPFInstallcarnacLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://carnackeys.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallcopyq" Content="CopyQ (Clipboard Manager)" ToolTip="CopyQ is a clipboard manager with advanced features, allowing you to store, edit, and retrieve clipboard history." Margin="0,0,2,0"/><TextBlock Name="WPFInstallcopyqLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://copyq.readthedocs.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallcpuz" Content="CPU-Z" ToolTip="CPU-Z is a system monitoring and diagnostic tool for Windows. It provides detailed information about the computer&#39;s hardware components, including the CPU, memory, and motherboard." Margin="0,0,2,0"/><TextBlock Name="WPFInstallcpuzLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.cpuid.com/softwares/cpu-z.html" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallcrystaldiskinfo" Content="Crystal Disk Info" ToolTip="Crystal Disk Info is a disk health monitoring tool that provides information about the status and performance of hard drives. It helps users anticipate potential issues and monitor drive health." Margin="0,0,2,0"/><TextBlock Name="WPFInstallcrystaldiskinfoLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://crystalmark.info/en/software/crystaldiskinfo/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallcrystaldiskmark" Content="Crystal Disk Mark" ToolTip="Crystal Disk Mark is a disk benchmarking tool that measures the read and write speeds of storage devices. It helps users assess the performance of their hard drives and SSDs." Margin="0,0,2,0"/><TextBlock Name="WPFInstallcrystaldiskmarkLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://crystalmark.info/en/software/crystaldiskmark/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallddu" Content="Display Driver Uninstaller" ToolTip="Display Driver Uninstaller (DDU) is a tool for completely uninstalling graphics drivers from NVIDIA, AMD, and Intel. It is useful for troubleshooting graphics driver-related issues." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldduLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.wagnardsoft.com/display-driver-uninstaller-DDU-" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldeluge" Content="Deluge" ToolTip="Deluge is a free and open-source BitTorrent client. It features a user-friendly interface, support for plugins, and the ability to manage torrents remotely." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldelugeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://deluge-torrent.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldevtoys" Content="DevToys" ToolTip="DevToys is a collection of development-related utilities and tools for Windows. It includes tools for file management, code formatting, and productivity enhancements for developers." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldevtoysLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://devtoys.app/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalldmt" Content="Dual Monitor Tools" ToolTip="Dual Monitor Tools (DMT) is a FOSS app that customize handling multiple monitors and even lock the mouse on specific monitor. Useful for full screen games and apps that does not handle well a second monitor or helps the workflow." Margin="0,0,2,0"/><TextBlock Name="WPFInstalldmtLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://dualmonitortool.sourceforge.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallduplicati" Content="Duplicati" ToolTip="Duplicati is an open-source backup solution that supports encrypted, compressed, and incremental backups. It is designed to securely store data on cloud storage services." Margin="0,0,2,0"/><TextBlock Name="WPFInstallduplicatiLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.duplicati.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallerrorlookup" Content="Windows Error Code Lookup" ToolTip="ErrorLookup is a tool for looking up Windows error codes and their descriptions." Margin="0,0,2,0"/><TextBlock Name="WPFInstallerrorlookupLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/HenryPP/ErrorLookup" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallesearch" Content="Everything Search" ToolTip="Everything Search is a fast and efficient file search utility for Windows." Margin="0,0,2,0"/><TextBlock Name="WPFInstallesearchLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.voidtools.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallespanso" Content="Espanso" ToolTip="Cross-platform and open-source Text Expander written in Rust" Margin="0,0,2,0"/><TextBlock Name="WPFInstallespansoLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://espanso.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalletcher" Content="Etcher USB Creator" ToolTip="Etcher is a powerful tool for creating bootable USB drives with ease." Margin="0,0,2,0"/><TextBlock Name="WPFInstalletcherLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.balena.io/etcher/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfileconverter" Content="File-Converter" ToolTip="File Converter is a very simple tool which allows you to convert and compress one or several file(s) using the context menu in windows explorer." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfileconverterLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://file-converter.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallflow" Content="Flow launcher" ToolTip="Keystroke launcher for Windows to search, manage and launch files, folders bookmarks, websites and more." Margin="0,0,2,0"/><TextBlock Name="WPFInstallflowLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.flowlauncher.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallflux" Content="F.lux" ToolTip="f.lux adjusts the color temperature of your screen to reduce eye strain during nighttime use." Margin="0,0,2,0"/><TextBlock Name="WPFInstallfluxLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://justgetflux.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallfzf" Content="Fzf" ToolTip="A command-line fuzzy finder" Margin="0,0,2,0"/><TextBlock Name="WPFInstallfzfLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/junegunn/fzf/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallglaryutilities" Content="Glary Utilities" ToolTip="Glary Utilities is a comprehensive system optimization and maintenance tool for Windows." Margin="0,0,2,0"/><TextBlock Name="WPFInstallglaryutilitiesLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.glarysoft.com/glary-utilities/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgoogledrive" Content="Google Drive" ToolTip="File syncing across devices all tied to your google account" Margin="0,0,2,0"/><TextBlock Name="WPFInstallgoogledriveLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.google.com/drive/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgpuz" Content="GPU-Z" ToolTip="GPU-Z provides detailed information about your graphics card and GPU." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgpuzLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.techpowerup.com/gpuz/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallgsudo" Content="Gsudo" ToolTip="Gsudo is a sudo implementation for Windows, allowing elevated privilege execution." Margin="0,0,2,0"/><TextBlock Name="WPFInstallgsudoLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://gerardog.github.io/gsudo/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallhwinfo" Content="HWiNFO" ToolTip="HWiNFO provides comprehensive hardware information and diagnostics for Windows." Margin="0,0,2,0"/><TextBlock Name="WPFInstallhwinfoLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.hwinfo.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallhwmonitor" Content="HWMonitor" ToolTip="HWMonitor is a hardware monitoring program that reads PC systems main health sensors." Margin="0,0,2,0"/><TextBlock Name="WPFInstallhwmonitorLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.cpuid.com/softwares/hwmonitor.html" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallintelpresentmon" Content="Intel-PresentMon" ToolTip="A new gaming performance overlay and telemetry application to monitor and measure your gaming experience." Margin="0,0,2,0"/><TextBlock Name="WPFInstallintelpresentmonLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://game.intel.com/us/stories/intel-presentmon/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljdownloader" Content="JDownloader" ToolTip="JDownloader is a feature-rich download manager with support for various file hosting services." Margin="0,0,2,0"/><TextBlock Name="WPFInstalljdownloaderLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="http://jdownloader.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalljpegview" Content="JPEG View" ToolTip="JPEGView is a lean, fast and highly configurable viewer/editor for JPEG, BMP, PNG, WEBP, TGA, GIF, JXL, HEIC, HEIF, AVIF and TIFF images with a minimal GUI" Margin="0,0,2,0"/><TextBlock Name="WPFInstalljpegviewLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/sylikc/jpegview" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallkdeconnect" Content="KDE Connect" ToolTip="KDE Connect allows seamless integration between your KDE desktop and mobile devices." Margin="0,0,2,0"/><TextBlock Name="WPFInstallkdeconnectLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://community.kde.org/KDEConnect" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallkeepass" Content="KeePassXC" ToolTip="KeePassXC is a cross-platform, open-source password manager with strong encryption features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallkeepassLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://keepassxc.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalllinkshellextension" Content="Link Shell extension" ToolTip="Link Shell Extension (LSE) provides for the creation of Hardlinks, Junctions, Volume Mountpoints, Symbolic Links, a folder cloning process that utilises Hardlinks or Symbolic Links and a copy process taking care of Junctions, Symbolic Links, and Hardlinks. LSE, as its name implies is implemented as a Shell extension and is accessed from Windows Explorer, or similar file/folder managers." Margin="0,0,2,0"/><TextBlock Name="WPFInstalllinkshellextensionLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://schinagl.priv.at/nt/hardlinkshellext/hardlinkshellext.html" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalllivelywallpaper" Content="Lively Wallpaper" ToolTip="Free and open-source software that allows users to set animated desktop wallpapers and screensavers." Margin="0,0,2,0"/><TextBlock Name="WPFInstalllivelywallpaperLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.rocksdanister.com/lively/" />
</StackPanel>

</StackPanel>
</Border>
<Border Grid.Row="1" Grid.Column="4">
<StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalllocalsend" Content="LocalSend" ToolTip="An open source cross-platform alternative to AirDrop." Margin="0,0,2,0"/><TextBlock Name="WPFInstalllocalsendLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://localsend.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalllockhunter" Content="LockHunter" ToolTip="LockHunter is a free tool to delete files blocked by something you do not know." Margin="0,0,2,0"/><TextBlock Name="WPFInstalllockhunterLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://lockhunter.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmagicwormhole" Content="Magic Wormhole" ToolTip="get things from one computer to another, safely" Margin="0,0,2,0"/><TextBlock Name="WPFInstallmagicwormholeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/magic-wormhole/magic-wormhole" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmalwarebytes" Content="Malwarebytes" ToolTip="Malwarebytes is an anti-malware software that provides real-time protection against threats." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmalwarebytesLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.malwarebytes.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmeld" Content="Meld" ToolTip="Meld is a visual diff and merge tool for files and directories." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmeldLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://meldmerge.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmonitorian" Content="Monitorian" ToolTip="Monitorian is a utility for adjusting monitor brightness and contrast on Windows." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmonitorianLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/emoacht/Monitorian" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallMotrix" Content="Motrix Download Manager" ToolTip="A full-featured download manager." Margin="0,0,2,0"/><TextBlock Name="WPFInstallMotrixLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://motrix.app/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallmsiafterburner" Content="MSI Afterburner" ToolTip="MSI Afterburner is a graphics card overclocking utility with advanced features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallmsiafterburnerLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.msi.com/Landing/afterburner" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnanazip" Content="NanaZip" ToolTip="NanaZip is a fast and efficient file compression and decompression tool." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnanazipLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/M2Team/NanaZip" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallneofetchwin" Content="Neofetch" ToolTip="Neofetch is a command-line utility for displaying system information in a visually appealing way." Margin="0,0,2,0"/><TextBlock Name="WPFInstallneofetchwinLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/nepnep39/neofetch-win" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnextclouddesktop" Content="Nextcloud Desktop" ToolTip="Nextcloud Desktop is the official desktop client for the Nextcloud file synchronization and sharing platform." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnextclouddesktopLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://nextcloud.com/install/#install-clients" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnilesoftShel" Content="Shell (Expanded Context Menu)" ToolTip="Shell is an expanded context menu tool that adds extra functionality and customization options to the Windows context menu." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnilesoftShelLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://nilesoft.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnushell" Content="Nushell" ToolTip="Nushell is a new shell that takes advantage of modern hardware and systems to provide a powerful, expressive, and fast experience." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnushellLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.nushell.sh/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallnvclean" Content="NVCleanstall" ToolTip="NVCleanstall is a tool designed to customize NVIDIA driver installations, allowing advanced users to control more aspects of the installation process." Margin="0,0,2,0"/><TextBlock Name="WPFInstallnvcleanLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.techpowerup.com/nvcleanstall/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallOPAutoClicker" Content="OPAutoClicker" ToolTip="A full-fledged autoclicker with two modes of autoclicking, at your dynamic cursor location or at a prespecified location." Margin="0,0,2,0"/><TextBlock Name="WPFInstallOPAutoClickerLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.opautoclicker.com" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallopenhashtab" Content="OpenHashTab" ToolTip="OpenHashTab is a shell extension for conveniently calculating and checking file hashes from file properties." Margin="0,0,2,0"/><TextBlock Name="WPFInstallopenhashtabLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/namazso/OpenHashTab/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallopenrgb" Content="OpenRGB" ToolTip="OpenRGB is an open-source RGB lighting control software designed to manage and control RGB lighting for various components and peripherals." Margin="0,0,2,0"/><TextBlock Name="WPFInstallopenrgbLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://openrgb.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallopenshell" Content="Open Shell (Start Menu)" ToolTip="Open Shell is a Windows Start Menu replacement with enhanced functionality and customization options." Margin="0,0,2,0"/><TextBlock Name="WPFInstallopenshellLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/Open-Shell/Open-Shell-Menu" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallOVirtualBox" Content="Oracle VirtualBox" ToolTip="Oracle VirtualBox is a powerful and free open-source virtualization tool for x86 and AMD64/Intel64 architectures." Margin="0,0,2,0"/><TextBlock Name="WPFInstallOVirtualBoxLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.virtualbox.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallownclouddesktop" Content="ownCloud Desktop" ToolTip="ownCloud Desktop is the official desktop client for the ownCloud file synchronization and sharing platform." Margin="0,0,2,0"/><TextBlock Name="WPFInstallownclouddesktopLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://owncloud.com/desktop-app/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallparsec" Content="Parsec" ToolTip="Parsec is a low-latency, high-quality remote desktop sharing application for collaborating and gaming across devices." Margin="0,0,2,0"/><TextBlock Name="WPFInstallparsecLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://parsec.app/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpeazip" Content="PeaZip" ToolTip="PeaZip is a free, open-source file archiver utility that supports multiple archive formats and provides encryption features." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpeazipLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://peazip.github.io/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallpiimager" Content="Raspberry Pi Imager" ToolTip="Raspberry Pi Imager is a utility for writing operating system images to SD cards for Raspberry Pi devices." Margin="0,0,2,0"/><TextBlock Name="WPFInstallpiimagerLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.raspberrypi.com/software/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallprocesslasso" Content="Process Lasso" ToolTip="Process Lasso is a system optimization and automation tool that improves system responsiveness and stability by adjusting process priorities and CPU affinities." Margin="0,0,2,0"/><TextBlock Name="WPFInstallprocesslassoLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://bitsum.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallprucaslicer" Content="PrusaSlicer" ToolTip="PrusaSlicer is a powerful and easy-to-use slicing software for 3D printing with Prusa 3D printers." Margin="0,0,2,0"/><TextBlock Name="WPFInstallprucaslicerLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.prusa3d.com/prusaslicer/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallqbittorrent" Content="qBittorrent" ToolTip="qBittorrent is a free and open-source BitTorrent client that aims to provide a feature-rich and lightweight alternative to other torrent clients." Margin="0,0,2,0"/><TextBlock Name="WPFInstallqbittorrentLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.qbittorrent.org/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallquicklook" Content="Quicklook" ToolTip="Bring macOS &#8220;Quick Look&#8221; feature to Windows" Margin="0,0,2,0"/><TextBlock Name="WPFInstallquicklookLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/QL-Win/QuickLook" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallrainmeter" Content="Rainmeter" ToolTip="Rainmeter is a desktop customization tool that allows you to create and share customizable skins for your desktop." Margin="0,0,2,0"/><TextBlock Name="WPFInstallrainmeterLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.rainmeter.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallrevo" Content="Revo Uninstaller" ToolTip="Revo Uninstaller is an advanced uninstaller tool that helps you remove unwanted software and clean up your system." Margin="0,0,2,0"/><TextBlock Name="WPFInstallrevoLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.revouninstaller.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallripgrep" Content="Ripgrep" ToolTip="Fast and powerful commandline search tool" Margin="0,0,2,0"/><TextBlock Name="WPFInstallripgrepLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/BurntSushi/ripgrep/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallrufus" Content="Rufus Imager" ToolTip="Rufus is a utility that helps format and create bootable USB drives, such as USB keys or pen drives." Margin="0,0,2,0"/><TextBlock Name="WPFInstallrufusLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://rufus.ie/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsamsungmagician" Content="Samsung Magician" ToolTip="Samsung Magician is a utility for managing and optimizing Samsung SSDs." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsamsungmagicianLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://semiconductor.samsung.com/consumer-storage/magician/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsandboxie" Content="Sandboxie Plus" ToolTip="Sandboxie Plus is a sandbox-based isolation program that provides enhanced security by running applications in an isolated environment." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsandboxieLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/sandboxie-plus/Sandboxie" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsdio" Content="Snappy Driver Installer Origin" ToolTip="Snappy Driver Installer Origin is a free and open-source driver updater with a vast driver database for Windows." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsdioLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://sourceforge.net/projects/snappy-driver-installer-origin" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsignalrgb" Content="SignalRGB" ToolTip="SignalRGB lets you control and sync your favorite RGB devices with one free application." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsignalrgbLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.signalrgb.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallspacedrive" Content="Spacedrive File Manager" ToolTip="Spacedrive is a file manager that offers cloud storage integration and file synchronization across devices." Margin="0,0,2,0"/><TextBlock Name="WPFInstallspacedriveLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.spacedrive.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallspacesniffer" Content="SpaceSniffer" ToolTip="A tool application that lets you understand how folders and files are structured on your disks" Margin="0,0,2,0"/><TextBlock Name="WPFInstallspacesnifferLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="http://www.uderzo.it/main_products/space_sniffer/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallstartallback" Content="StartAllBack" ToolTip="StartAllBack is a Tool that can be used to edit the Windows appearance by your liking (Taskbar, Start Menu, File Explorer, Control Panel, Context Menu ...)" Margin="0,0,2,0"/><TextBlock Name="WPFInstallstartallbackLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.startallback.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsuperf4" Content="SuperF4" ToolTip="SuperF4 is a utility that allows you to terminate programs instantly by pressing a customizable hotkey." Margin="0,0,2,0"/><TextBlock Name="WPFInstallsuperf4Link" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://stefansundin.github.io/superf4/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsyncthingtray" Content="Syncthingtray" ToolTip="Might be the alternative for Synctrayzor. Windows tray utility / filesystem watcher / launcher for Syncthing" Margin="0,0,2,0"/><TextBlock Name="WPFInstallsyncthingtrayLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/Martchus/syncthingtray" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallsynctrayzor" Content="SyncTrayzor" ToolTip="Windows tray utility / filesystem watcher / launcher for Syncthing" Margin="0,0,2,0"/><TextBlock Name="WPFInstallsynctrayzorLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/canton7/SyncTrayzor/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltabby" Content="Tabby.sh" ToolTip="Tabby is a highly configurable terminal emulator, SSH and serial client for Windows, macOS and Linux" Margin="0,0,2,0"/><TextBlock Name="WPFInstalltabbyLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://tabby.sh/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltailscale" Content="Tailscale" ToolTip="Tailscale is a secure and easy-to-use VPN solution for connecting your devices and networks." Margin="0,0,2,0"/><TextBlock Name="WPFInstalltailscaleLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://tailscale.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallteamviewer" Content="TeamViewer" ToolTip="TeamViewer is a popular remote access and support software that allows you to connect to and control remote devices." Margin="0,0,2,0"/><TextBlock Name="WPFInstallteamviewerLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.teamviewer.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltightvnc" Content="TightVNC" ToolTip="TightVNC is a free and Open Source remote desktop software that lets you access and control a computer over the network. With its intuitive interface, you can interact with the remote screen as if you were sitting in front of it. You can open files, launch applications, and perform other actions on the remote desktop almost as if you were physically there" Margin="0,0,2,0"/><TextBlock Name="WPFInstalltightvncLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.tightvnc.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltixati" Content="Tixati" ToolTip="Tixati is a cross-platform BitTorrent client written in C++ that has been designed to be light on system resources." Margin="0,0,2,0"/><TextBlock Name="WPFInstalltixatiLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.tixati.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltotalcommander" Content="Total Commander" ToolTip="Total Commander is a file manager for Windows that provides a powerful and intuitive interface for file management." Margin="0,0,2,0"/><TextBlock Name="WPFInstalltotalcommanderLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.ghisler.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltreesize" Content="TreeSize Free" ToolTip="TreeSize Free is a disk space manager that helps you analyze and visualize the space usage on your drives." Margin="0,0,2,0"/><TextBlock Name="WPFInstalltreesizeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.jam-software.com/treesize_free/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallttaskbar" Content="Translucent Taskbar" ToolTip="Translucent Taskbar is a tool that allows you to customize the transparency of the Windows taskbar." Margin="0,0,2,0"/><TextBlock Name="WPFInstallttaskbarLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/TranslucentTB/TranslucentTB" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstalltwinkletray" Content="Twinkle Tray" ToolTip="Twinkle Tray lets you easily manage the brightness levels of multiple monitors." Margin="0,0,2,0"/><TextBlock Name="WPFInstalltwinkletrayLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://twinkletray.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallultravnc" Content="UltraVNC" ToolTip="UltraVNC is a powerful, easy to use and free - remote pc access softwares - that can display the screen of another computer (via internet or network) on your own screen. The program allows you to use your mouse and keyboard to control the other PC remotely. It means that you can work on a remote computer, as if you were sitting in front of it, right from your current location." Margin="0,0,2,0"/><TextBlock Name="WPFInstallultravncLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://uvnc.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallvistaswitcher" Content="VistaSwitcher" ToolTip="VistaSwitcher makes it easier for you to locate windows and switch focus, even on multi-monitor systems. The switcher window consists of an easy-to-read list of all tasks running with clearly shown titles and a full-sized preview of the selected task." Margin="0,0,2,0"/><TextBlock Name="WPFInstallvistaswitcherLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.ntwind.com/freeware/vistaswitcher.html" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwindirstat" Content="WinDirStat" ToolTip="WinDirStat is a disk usage statistics viewer and cleanup tool for Windows." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwindirstatLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://windirstat.net/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwindowsfirewallcontrol" Content="Windows Firewall Control" ToolTip="Windows Firewall Control is a powerful tool which extends the functionality of Windows Firewall and provides new extra features which makes Windows Firewall better." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwindowsfirewallcontrolLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.binisoft.org/wfc" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwindowspchealth" Content="Windows PC Health Check" ToolTip="Windows PC Health Check is a tool that helps you check if your PC meets the system requirements for Windows 11." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwindowspchealthLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://support.microsoft.com/en-us/windows/how-to-use-the-pc-health-check-app-9c8abd9b-03ba-4e67-81ef-36f37caa7844" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwingetui" Content="WingetUI" ToolTip="WingetUI is a graphical user interface for Microsoft&#39;s Windows Package Manager (winget)." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwingetuiLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.marticliment.com/wingetui/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwinpaletter" Content="WinPaletter" ToolTip="WinPaletter is a tool for adjusting the color palette of Windows 10, providing customization options for window colors." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwinpaletterLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/Abdelrhman-AK/WinPaletter" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwinrar" Content="WinRAR" ToolTip="WinRAR is a powerful archive manager that allows you to create, manage, and extract compressed files." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwinrarLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.win-rar.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwisetoys" Content="WiseToys" ToolTip="WiseToys is a set of utilities and tools designed to enhance and optimize your Windows experience." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwisetoysLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://toys.wisecleaner.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwizfile" Content="WizFile" ToolTip="Find files by name on your hard drives almost instantly." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwizfileLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://antibody-software.com/wizfile/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallwiztree" Content="WizTree" ToolTip="WizTree is a fast disk space analyzer that helps you quickly find the files and folders consuming the most space on your hard drive." Margin="0,0,2,0"/><TextBlock Name="WPFInstallwiztreeLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://wiztreefree.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallxdm" Content="Xtreme Download Manager" ToolTip="Xtreme Download Manager is an advanced download manager with support for various protocols and browsers.*Browser integration deprecated by google store. No official release.*" Margin="0,0,2,0"/><TextBlock Name="WPFInstallxdmLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://xtremedownloadmanager.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallxeheditor" Content="HxD Hex Editor" ToolTip="HxD is a free hex editor that allows you to edit, view, search, and analyze binary files." Margin="0,0,2,0"/><TextBlock Name="WPFInstallxeheditorLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://mh-nexus.de/en/hxd/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallxnview" Content="XnView classic" ToolTip="XnView is an efficient image viewer, browser and converter for Windows." Margin="0,0,2,0"/><TextBlock Name="WPFInstallxnviewLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://www.xnview.com/en/xnview/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallzerotierone" Content="ZeroTier One" ToolTip="ZeroTier One is a software-defined networking tool that allows you to create secure and scalable networks." Margin="0,0,2,0"/><TextBlock Name="WPFInstallzerotieroneLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://zerotier.com/" />
</StackPanel>
<StackPanel Orientation="Horizontal">
<CheckBox Name="WPFInstallzoxide" Content="Zoxide" ToolTip="Zoxide is a fast and efficient directory changer (cd) that helps you navigate your file system with ease." Margin="0,0,2,0"/><TextBlock Name="WPFInstallzoxideLink" Style="{StaticResource HoverTextBlockStyle}" Text="(?)" ToolTip="https://github.com/ajeetdsouza/zoxide" />
</StackPanel>

</StackPanel>
</Border>


                        </Grid>
                    </ScrollViewer>

                </Grid>
            </TabItem>
            <TabItem Header="Tweaks" Visibility="Collapsed" Name="WPFTab2">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                <Grid Background="Transparent">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="55"/>
                        <RowDefinition Height=".70*"/>
                        <RowDefinition Height=".10*"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
<ColumnDefinition Width="*"/>
<ColumnDefinition Width="*"/>
</Grid.ColumnDefinitions>
<Border Grid.Row="1" Grid.Column="0">
<StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
<Label Content="Essential Tweaks" FontSize="16"/>
<CheckBox Name="WPFTweaksRestorePoint" Content="Create Restore Point" IsChecked="True" Margin="5,0"  ToolTip="Creates a restore point at runtime in case a revert is needed from WinUtil modifications"/>
<CheckBox Name="WPFTweaksEndTaskOnTaskbar" Content="Enable End Task With Right Click" Margin="5,0"  ToolTip="Enables option to end task when right clicking a program in the taskbar"/>
<CheckBox Name="WPFTweaksOO" Content="Run OO Shutup" Margin="5,0"  ToolTip="Runs OO Shutup and applies the recommended Tweaks. https://www.oo-software.com/en/shutup10"/>
<CheckBox Name="WPFTweaksTele" Content="Disable Telemetry" Margin="5,0"  ToolTip="Disables Microsoft Telemetry. Note: This will lock many Edge Browser settings. Microsoft spies heavily on you when using the Edge browser."/>
<CheckBox Name="WPFTweaksWifi" Content="Disable Wifi-Sense" Margin="5,0"  ToolTip="Wifi Sense is a spying service that phones home all nearby scanned wifi networks and your current geo location."/>
<CheckBox Name="WPFTweaksAH" Content="Disable Activity History" Margin="5,0"  ToolTip="This erases recent docs, clipboard, and run history."/>
<CheckBox Name="WPFTweaksDeleteTempFiles" Content="Delete Temporary Files" Margin="5,0"  ToolTip="Erases TEMP Folders"/>
<CheckBox Name="WPFTweaksDiskCleanup" Content="Run Disk Cleanup" Margin="5,0"  ToolTip="Runs Disk Cleanup on Drive C: and removes old Windows Updates."/>
<CheckBox Name="WPFTweaksLoc" Content="Disable Location Tracking" Margin="5,0"  ToolTip="Disables Location Tracking...DUH!"/>
<CheckBox Name="WPFTweaksHome" Content="Disable Homegroup" Margin="5,0"  ToolTip="Disables HomeGroup - HomeGroup is a password-protected home networking service that lets you share your stuff with other PCs that are currently running and connected to your network."/>
<CheckBox Name="WPFTweaksStorage" Content="Disable Storage Sense" Margin="5,0"  ToolTip="Storage Sense deletes temp files automatically."/>
<CheckBox Name="WPFTweaksHiber" Content="Disable Hibernation" Margin="5,0"  ToolTip="Hibernation is really meant for laptops as it saves what&#39;s in memory before turning the pc off. It really should never be used, but some people are lazy and rely on it. Don&#39;t be like Bob. Bob likes hibernation."/>
<CheckBox Name="WPFTweaksDVR" Content="Disable GameDVR" Margin="5,0"  ToolTip="GameDVR is a Windows App that is a dependency for some Store Games. I&#39;ve never met someone that likes it, but it&#39;s there for the XBOX crowd."/>
<CheckBox Name="WPFTweaksTeredo" Content="Disable Teredo" Margin="5,0"  ToolTip="Teredo network tunneling is a ipv6 feature that can cause additional latency."/>
<CheckBox Name="WPFTweaksServices" Content="Set Services to Manual" Margin="5,0"  ToolTip="Turns a bunch of system services to manual that don&#39;t need to be running all the time. This is pretty harmless as if the service is needed, it will simply start on demand."/>
<Label Content="Advanced Tweaks - CAUTION" FontSize="16"/>
<CheckBox Name="WPFTweaksDisplay" Content="Set Display for Performance" Margin="5,0"  ToolTip="Sets the system preferences to performance. You can do this manually with sysdm.cpl as well."/>
<CheckBox Name="WPFTweaksUTC" Content="Set Time to UTC (Dual Boot)" Margin="5,0"  ToolTip="Essential for computers that are dual booting. Fixes the time sync with Linux Systems."/>
<CheckBox Name="WPFTweaksDisableNotifications" Content="Disable Notification Tray/Calendar" Margin="5,0"  ToolTip="Disables all Notifications INCLUDING Calendar"/>
<CheckBox Name="WPFTweaksDeBloat" Content="Remove ALL MS Store Apps - NOT RECOMMENDED" Margin="5,0"  ToolTip="USE WITH CAUTION!!!!! This will remove ALL Microsoft store apps other than the essentials to make winget work. Games installed by MS Store ARE INCLUDED!"/>
<CheckBox Name="WPFTweaksRemoveEdge" Content="Remove Microsoft Edge - NOT RECOMMENDED" Margin="5,0"  ToolTip="Removes MS Edge when it gets reinstalled by updates."/>
<CheckBox Name="WPFTweaksRemoveOnedrive" Content="Remove OneDrive" Margin="5,0"  ToolTip="Copies OneDrive files to Default Home Folders and Uninstalls it."/>
<CheckBox Name="WPFTweaksRightClickMenu" Content="Set Classic Right-Click Menu " Margin="5,0"  ToolTip="Great Windows 11 tweak to bring back good context menus when right clicking things in explorer."/>
<CheckBox Name="WPFTweaksEnableipsix" Content="Enable IPv6" Margin="5,0"  ToolTip="Enables IPv6."/>
<CheckBox Name="WPFTweaksDisableipsix" Content="Disable IPv6" Margin="5,0"  ToolTip="Disables IPv6."/>
<Button Name="WPFOOSUbutton" Content="Customize OO Shutup Tweaks" HorizontalAlignment = "Left" Width="220" Margin="5" Padding="20,5" />
<StackPanel Orientation="Horizontal" Margin="0,5,0,0">
<Label Content="DNS" HorizontalAlignment="Left" VerticalAlignment="Center"/>
<ComboBox Name="WPFchangedns"  Height="32" Width="186" HorizontalAlignment="Left" VerticalAlignment="Center" Margin="5,5">
<ComboBoxItem IsSelected="True" Content="Default"/>
<ComboBoxItem  Content="DHCP"/>
<ComboBoxItem  Content="Google"/>
<ComboBoxItem  Content="Cloudflare"/>
<ComboBoxItem  Content="Cloudflare_Malware"/>
<ComboBoxItem  Content="Cloudflare_Malware_Adult"/>
<ComboBoxItem  Content="Level3"/>
<ComboBoxItem  Content="Open_DNS"/>
<ComboBoxItem  Content="Quad9"/>
</ComboBox>
</StackPanel><Button Name="WPFTweaksbutton" Content="Run Tweaks" HorizontalAlignment = "Left" Width="160" Margin="5" Padding="20,5" />
<Button Name="WPFUndoall" Content="Undo Selected Tweaks" HorizontalAlignment = "Left" Width="160" Margin="5" Padding="20,5" />

</StackPanel>
</Border>
<Border Grid.Row="1" Grid.Column="1">
<StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
<Label Content="Customize Preferences" FontSize="16"/>
<StackPanel Orientation="Horizontal" Margin="0,10,0,0">
<Label Content="Dark Theme" Style="{StaticResource labelfortweaks}" ToolTip="Enable/Disable Dark Mode." />
<CheckBox Name="WPFToggleDarkMode" Style="{StaticResource ColorfulToggleSwitchStyle}" Margin="2.5,0"/>
</StackPanel>
<StackPanel Orientation="Horizontal" Margin="0,10,0,0">
<Label Content="Bing Search in Start Menu" Style="{StaticResource labelfortweaks}" ToolTip="If enable then includes web search results from Bing in your Start Menu search." />
<CheckBox Name="WPFToggleBingSearch" Style="{StaticResource ColorfulToggleSwitchStyle}" Margin="2.5,0"/>
</StackPanel>
<StackPanel Orientation="Horizontal" Margin="0,10,0,0">
<Label Content="NumLock on Startup" Style="{StaticResource labelfortweaks}" ToolTip="Toggle the Num Lock key state when your computer starts." />
<CheckBox Name="WPFToggleNumLock" Style="{StaticResource ColorfulToggleSwitchStyle}" Margin="2.5,0"/>
</StackPanel>
<StackPanel Orientation="Horizontal" Margin="0,10,0,0">
<Label Content="Verbose Logon Messages" Style="{StaticResource labelfortweaks}" ToolTip="Show detailed messages during the login process for troubleshooting and diagnostics." />
<CheckBox Name="WPFToggleVerboseLogon" Style="{StaticResource ColorfulToggleSwitchStyle}" Margin="2.5,0"/>
</StackPanel>
<StackPanel Orientation="Horizontal" Margin="0,10,0,0">
<Label Content="Show File Extensions" Style="{StaticResource labelfortweaks}" ToolTip="If enabled then File extensions (e.g., .txt, .jpg) are visible." />
<CheckBox Name="WPFToggleShowExt" Style="{StaticResource ColorfulToggleSwitchStyle}" Margin="2.5,0"/>
</StackPanel>
<StackPanel Orientation="Horizontal" Margin="0,10,0,0">
<Label Content="Snap Assist Flyout" Style="{StaticResource labelfortweaks}" ToolTip="If enabled then Snap preview is disabled when maximize button is hovered." />
<CheckBox Name="WPFToggleSnapFlyout" Style="{StaticResource ColorfulToggleSwitchStyle}" Margin="2.5,0"/>
</StackPanel>
<StackPanel Orientation="Horizontal" Margin="0,10,0,0">
<Label Content="Mouse Acceleration" Style="{StaticResource labelfortweaks}" ToolTip="If Enabled then Cursor movement is affected by the speed of your physical mouse movements." />
<CheckBox Name="WPFToggleMouseAcceleration" Style="{StaticResource ColorfulToggleSwitchStyle}" Margin="2.5,0"/>
</StackPanel>
<StackPanel Orientation="Horizontal" Margin="0,10,0,0">
<Label Content="Sticky Keys" Style="{StaticResource labelfortweaks}" ToolTip="If Enabled then Sticky Keys is activated - Sticky keys is an accessibility feature of some graphical user interfaces which assists users who have physical disabilities or help users reduce repetitive strain injury." />
<CheckBox Name="WPFToggleStickyKeys" Style="{StaticResource ColorfulToggleSwitchStyle}" Margin="2.5,0"/>
</StackPanel>
<StackPanel Orientation="Horizontal" Margin="0,10,0,0">
<Label Content="Taskbar Widgets" Style="{StaticResource labelfortweaks}" ToolTip="If Enabled then Widgets Icon in Taskbar will be shown." />
<CheckBox Name="WPFToggleTaskbarWidgets" Style="{StaticResource ColorfulToggleSwitchStyle}" Margin="2.5,0"/>
</StackPanel>
<Label Content="Performance Plans" FontSize="16"/>
<Button Name="WPFAddUltPerf" Content="Add and Activate Ultimate Performance Profile" HorizontalAlignment = "Left" Width="300" Margin="5" Padding="20,5" />
<Button Name="WPFRemoveUltPerf" Content="Remove Ultimate Performance Profile" HorizontalAlignment = "Left" Width="300" Margin="5" Padding="20,5" />
<Label Content="Shortcuts" FontSize="16"/>
<Button Name="WPFWinUtilShortcut" Content="Create WinUtil Shortcut" HorizontalAlignment = "Left" Width="300" Margin="5" Padding="20,5" />

</StackPanel>
</Border>


                    <StackPanel Background="{MainBackgroundColor}" Orientation="Horizontal" HorizontalAlignment="Left" Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="2" Margin="10">
                        <Label Content="Recommended Selections:" FontSize="14" VerticalAlignment="Center"/>
                        <Button Name="WPFdesktop" Content=" Desktop " Margin="1"/>
                        <Button Name="WPFlaptop" Content=" Laptop " Margin="1"/>
                        <Button Name="WPFminimal" Content=" Minimal " Margin="1"/>
                        <Button Name="WPFclear" Content=" Clear " Margin="1"/>
                        <Button Name="WPFGetInstalledTweaks" Content=" Get Installed " Margin="1"/>
                    </StackPanel>
                    <Border Grid.ColumnSpan="2" Grid.Row="2" Grid.Column="0">
                        <StackPanel Background="{MainBackgroundColor}" Orientation="Horizontal" HorizontalAlignment="Left">
                            <TextBlock Padding="10">
                                Note: Hover over items to get a better description. Please be careful as many of these tweaks will heavily modify your system.
                                <LineBreak/>Recommended selections are for normal users and if you are unsure do NOT check anything else!
                            </TextBlock>
                        </StackPanel>
                    </Border>

                    </Grid>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="Config" Visibility="Collapsed" Name="WPFTab3">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                <Grid Background="Transparent">
                    <Grid.ColumnDefinitions>
<ColumnDefinition Width="*"/>
<ColumnDefinition Width="*"/>
</Grid.ColumnDefinitions>
<Border Grid.Row="1" Grid.Column="0">
<StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
<Label Content="Features" FontSize="16"/>
<CheckBox Name="WPFFeaturesdotnet" Content="All .Net Framework (2,3,4)" Margin="5,0"  ToolTip=".NET and .NET Framework is a developer platform made up of tools, programming languages, and libraries for building many different types of applications."/>
<CheckBox Name="WPFFeatureshyperv" Content="HyperV Virtualization" Margin="5,0"  ToolTip="Hyper-V is a hardware virtualization product developed by Microsoft that allows users to create and manage virtual machines."/>
<CheckBox Name="WPFFeatureslegacymedia" Content="Legacy Media (WMP, DirectPlay)" Margin="5,0"  ToolTip="Enables legacy programs from previous versions of windows"/>
<CheckBox Name="WPFFeaturenfs" Content="NFS - Network File System" Margin="5,0"  ToolTip="Network File System (NFS) is a mechanism for storing files on a network."/>
<CheckBox Name="WPFFeatureEnableSearchSuggestions" Content="Enable Search Box Web Suggestions in Registry(explorer restart)" Margin="5,0"  ToolTip="Enables web suggestions when searching using Windows Search."/>
<CheckBox Name="WPFFeatureDisableSearchSuggestions" Content="Disable Search Box Web Suggestions in Registry(explorer restart)" Margin="5,0"  ToolTip="Disables web suggestions when searching using Windows Search."/>
<CheckBox Name="WPFFeatureRegBackup" Content="Enable Daily Registry Backup Task 12.30am" Margin="5,0"  ToolTip="Enables daily registry backup, previously disabled by Microsoft in Windows 10 1803."/>
<CheckBox Name="WPFFeatureEnableLegacyRecovery" Content="Enable Legacy F8 Boot Recovery" Margin="5,0"  ToolTip="Enables Advanced Boot Options screen that lets you start Windows in advanced troubleshooting modes."/>
<CheckBox Name="WPFFeatureDisableLegacyRecovery" Content="Disable Legacy F8 Boot Recovery" Margin="5,0"  ToolTip="Disables Advanced Boot Options screen that lets you start Windows in advanced troubleshooting modes."/>
<CheckBox Name="WPFFeaturewsl" Content="Windows Subsystem for Linux" Margin="5,0"  ToolTip="Windows Subsystem for Linux is an optional feature of Windows that allows Linux programs to run natively on Windows without the need for a separate virtual machine or dual booting."/>
<CheckBox Name="WPFFeaturesandbox" Content="Windows Sandbox" Margin="5,0"  ToolTip="Windows Sandbox is a lightweight virtual machine that provides a temporary desktop environment to safely run applications and programs in isolation."/>
<Button Name="WPFFeatureInstall" Content="Install Features" HorizontalAlignment = "Left" Width="150" Margin="5" Padding="20,5" />
<Label Content="Fixes" FontSize="16"/>
<Button Name="WPFPanelAutologin" Content="Set Up Autologin" HorizontalAlignment = "Left" Width="300" Margin="5" Padding="20,5" />
<Button Name="WPFFixesUpdate" Content="Reset Windows Update" HorizontalAlignment = "Left" Width="300" Margin="5" Padding="20,5" />
<Button Name="WPFFixesNetwork" Content="Reset Network" HorizontalAlignment = "Left" Width="300" Margin="5" Padding="20,5" />
<Button Name="WPFPanelDISM" Content="System Corruption Scan" HorizontalAlignment = "Left" Width="300" Margin="5" Padding="20,5" />
<Button Name="WPFFixesWinget" Content="WinGet Reinstall" HorizontalAlignment = "Left" Width="300" Margin="5" Padding="20,5" />
<Button Name="WPFRunAdobeCCCleanerTool" Content="Remove Adobe Creative Cloud" HorizontalAlignment = "Left" Width="300" Margin="5" Padding="20,5" />

</StackPanel>
</Border>
<Border Grid.Row="1" Grid.Column="1">
<StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
<Label Content="Legacy Windows Panels" FontSize="16"/>
<Button Name="WPFPanelcontrol" Content="Control Panel" HorizontalAlignment = "Left" Width="200" Margin="5" Padding="20,5" />
<Button Name="WPFPanelnetwork" Content="Network Connections" HorizontalAlignment = "Left" Width="200" Margin="5" Padding="20,5" />
<Button Name="WPFPanelpower" Content="Power Panel" HorizontalAlignment = "Left" Width="200" Margin="5" Padding="20,5" />
<Button Name="WPFPanelregion" Content="Region" HorizontalAlignment = "Left" Width="200" Margin="5" Padding="20,5" />
<Button Name="WPFPanelsound" Content="Sound Settings" HorizontalAlignment = "Left" Width="200" Margin="5" Padding="20,5" />
<Button Name="WPFPanelsystem" Content="System Properties" HorizontalAlignment = "Left" Width="200" Margin="5" Padding="20,5" />
<Button Name="WPFPaneluser" Content="User Accounts" HorizontalAlignment = "Left" Width="200" Margin="5" Padding="20,5" />

</StackPanel>
</Border>


                    </Grid>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="Updates" Visibility="Collapsed" Name="WPFTab4">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                <Grid Background="Transparent">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Border Grid.Row="0" Grid.Column="0">
                        <StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
                            <Button Name="WPFUpdatesdefault" FontSize="16" Content="Default (Out of Box) Settings" Margin="20,4,20,10" Padding="10"/>
                            <TextBlock Margin="20,0,20,0" Padding="10" TextWrapping="WrapWithOverflow" MaxWidth="300">This is the default settings that come with Windows. <LineBreak/><LineBreak/> No modifications are made and will remove any custom windows update settings.<LineBreak/><LineBreak/>Note: If you still encounter update errors, reset all updates in the config tab. That will restore ALL Microsoft Update Services from their servers and reinstall them to default settings.</TextBlock>
                        </StackPanel>
                    </Border>
                    <Border Grid.Row="0" Grid.Column="1">
                        <StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
                            <Button Name="WPFUpdatessecurity" FontSize="16" Content="Security (Recommended) Settings" Margin="20,4,20,10" Padding="10"/>
                            <TextBlock Margin="20,0,20,0" Padding="10" TextWrapping="WrapWithOverflow" MaxWidth="300">This is my recommended setting I use on all computers.<LineBreak/><LineBreak/> It will delay feature updates by 2 years and will install security updates 4 days after release.<LineBreak/><LineBreak/>Feature Updates: Adds features and often bugs to systems when they are released. You want to delay these as long as possible.<LineBreak/><LineBreak/>Security Updates: Typically these are pressing security flaws that need to be patched quickly. You only want to delay these a couple of days just to see if they are safe and don''t break other systems. You don''t want to go without these for ANY extended periods of time.</TextBlock>
                        </StackPanel>
                    </Border>
                    <Border Grid.Row="0" Grid.Column="2">
                        <StackPanel Background="{MainBackgroundColor}" SnapsToDevicePixels="True">
                            <Button Name="WPFUpdatesdisable" FontSize="16" Content="Disable ALL Updates (NOT RECOMMENDED!)" Margin="20,4,20,10" Padding="10,10,10,10"/>
                            <TextBlock Margin="20,0,20,0" Padding="10" TextWrapping="WrapWithOverflow" MaxWidth="300">This completely disables ALL Windows Updates and is NOT RECOMMENDED.<LineBreak/><LineBreak/> However, it can be suitable if you use your system for a select purpose and do not actively browse the internet. <LineBreak/><LineBreak/>Note: Your system will be easier to hack and infect without security updates.</TextBlock>
                            <TextBlock Text=" " Margin="20,0,20,0" Padding="10" TextWrapping="WrapWithOverflow" MaxWidth="300"/>
                        </StackPanel>
                        </Border>
                    </Grid>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="MicroWin" Visibility="Collapsed" Name="WPFTab5" Width="Auto" Height="Auto">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                <Grid Width="Auto" Height="Auto">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="3*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*" />
                    </Grid.RowDefinitions>
                    <Border Grid.Row="0" Grid.Column="0"
                        VerticalAlignment="Stretch"
                        HorizontalAlignment="Stretch">
                    <StackPanel Name="MicrowinMain" Background="{MainBackgroundColor}" SnapsToDevicePixels="True" Grid.Column="0" Grid.Row="0">
                        <StackPanel Background="Transparent" SnapsToDevicePixels="True" Margin="1">
                            <CheckBox x:Name="WPFMicrowinDownloadFromGitHub" Content="Download oscdimg.exe from CTT Github repo" IsChecked="False" Margin="1" />
                            <TextBlock Margin="5" Padding="1" TextWrapping="Wrap" Foreground="{ComboBoxForegroundColor}">
                                Choose a Windows ISO file that you''ve downloaded <LineBreak/>
                                Check the status in the console
                            </TextBlock>
                            <CheckBox x:Name="WPFMicrowinISOScratchDir" Content="Use ISO directory for ScratchDir " IsChecked="False" Margin="1"
                                ToolTip="Use ISO directory for ScratchDir " />

                            <Button Name="MicrowinScratchDirBT" Margin="2" Padding="1">
                              <Button.Content>
                                <TextBox Name="MicrowinScratchDirBox" Background="Transparent" BorderBrush="{MainForegroundColor}"
                                    Text="Scratch" Padding="0"
                                    ToolTip="Alt Path For Scratch Directory" BorderThickness="1"
                                    Margin="0,0,0,3" HorizontalAlignment="Left"
                                    IsReadOnly="False"
                                    Height="Auto"
                                    Width="110"
                                    Foreground="{ButtonForegroundColor}"
                                  />
                              </Button.Content>
                            </Button>
                            <TextBox Name="MicrowinFinalIsoLocation" Background="Transparent" BorderBrush="{MainForegroundColor}"
                                Text="ISO location will be printed here"
                                Margin="2"
                                IsReadOnly="True"
                                TextWrapping="Wrap"
                                Foreground="{LabelboxForegroundColor}"
                            />
                            <Button Name="WPFGetIso" Margin="2" Padding="15">
                                <Button.Content>
                                    <TextBlock Background="Transparent" Foreground="{ButtonForegroundColor}">
                                        Select Windows <Underline>I</Underline>SO
                                    </TextBlock>
                                </Button.Content>
                            </Button>
                        </StackPanel>
                        <!-- Visibility="Hidden" -->
                        <StackPanel Name="MicrowinOptionsPanel" HorizontalAlignment="Left" SnapsToDevicePixels="True" Margin="1" Visibility="Hidden">
                            <TextBlock Margin="6" Padding="1" TextWrapping="Wrap">Choose Windows SKU</TextBlock>
                            <ComboBox x:Name = "MicrowinWindowsFlavors" Margin="1" />
                            <TextBlock Margin="6" Padding="1" TextWrapping="Wrap">Choose Windows features you want to remove from the ISO</TextBlock>
                            <CheckBox Name="WPFMicrowinKeepProvisionedPackages" Content="Keep Provisioned Packages" Margin="5,0" ToolTip="Do not remove Microsoft Provisioned packages from the ISO."/>
                            <CheckBox Name="WPFMicrowinKeepAppxPackages" Content="Keep Appx Packages" Margin="5,0" ToolTip="Do not remove Microsoft Appx packages from the ISO."/>
                            <CheckBox Name="WPFMicrowinKeepDefender" Content="Keep Defender" Margin="5,0" IsChecked="True" ToolTip="Do not remove Microsoft Antivirus from the ISO."/>
                            <CheckBox Name="WPFMicrowinKeepEdge" Content="Keep Edge" Margin="5,0" IsChecked="True" ToolTip="Do not remove Microsoft Edge from the ISO."/>
                            <Rectangle Fill="{MainForegroundColor}" Height="2" HorizontalAlignment="Stretch" Margin="0,10,0,10"/>
                            <CheckBox Name="MicrowinInjectDrivers" Content="Inject drivers (I KNOW WHAT I''M DOING)" Margin="5,0" IsChecked="False" ToolTip="Path to unpacked drivers all sys and inf files for devices that need drivers"/>
                            <TextBox Name="MicrowinDriverLocation" Background="Transparent" BorderThickness="1" BorderBrush="{MainForegroundColor}"
                                Margin="6"
                                Text=""
                                IsReadOnly="False"
                                TextWrapping="Wrap"
                                Foreground="{LabelboxForegroundColor}"
                                ToolTip="Path to unpacked drivers all sys and inf files for devices that need drivers"
                            />
                            <Rectangle Fill="{MainForegroundColor}" Height="2" HorizontalAlignment="Stretch" Margin="0,10,0,10"/>
                            <CheckBox Name="WPFMicrowinCopyToUsb" Content="Copy to Ventoy" Margin="5,0" IsChecked="False" ToolTip="Copy to USB disk with a label Ventoy"/>
                            <Rectangle Fill="{MainForegroundColor}" Height="2" HorizontalAlignment="Stretch" Margin="0,10,0,10"/>
                            <Button Name="WPFMicrowin" Content="Start the process" Margin="2" Padding="15"/>
                        </StackPanel>
                        <StackPanel HorizontalAlignment="Left" SnapsToDevicePixels="True" Margin="1" Visibility="Collapsed">
                            <TextBlock Name="MicrowinIsoDrive" VerticalAlignment="Center"  Margin="1" Padding="1" TextWrapping="WrapWithOverflow" Foreground="{ComboBoxForegroundColor}"/>
                            <TextBlock Name="MicrowinIsoLocation" VerticalAlignment="Center"  Margin="1" Padding="1" TextWrapping="WrapWithOverflow" Foreground="{ComboBoxForegroundColor}"/>
                            <TextBlock Name="MicrowinMountDir" VerticalAlignment="Center"  Margin="1" Padding="1" TextWrapping="WrapWithOverflow" Foreground="{ComboBoxForegroundColor}"/>
                            <TextBlock Name="MicrowinScratchDir" VerticalAlignment="Center"  Margin="1" Padding="1" TextWrapping="WrapWithOverflow" Foreground="{ComboBoxForegroundColor}"/>
                        </StackPanel>
                    </StackPanel>
                    </Border>
                    <Border
                        VerticalAlignment="Stretch"
                        HorizontalAlignment="Stretch"
                        Grid.Row="0" Grid.Column="1">
                        <StackPanel HorizontalAlignment="Left" Background="{MainBackgroundColor}" SnapsToDevicePixels="True" Visibility="Visible">

                            <Grid Name = "BusyMessage" Visibility="Collapsed">
                              <TextBlock Name = "BusyText" Text="NBusy" Padding="22,2,1,1" />
                              <TextBlock VerticalAlignment="Center" HorizontalAlignment="Left" FontFamily="Segoe MDL2 Assets" 
                                  FontSize="14" Margin="16,0,0,0">&#xE701;</TextBlock>
                            </Grid>                         
 
                            <TextBlock x:Name = "asciiTextBlock"
                                xml:space ="preserve"
                                HorizontalAlignment = "Center"
                                Margin = "0"
                                VerticalAlignment = "Top"
                                Height = "Auto"
                                Width = "Auto"
                                FontSize = "10"
                                FontFamily = "Courier New"
                            >
  /\/\  (_)  ___  _ __   ___  / / /\ \ \(_) _ __    
 /    \ | | / __|| ''__| / _ \ \ \/  \/ /| || ''_ \  
/ /\/\ \| || (__ | |   | (_) | \  /\  / | || | | | 
\/    \/|_| \___||_|    \___/   \/  \/  |_||_| |_| 
                            </TextBlock>
                        
                            <TextBlock Margin="15,15,15,0" 
                                Padding="8,8,8,0" 
                                VerticalAlignment="Center" 
                                TextWrapping="WrapWithOverflow" 
                                Height = "Auto"
                                Width = "Auto"
                                Foreground="{ComboBoxForegroundColor}">
                                <Bold>MicroWin features:</Bold><LineBreak/>
                                - Remove Telemetry and Tracking <LineBreak/>
                                - Add ability to use local accounts <LineBreak/>
                                - Remove Wifi requirement to finish install <LineBreak/>
                                - Ability to remove Edge <LineBreak/>
                                - Ability to remove Defender <LineBreak/>
                                - Remove Teams <LineBreak/>
                                - Apps debloat <LineBreak/>
                                <LineBreak/>
                                <LineBreak/>

                                <Bold>INSTRUCTIONS</Bold> <LineBreak/>
                                - Download the latest Windows 11 image from Microsoft <LineBreak/>
                                LINK: https://www.microsoft.com/software-download/windows11 <LineBreak/>
                                May take several minutes to process the ISO depending on your machine and connection <LineBreak/>
                                - Put it somewhere on the C:\ drive so it is easily accessible <LineBreak/>
                                - Launch WinUtil and MicroWin  <LineBreak/>
                                - Click on the "Select Windows ISO" button and wait for WinUtil to process the image <LineBreak/>
                                It will be processed and unpacked which may take some time <LineBreak/>
                                - Once complete, choose which Windows flavor you want to base your image on <LineBreak/>
                                - Choose which features you want to keep <LineBreak/>
                                - Click the "Start Process" button <LineBreak/>
                                The process of creating the Windows image may take some time, please check the console and wait for it to say "Done" <LineBreak/>
                                - Once complete, the target ISO file will be in the directory you have specified <LineBreak/>
                                - Copy this image to your Ventoy USB Stick, boot to this image, gg
                                <LineBreak/>
                                If you are injecting drivers ensure you put all your inf, sys, and dll files for each driver into a separate directory
                            </TextBlock>
                            <TextBlock Margin="15,0,15,15" 
                                Padding = "1" 
                                TextWrapping="WrapWithOverflow" 
                                Height = "Auto"
                                Width = "Auto"
                                VerticalAlignment = "Top"
                                Foreground = "{ComboBoxForegroundColor}"
                                xml:space = "preserve"
                            >
<Bold>Example:</Bold>
     C:\drivers\
          |-- Driver1\
          |   |-- Driver1.inf
          |   |-- Driver1.sys
          |-- Driver2\
          |   |-- Driver2.inf
          |   |-- Driver2.sys
          |-- OtherFiles...
                                </TextBlock>
                            </StackPanel>
                        </Border>
                    </Grid>
                </ScrollViewer>
            </TabItem>
        </TabControl>
    </Grid>
</Window>'
# SPDX-License-Identifier: MIT
# Set the maximum number of threads for the RunspacePool to the number of threads on the machine
$maxthreads = [int]$env:NUMBER_OF_PROCESSORS

# Create a new session state for parsing variables into our runspace
$hashVars = New-object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sync',$sync,$Null
$InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

# Add the variable to the session state
$InitialSessionState.Variables.Add($hashVars)

# Get every private function and add them to the session state
$functions = Get-ChildItem function:\ | Where-Object {$_.name -like "*winutil*" -or $_.name -like "*WPF*"}
foreach ($function in $functions){
    $functionDefinition = Get-Content function:\$($function.name)
    $functionEntry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $($function.name), $functionDefinition

    $initialSessionState.Commands.Add($functionEntry)
}

# Create the runspace pool
$sync.runspace = [runspacefactory]::CreateRunspacePool(
    1,                      # Minimum thread count
    $maxthreads,            # Maximum thread count
    $InitialSessionState,   # Initial session state
    $Host                   # Machine to create runspaces on
)

# Open the RunspacePool instance
$sync.runspace.Open()

# Create classes for different exceptions

    class WingetFailedInstall : Exception {
        [string] $additionalData

        WingetFailedInstall($Message) : base($Message) {}
    }

    class ChocoFailedInstall : Exception {
        [string] $additionalData

        ChocoFailedInstall($Message) : base($Message) {}
    }

    class GenericException : Exception {
        [string] $additionalData

        GenericException($Message) : base($Message) {}
    }


$inputXML = $inputXML -replace 'mc:Ignorable="d"', '' -replace "x:N", 'N' -replace '^<Win.*', '<Window'

if ((Get-WinUtilToggleStatus WPFToggleDarkMode) -eq $True) {
    if (Invoke-WinUtilGPU -eq $True) {
        $ctttheme = 'Matrix'
    }
    else {
        $ctttheme = 'Dark'
    }
}
else {
    $ctttheme = 'Classic'
}
$inputXML = Set-WinUtilUITheme -inputXML $inputXML -themeName $ctttheme

[void][System.Reflection.Assembly]::LoadWithPartialName('presentationframework')
[xml]$XAML = $inputXML

# Read the XAML file
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
try { $sync["Form"] = [Windows.Markup.XamlReader]::Load( $reader ) }
catch [System.Management.Automation.MethodInvocationException] {
    Write-Warning "We ran into a problem with the XAML code.  Check the syntax for this control..."
    Write-Host $error[0].Exception.Message -ForegroundColor Red
    If ($error[0].Exception.Message -like "*button*") {
        write-warning "Ensure your &lt;button in the `$inputXML does NOT have a Click=ButtonClick property.  PS can't handle this`n`n`n`n"
    }
}
catch {
    Write-Host "Unable to load Windows.Markup.XamlReader. Double-check syntax and ensure .net is installed."
}

#===========================================================================
# Store Form Objects In PowerShell
#===========================================================================

$xaml.SelectNodes("//*[@Name]") | ForEach-Object {$sync["$("$($psitem.Name)")"] = $sync["Form"].FindName($psitem.Name)}

$sync.keys | ForEach-Object {
    if($sync.$psitem){
        if($($sync["$psitem"].GetType() | Select-Object -ExpandProperty Name) -eq "CheckBox" `
                -and $sync["$psitem"].Name -like "WPFToggle*"){
            $sync["$psitem"].IsChecked = Get-WinUtilToggleStatus $sync["$psitem"].Name

            $sync["$psitem"].Add_Click({
                [System.Object]$Sender = $args[0]
                Invoke-WPFToggle $Sender.name
            })
        }

        if($($sync["$psitem"].GetType() | Select-Object -ExpandProperty Name) -eq "ToggleButton"){
            $sync["$psitem"].Add_Click({
                [System.Object]$Sender = $args[0]
                Invoke-WPFButton $Sender.name
            })
        }

        if($($sync["$psitem"].GetType() | Select-Object -ExpandProperty Name) -eq "Button"){
            $sync["$psitem"].Add_Click({
                [System.Object]$Sender = $args[0]
                Invoke-WPFButton $Sender.name
            })
        }

        if ($($sync["$psitem"].GetType() | Select-Object -ExpandProperty Name) -eq "TextBlock") {
            if ($sync["$psitem"].Name.EndsWith("Link")) {
                $sync["$psitem"].Add_MouseUp({
                    [System.Object]$Sender = $args[0]
                    Start-Process $Sender.ToolTip -ErrorAction Stop
                    Write-Debug "Opening: $($Sender.ToolTip)"
                })
            }

        }
    }
}

#===========================================================================
# Setup background config
#===========================================================================

# Load computer information in the background
Invoke-WPFRunspace -ScriptBlock {
    $sync.ConfigLoaded = $False
    $sync.ComputerInfo = Get-ComputerInfo
    $sync.ConfigLoaded = $True
} | Out-Null

#===========================================================================
# Setup and Show the Form
#===========================================================================

# Print the logo
Invoke-WPFFormVariables

# Check if Chocolatey is installed
Install-WinUtilChoco

# Set the titlebar
$sync["Form"].title = $sync["Form"].title + " " + $sync.version
# Set the commands that will run when the form is closed
$sync["Form"].Add_Closing({
    $sync.runspace.Dispose()
    $sync.runspace.Close()
    [System.GC]::Collect()
})

# Attach the event handler to the Click event
$sync.CheckboxFilterClear.Add_Click({
    $sync.CheckboxFilter.Text = ""
    $sync.CheckboxFilterClear.Visibility = "Collapsed"
})

# add some shortcuts for people that don't like clicking
$commonKeyEvents = {
    if ($sync.ProcessRunning -eq $true) {
        return
    }

    if ($_.Key -eq "Escape")
    {
        $sync.CheckboxFilter.SelectAll()
        $sync.CheckboxFilter.Text = ""
        $sync.CheckboxFilterClear.Visibility = "Collapsed"
        return
    }

    # don't ask, I know what I'm doing, just go...
    if (($_.Key -eq "Q" -and $_.KeyboardDevice.Modifiers -eq "Ctrl"))
    {
        $this.Close()
    }
    if ($_.KeyboardDevice.Modifiers -eq "Alt") {
        if ($_.SystemKey -eq "I") {
            Invoke-WPFButton "WPFTab1BT"
        }
        if ($_.SystemKey -eq "T") {
            Invoke-WPFButton "WPFTab2BT"
        }
        if ($_.SystemKey -eq "C") {
            Invoke-WPFButton "WPFTab3BT"
        }
        if ($_.SystemKey -eq "U") {
            Invoke-WPFButton "WPFTab4BT"
        }
        if ($_.SystemKey -eq "M") {
            Invoke-WPFButton "WPFTab5BT"
        }
        if ($_.SystemKey -eq "P") {
            Write-Host "Your Windows Product Key: $((Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey)"
        }
    }
    # shortcut for the filter box
    if ($_.Key -eq "F" -and $_.KeyboardDevice.Modifiers -eq "Ctrl") {
        if ($sync.CheckboxFilter.Text -eq "Ctrl-F to filter") {
            $sync.CheckboxFilter.SelectAll()
            $sync.CheckboxFilter.Text = ""
        }
        $sync.CheckboxFilter.Focus()
    }
}

$sync["Form"].Add_PreViewKeyDown($commonKeyEvents)

$sync["Form"].Add_MouseLeftButtonDown({
    if ($sync["SettingsPopup"].IsOpen) {
        $sync["SettingsPopup"].IsOpen = $false
    }
    $sync["Form"].DragMove()
})

$sync["Form"].Add_MouseDoubleClick({
    if ($sync["Form"].WindowState -eq [Windows.WindowState]::Normal)
    {
        $sync["Form"].WindowState = [Windows.WindowState]::Maximized;
    }
    else
    {
        $sync["Form"].WindowState = [Windows.WindowState]::Normal;
    }
})

$sync["Form"].Add_Deactivated({
    Write-Debug "WinUtil lost focus"
    if ($sync["SettingsPopup"].IsOpen) {
        $sync["SettingsPopup"].IsOpen = $false
    }
})

$sync["Form"].Add_ContentRendered({

    try {
        [void][Window]
    } catch {
Add-Type @"
        using System;
        using System.Runtime.InteropServices;
        public class Window {
            [DllImport("user32.dll")]
            public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            public static extern bool MoveWindow(IntPtr handle, int x, int y, int width, int height, bool redraw);

            [DllImport("user32.dll")]
            public static extern int GetSystemMetrics(int nIndex);
        };
        public struct RECT {
            public int Left;   // x position of upper-left corner
            public int Top;    // y position of upper-left corner
            public int Right;  // x position of lower-right corner
            public int Bottom; // y position of lower-right corner
        }
"@
    }

    foreach ($proc in (Get-Process | Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle -like "*titus*" })) {
        if ($proc.Id -ne [System.IntPtr]::Zero) {
            Write-Debug "MainWindowHandle: $($proc.Id) $($proc.MainWindowTitle) $($proc.MainWindowHandle)"
            $windowHandle = $proc.MainWindowHandle
        }
    }

    # need to experiemnt more
    # setting icon for the windows is still not working
    # $pngUrl = "https://christitus.com/images/logo-full.png"
    # $pngPath = "$env:TEMP\cttlogo.png"
    # $iconPath = "$env:TEMP\cttlogo.ico"
    # # Download the PNG file
    # Invoke-WebRequest -Uri $pngUrl -OutFile $pngPath
    # if (Test-Path -Path $pngPath) {
    #     ConvertTo-Icon -bitmapPath $pngPath -iconPath $iconPath
    # }
    # $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
    # Write-Host $icon.Handle
    # [Window]::SendMessage($windowHandle, 0x80, [IntPtr]::Zero, $icon.Handle)

    $rect = New-Object RECT
    [Window]::GetWindowRect($windowHandle, [ref]$rect)
    $width  = $rect.Right  - $rect.Left
    $height = $rect.Bottom - $rect.Top

    Write-Debug "UpperLeft:$($rect.Left),$($rect.Top) LowerBottom:$($rect.Right),$($rect.Bottom). Width:$($width) Height:$($height)"

    # Load the Windows Forms assembly
    Add-Type -AssemblyName System.Windows.Forms
    $primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen
    # Check if the primary screen is found
    if ($primaryScreen) {
        # Extract screen width and height for the primary monitor
        $screenWidth = $primaryScreen.Bounds.Width
        $screenHeight = $primaryScreen.Bounds.Height

        # Print the screen size
        Write-Debug "Primary Monitor Width: $screenWidth pixels"
        Write-Debug "Primary Monitor Height: $screenHeight pixels"

        # Compare with the primary monitor size
        if ($width -gt $screenWidth -or $height -gt $screenHeight) {
            Write-Debug "The specified width and/or height is greater than the primary monitor size."
            [void][Window]::MoveWindow($windowHandle, 0, 0, $screenWidth, $screenHeight, $True)
        } else {
            Write-Debug "The specified width and height are within the primary monitor size limits."
        }
    } else {
        Write-Debug "Unable to retrieve information about the primary monitor."
    }

    Invoke-WPFTab "WPFTab1BT"
    $sync["Form"].Focus()

    # maybe this is not the best place to load and execute config file?
    # maybe community can help?
    if ($PARAM_CONFIG){
        Invoke-WPFImpex -type "import" -Config $PARAM_CONFIG
        if ($PARAM_RUN){
            while ($sync.ProcessRunning) {
                Start-Sleep -Seconds 5
            }
            Start-Sleep -Seconds 5

            Write-Host "Applying tweaks..."
            Invoke-WPFtweaksbutton
            while ($sync.ProcessRunning) {
                Start-Sleep -Seconds 5
            }
            Start-Sleep -Seconds 5

            Write-Host "Installing features..."
            Invoke-WPFFeatureInstall
            while ($sync.ProcessRunning) {
                Start-Sleep -Seconds 5
            }

            Start-Sleep -Seconds 5
            Write-Host "Installing applications..."
            while ($sync.ProcessRunning) {
                Start-Sleep -Seconds 1
            }
            Invoke-WPFInstall
            Start-Sleep -Seconds 5

            Write-Host "Done."
        }
    }

})

$sync["CheckboxFilter"].Add_TextChanged({

    if ($sync.CheckboxFilter.Text -ne "") {
        $sync.CheckboxFilterClear.Visibility = "Visible"
    }
    else {
        $sync.CheckboxFilterClear.Visibility = "Collapsed"
    }

    $filter = Get-WinUtilVariables -Type CheckBox
    $CheckBoxes = $sync.GetEnumerator() | Where-Object { $psitem.Key -in $filter }

    foreach ($CheckBox in $CheckBoxes) {
        # Check if the checkbox is null or if it doesn't have content
        if ($CheckBox -eq $null -or $CheckBox.Value -eq $null -or $CheckBox.Value.Content -eq $null) {
            continue
        }

        $textToSearch = $sync.CheckboxFilter.Text.ToLower()
        $checkBoxName = $CheckBox.Key
        $textBlockName = $checkBoxName + "Link"

        # Retrieve the corresponding text block based on the generated name
        $textBlock = $sync[$textBlockName]

        if ($CheckBox.Value.Content.ToLower().Contains($textToSearch)) {
            $CheckBox.Value.Visibility = "Visible"
             # Set the corresponding text block visibility
            if ($textBlock -ne $null) {
                $textBlock.Visibility = "Visible"
            }
        }
        else {
             $CheckBox.Value.Visibility = "Collapsed"
            # Set the corresponding text block visibility
            if ($textBlock -ne $null) {
                $textBlock.Visibility = "Collapsed"
            }
        }
    }

})

# Define event handler for button click
$sync["SettingsButton"].Add_Click({
    Write-Debug "SettingsButton clicked"
    if ($sync["SettingsPopup"].IsOpen) {
        $sync["SettingsPopup"].IsOpen = $false
    }
    else {
        $sync["SettingsPopup"].IsOpen = $true
    }
    $_.Handled = $false
})

# Define event handlers for menu items
$sync["ImportMenuItem"].Add_Click({
  # Handle Import menu item click
  Write-Debug "Import clicked"
  $sync["SettingsPopup"].IsOpen = $false
  Invoke-WPFImpex -type "import"
  $_.Handled = $false
})

$sync["ExportMenuItem"].Add_Click({
    # Handle Export menu item click
    Write-Debug "Export clicked"
    $sync["SettingsPopup"].IsOpen = $false
    Invoke-WPFImpex -type "export"
    $_.Handled = $false
})

$sync["AboutMenuItem"].Add_Click({
    # Handle Export menu item click
    Write-Debug "About clicked"
    $sync["SettingsPopup"].IsOpen = $false
    # Example usage
    $authorInfo = @"
Author   : @christitustech
Runspace : @DeveloperDurp
GUI      : @KonTy
MicroWin : @KonTy
GitHub   : https://github.com/ChrisTitusTech/winutil
Version  : $($sync.version)
"@
    Show-CustomDialog -Message $authorInfo -Width 400
})

$sync["Form"].ShowDialog() | out-null
Stop-Transcript
