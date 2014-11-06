##########
# VMware vSphere PowerCLI script to find out on which ESXi hosts specific VMs are running, by connecting to the hosts directly when vCenter is unavailable.
# 
# For this script you can provide either a list of ESXi hosts to connect to or an alias for a cluster which member hosts you pre-populated in the script, along with one or more search strings to look for.
# This search is matched against the VM names and outputs the list of found VMs with their current power state and the host running the VM. This way you can get a VM-Host mapping of not only your vCenter VM, but other VMs as well.
# 
# Github: https://github.com/alpacacode/Homebrewn-Scripts
# Reference: http://alpacapowered.wordpress.com/2013/07/11/script-powercli-find-out-the-host-on-which-vms-are-running-when-vcenter-is-down/
########

PARAM(
    $Hostlist,
    $Cluster,
    $Query
)
# Adjust the cluster match list accordingly
if ((($Hostlist -eq $null) -and ($Cluster -notmatch "^(PROD|TEST|DMZ)$")) -or ($Query -eq $null) ) {
    Write "Wrong parameters/syntax. Usage: `n-hostlist [host1,host2,...] `nOR`n-cluster [PROD|DMZ|TEST] `nAND`n -query [string1,string2,...]."
    Exit
}
# Populate the cluster list with your clusters and hostnames so you don't have to enter a list of hosts manually every time with the -Hostlist parameter
switch ($Cluster) { 
    "PROD"    { $Hostlist = "prodhost01.local","prodhost02.local","prodhost03.local","prodhost04.local" }
    "DMZ"    { $Hostlist = "dmzhost01.local","dmzhost02.local" }
    "TEST"    { $Hostlist = "testhost01.local","testhost02.local" }
}
Write "Provide local login credentials for the ESXi hosts:`n$HostList`n"
$HostCreds = Get-Credential root
Write "Connecting to $Hostlist"
Connect-VIServer -Server $Hostlist -Credential $HostCreds
if ($DefaultVIServer -eq $null) {
    Write "No host connected. Exiting"
    Exit
}
foreach ($q in $Query) {
    Write "`n----------`nSearching for VMs with names containing the string `"$q`"..."
    Get-VM -Name *$q* | Sort Name | Format-Table -autosize Name, Powerstate, VMHost | Out-String
}
Disconnect-VIServer -Server * -Force -Confirm:$false
Exit
