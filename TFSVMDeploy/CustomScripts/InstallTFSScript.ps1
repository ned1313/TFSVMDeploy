<# Custom Script for Windows #>
param(
 [string] $FileContainerURL,
 [string] $FileContainerSASToken
)

Write-Output "File Container URL set to $FileContainerURL"
Write-Output "File Containre SAS Token set to $FileContainerSASToken"

#let's set some variables
$installPath = "F:\Program Files\Microsoft Team Foundation Server 14.0"

$isoFileName = "en_team_foundation_server_2015_update_3_x86_x64_dvd_8945842.iso"

$VSCisoFileName = "vs2015.3.com_enu.iso"

$VSCAdminFileName = "AdminDeployment.xml"

$dest = "F:\"

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

Write-Output "Preparing Disks"

#Get the data disk prepared
Get-Disk |

Where partitionstyle -eq ‘raw’ |

Initialize-Disk -PartitionStyle GPT -PassThru |

New-Partition -DriveLetter F -UseMaximumSize |

Format-Volume -FileSystem NTFS -NewFileSystemLabel “TFSInstall” -Confirm:$false

Write-Output "Create install path and disable ESC"
mkdir $installPath

#Turn off the pesky IE ESC, optionally UAC can be disabled too
Disable-InternetExplorerESC

#Get the files to install TFS and VSC 2015
$isoFile = Copy-AzureBlob -URL $FileContainerURL -SASToken $FileContainerSASToken -FileName $isoFileName -destPath $dest

Write-Output "TFS ISO set to $isoFile"

$VSCisoFile = Copy-AzureBlob -URL $FileContainerURL -SASToken $FileContainerSASToken -FileName $VSCisoFileName -destPath $dest

Write-Output "VSC ISO set to $VSCisoFile"

$VSCAdminFile = Copy-AzureBlob -URL $FileContainerURL -SASToken $FileContainerSASToken -FileName $VSCAdminFileName -destPath $dest

Write-Output "VSC admin file set to $VSCAdminFile"

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

#Mount the VS Community ISO to get to the installers and retrieve the mount point
Write-Output "Mounting VSC ISO to perform installation"
Mount-DiskImage -ImagePath $VSCisoFile -PassThru -ov mount
 
$mount = ($mount | Get-Volume).DriveLetter + ":"

cd $mount

Write-Output "Running VSC Installer"
.\vs_community.exe /adminfile $VSCAdminFile /quiet /norestart

do{Wait-Event -Timeout 5; $proc = Get-Process -Name "vs_community" -ErrorAction SilentlyContinue; Write-Output "VS 2015 process still running"}while($proc)

mkdir $dest\Agent

cd "$installPath\Build\Agent"

Write-Output "Running Build Agent installation"

 .\VsoAgent.exe /Configure /RunningAsService /ServerUrl:http://localhost:8080/tfs /WorkFolder:$dest\Agent\_work /StartMode:Automatic /Name:Agent-Default /PoolName:default /WindowsServiceLogonAccount:"NT AUTHORITY\LOCAL SERVICE" /WindowsServiceLogonPassword:"password" /Force

Write-Output "Dismount VSC ISO"
Dismount-DiskImage -ImagePath $VSCisoFile