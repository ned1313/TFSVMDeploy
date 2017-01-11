<# Custom Script for Windows #>
#let's set some variables
$installPath = "F:\Program Files\Microsoft Team Foundation Server 14.0"

$isoURL = "https://nbinstallers.blob.core.windows.net/tfs/en_team_foundation_server_2015_update_3_x86_x64_dvd_8945842.iso"

$unattendFileURL = "https://nbinstallers.blob.core.windows.net/tfs/unattendtfsbasic.ini"

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

#Get the data disk prepared
Get-Disk |

Where partitionstyle -eq ‘raw’ |

Initialize-Disk -PartitionStyle GPT -PassThru |

New-Partition -DriveLetter F -UseMaximumSize |

Format-Volume -FileSystem NTFS -NewFileSystemLabel “TFSInstall” -Confirm:$false

mkdir $installPath

#Turn off the pesky IE ESC, optionally UAC can be disabled too
Disable-InternetExplorerESC

#Transfer the installer ISO and config file
Start-BitsTransfer -Source $isoURL -Destination $dest

Start-BitsTransfer -Source $unattendFileURL -Destination $dest

#Get the files that were transferred since Start-BitsTransfer doesn't really help with that
$isoFile = Get-ChildItem -Path $dest -Filter ($isoURL.Split("/") | select -Last 1)

$unattendFile = Get-ChildItem -Path $dest -Filter ($unattendFileURL.Split("/") | select -Last 1)

#Mount the ISO to get to the installers and retrieve the mount point
Mount-DiskImage -ImagePath $isoFile.FullName -PassThru -ov mount
 
$mount = ($mount | Get-Volume).DriveLetter + ":"

cd $mount

#Run the TFS installer and wait until the process completes
.\Tfs2015.3.exe /Full /Quiet /CustomInstallPath $installPath

do{Wait-Event -Timeout 5; $proc = Get-Process -Name "Tfs2015.3" -ErrorAction SilentlyContinue; Write-Output "TFS process still running"}while($proc)

#Run the basic unattended install for TFS
cd "$installPath\Tools"

.\tfsconfig unattend /configure /type:basic
