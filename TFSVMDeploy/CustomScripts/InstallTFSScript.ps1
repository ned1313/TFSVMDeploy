<# Custom Script for Windows #>
#let's set some variables
$installPath = "F:\Program Files\Microsoft Team Foundation Server 14.0"

$isoURL = "https://nbinstallers.blob.core.windows.net/tfs/en_team_foundation_server_2015_update_3_x86_x64_dvd_8945842.iso"

$VSCisoURL = "https://nbinstallers.blob.core.windows.net/tfs/vs2015.3.com_enu.iso"

$VSCAdminURL = "https://nbinstallers.blob.core.windows.net/tfs/AdminDeployment.xml"

$dest = "F:\"

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
		[string] $destPath
	)
	Start-BitsTransfer -Source $URL -Destination $destPath
	$file = Get-ChildItem -Path $destPath -Filter ($URL.Split("/") | select -Last 1)
	return $file
}

#Get the data disk prepared
Get-Disk |

Where partitionstyle -eq ‘raw’ |

Initialize-Disk -PartitionStyle GPT -PassThru |

New-Partition -DriveLetter F -UseMaximumSize |

Format-Volume -FileSystem NTFS -NewFileSystemLabel “TFSInstall” -Confirm:$false

mkdir $installPath

#Turn off the pesky IE ESC, optionally UAC can be disabled too
Disable-InternetExplorerESC

#Get the files to install TFS and VSC 2015
$isoFile = Copy-AzureBlob -URL $isoURL -destPath $dest

$VSCisoFile = Copy-AzureBlob -URL $VSCisoURL -destPath $dest

$VSCAdminFile = Copy-AzureBlob -URL $VSCAdminURL -destPath $dest

#Mount the TFS ISO to get to the installers and retrieve the mount point
Mount-DiskImage -ImagePath $isoFile.FullName -PassThru -ov mount
 
$mount = ($mount | Get-Volume).DriveLetter + ":"

cd $mount

#Run the TFS installer and wait until the process completes
.\Tfs2015.3.exe /Full /Quiet /CustomInstallPath $installPath

do{Wait-Event -Timeout 5; $proc = Get-Process -Name "Tfs2015.3" -ErrorAction SilentlyContinue; Write-Output "TFS process still running"}while($proc)

#Run the basic unattended install for TFS
cd "$installPath\Tools"

.\tfsconfig unattend /configure /type:basic

#Enable public access of TFS site
Get-NetFirewallRule -DisplayName "Team Foundation Server:8080" | Set-NetFirewallRule -Profile Any

Dismount-DiskImage -ImagePath $isoFile.FullName

#Mount the VS Community ISO to get to the installers and retrieve the mount point
Mount-DiskImage -ImagePath $VSCisoFile.FullName -PassThru -ov mount
 
$mount = ($mount | Get-Volume).DriveLetter + ":"

cd $mount

.\vs_community.exe /adminfile $VSCAdminFile.FullName /quiet /norestart

do{Wait-Event -Timeout 5; $proc = Get-Process -Name "vs_community" -ErrorAction SilentlyContinue; Write-Output "VS 2015 process still running"}while($proc)

mkdir $dest\Agent

cd "$installPath\Build\Agent"

.\VsoAgent.exe /Configure /RunningAsService /ServerUrl:http://localhost:8080/tfs /WorkFolder:$dest\Agent\_work /StartMode:Automatic /Name:Agent-Default /PoolName:default /WindowsServiceLogonAccount:"NT AUTHORITY\LOCAL SERVICE"