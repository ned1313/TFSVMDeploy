<# Custom Script for Windows #>
param(
 [string] $FileContainerURL,
 [string] $FileContainerSASToken,
 [int] $InstallStep = 0
)

$FileContainerSASToken = "sv=2015-04-05&sr=c&sig=y5cfpbNbhUT3TFGatA4X8AmUpoD5DvH6uSsJClGM0XA%3D&se=
2017-04-05T19%3A21%3A25Z&sp=rl"

$FileContainerURL = "https://nbinstallers.blob.core.windows.net/tfs"

Write-Output "File Container URL set to $FileContainerURL"
Write-Output "File Container SAS Token set to $FileContainerSASToken"

#let's set some variables
$installPath = "F:\Program Files\Microsoft Team Foundation Server 14.0"

$isoFileName = "en_team_foundation_server_2015_update_3_x86_x64_dvd_8945842.iso"

$dest = "F:\"

$ScheduledTaskName = "InstallTFSScript.ps1"

$task = Get-ScheduledTask -TaskName $ScheduledTaskName -ErrorAction SilentlyContinue
if($task){
	Unregister-ScheduledTask -TaskName $ScheduledTaskName
}

Write-Output "Loading functions"

#now a few functions
function Disable-InternetExplorerESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -Force
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -Force
    Stop-Process -Name Explorer -Force
    Write-Output "IE Enhanced Security Configuration (ESC) has been disabled."
}
function Enable-InternetExplorerESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 1 -Force
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 1 -Force
    Stop-Process -Name Explorer
    Write-Output "IE Enhanced Security Configuration (ESC) has been enabled."
}
function Disable-UserAccessControl {
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 00000000 -Force
    Write-Output "User Access Control (UAC) has been disabled."
}
function Copy-AzureBlob {
	param(
		[string] $URL,
		[string] $SASToken,
		[string] $FileName,
		[string] $destPath
	)
	$URI = "$URL/" + $FileName + "?$SASToken"
	
	Start-BitsTransfer -Source $URI -Destination "$destPath\$FileName"
	return "$destPath\$FileName"
}

function PrepareDisks {
	Write-Output "Preparing Disks"

	#Get the data disk prepared
	Get-Disk |

	Where partitionstyle -eq ‘raw’ |

	Initialize-Disk -PartitionStyle GPT -PassThru |

	New-Partition -DriveLetter F -UseMaximumSize |

	Format-Volume -FileSystem NTFS -NewFileSystemLabel “TFSInstall” -Confirm:$false
}

function PrepareSystem{
	Write-Output "Create install path and disable ESC"
	mkdir $installPath

	#Turn off the pesky IE ESC, optionally UAC can be disabled too
	Disable-InternetExplorerESC

}

function CopyFiles {
	#Get the files to install TFS and VSC 2015
	$isoFile = Copy-AzureBlob -URL $FileContainerURL -SASToken $FileContainerSASToken -FileName $isoFileName -destPath $dest

	Write-Output "TFS ISO set to $isoFile"

}

function InstallTFS {
	#Mount the TFS ISO to get to the installers and retrieve the mount point
	Write-Output "Mounting TFS ISO to perform installation"

	Mount-DiskImage -ImagePath $isoFile -PassThru -ov mount
 
	$mount = ($mount | Get-Volume).DriveLetter + ":"

	cd $mount

	#Run the TFS installer and wait until the process completes
	Write-Output "Running TFS Installer"
	.\Tfs2015.3.exe /Full /Quiet /CustomInstallPath $installPath

	do{Wait-Event -Timeout 5; $proc = Get-Process -Name "Tfs2015.3" -ErrorAction SilentlyContinue; Write-Output "TFS process still running"}while($proc)

	#Run the basic unattended install for TFS
	cd "$installPath\Tools"

	Write-Output "Running TFS configuration"
	.\tfsconfig unattend /configure /type:basic

	Write-Output "Enable firewall rule"
	#Enable public access of TFS site
	Get-NetFirewallRule -DisplayName "Team Foundation Server:8080" | Set-NetFirewallRule -Profile Any

	Write-Output "Dismount TFS ISO"
	Dismount-DiskImage -ImagePath $isoFile
}

function InstallWebPi {
	#Get the WebPlatformInstaller from Microsoft
	Invoke-WebRequest -Uri http://go.microsoft.com/fwlink/?LinkId=255386 -OutFile $dest\wpilauncher.exe

	cd $dest

	.\wpilauncher.exe

	while(-not (Test-Path 'C:\Program Files\Microsoft\Web Platform Installer\WebpiCmd.exe')){
		Wait-Event -Timeout 5
	}

	$proc = Get-Process -Name "WebPlatformInstaller" -ErrorAction SilentlyContinue
	if($proc){
		Stop-Process -Name "WebPlatformInstaller" -Force
	}

}

function InstallVSC {
	& 'C:\Program Files\Microsoft\Web Platform Installer\WebpiCmd.exe' /Install /Products:"VS2015CommunityAzurePack.2.9" /AcceptEULA
}

function InstallWMF5 {
	Invoke-WebRequest -Uri http://go.microsoft.com/fwlink/?LinkId=717507 -OutFile $dest\Win8.1AndW2K12R2-KB3134758-x64.msu
	wusa.exe $dest\Win8.1AndW2K12R2-KB3134758-x64.msu /quiet 
}

function InstallAzurePowerShell {

 # To install the module for all users on your computer. Run this command in an elevated PowerShell session
 Get-Module -ListAvailable | where-Object {$_.Name -like “Azure*”} | Uninstall-Module
 Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
 Install-Module -Name AzureRM -RequiredVersion 1.2.8 -Force
 Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

}

function CreateTFSBuildAgent{
	mkdir $dest\Agent

	cd "$installPath\Build\Agent"

	Write-Output "Running Build Agent installation"

	 .\VsoAgent.exe /Configure /RunningAsService /ServerUrl:http://localhost:8080/tfs /WorkFolder:$dest\Agent\_work /StartMode:Automatic /Name:Agent-Default /PoolName:default /WindowsServiceLogonAccount:"NT AUTHORITY\LOCAL SERVICE" /WindowsServiceLogonPassword:"password" /Force

}

function CreateResumeTask {
	param(
		[int] $InstallStep
	)
	$trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay "00:01:00"
	$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NonInteractive -NoProfile -File $PSCommandPath -InstallStep $InstallStep" -WorkingDirectory $PSScriptRoot
	$settings = New-ScheduledTaskSettingsSet
	$task = New-ScheduledTask -Action $action -Description "InstallTFSScript.ps1" -Settings $settings -Trigger $trigger
	Register-ScheduledTask "InstallTFSScript.ps1" -InputObject $task -User System 

}

if($InstallStep -eq 1){
	PrepareDisks
	PrepareSystem
	CopyFiles
	InstallTFS
	InstallWebPi
	InstallVSC
	$InstallStep++
	CreateResumeTask -InstallStep $InstallStep
	InstallWMF5
}

if($InstallStep -eq 2){
	InstallAzurePowerShell
	CreateTFSBuildAgent
	$InstallStep++
}