# ABX Action to configure the Salt Minion and tun a highstate as part of a vRA deployment
# Created by Dennis Gerolymatos and Guillermo Martinez
# Version 1.0 - 24.10.2021

function handler($context, $inputs) {

#global Variables definition

$tmpl_pass = $context.getSecret($inputs.tmpl_pass)      # get password for OS image
$vcuser = $context.getSecret($inputs.vcUsername)        # get user for Vcenter connection
$vcpassword = $context.getSecret($inputs.vcPassword)    # get password for Vcenter connection
$vcfqdn = $context.getSecret($inputs.vcfqdn)            # get FQDN of Vcenter
$name = $inputs.resourceNames[0]                        # get name from the resourcenames array
$tempfilegrains = New-TemporaryFile                     # initialize tempfile for grains
$tempfileminion = New-TemporaryFile                     # initialize tempfile for minion config


#Variables definition per operative system
if ($inputs.customProperties.osType -eq "WINDOWS")
{
    $vmusername=$context.getSecret($inputs.tmpl_user_windows)       # get username for Windows image
    $restartservicescript = "restart-service salt-minion -force"    # get command for restarting minion on Windows
    $highstatescript = "c:\salt\salt-call state.highstate"          # get command for executing a highstate on windows
    $filepathgrains = "c:\salt\conf\grains"                         # path to grains file on Windows
    $filepathminion = "c:\salt\conf\minion.d\minion.conf"           # path to minion.conf file on Windows
    $scriptrevoke = "c:\salt\salt-call saltutil.revoke_auth"        # get command for revoking minion key on Windows
}
else 
{
    $vmusername=$context.getSecret($inputs.tmpl_user_linux)         # get username for Linux image
    $restartservicescript = "service salt-minion restart"           # get command for restarting minion on Linux
    $highstatescript = "salt-call state.highstate"                  # get command for executing a highstate on Linux
    $filepathgrains = "//etc/salt/grains"                           # path to grains file on Linux
    $filepathminion = "//etc/salt/minion.d/minion.conf"             # path to minion.conf file on Linux
    $scriptrevoke = "salt-call saltutil.revoke_auth"                # get command for revoking minion key on Linux
    
}

# Test if the script is called in the compute.removal.pre event topic. If yes, then run saltutil.revoke_auth
$event = $inputs.__metadata.eventTopicId
if ($event -eq "compute.removal.pre")
    {
    write-host "executing salt-call saltutil.revoke_auth..."
    Connect-VIServer $vcfqdn -User $vcuser -Password $vcpassword -Force
    $vm = Get-vm -name $name
    $runscript = Invoke-VMScript -VM $vm -ScriptText $scriptrevoke -GuestUser $vmusername -GuestPassword $tmpl_pass
    Write-Host $runscript.ScriptOutput
     
    }
else
    {
    
    
    #Vcenter connection
    write-host "Connecting to Vcenter..."
    Connect-VIServer $vcfqdn -User $vcuser -Password $vcpassword -Force
    write-host “Waiting for VM Tools to Start”
    do {
        $toolsStatus = (Get-vm -name $name | Get-View).Guest.ToolsStatus
        write-host $toolsStatus
        sleep 3
        } until ( $toolsStatus -eq ‘toolsOk’ )

    $vm = Get-vm -name $name

    
    
    # Reads Values in "grains:" and "minionconfig" literal blocks and write them to the tempfiles
    write-host "collecting key:value pairs..."
     
    $inputs.customProperties.minionconfig | add-content $tempfileminion
    $inputs.customProperties.grains | add-content $tempfilegrains
    
    # copy temp files to operative system
    write-host "copy minion.conf file to operative system..."
    $runscript = copy-vmguestfile -source $tempfileminion -destination $filepathminion -localtoguest -VM $vm -GuestUser $vmusername -GuestPassword $tmpl_pass -Force
    Write-Host $runscript.ScriptOutput
    write-host "copy grains file to operative system..."
    $runscript = copy-vmguestfile -source $tempfilegrains -destination $filepathgrains -localtoguest -VM $vm -GuestUser $vmusername -GuestPassword $tmpl_pass -Force
    Write-Host $runscript.ScriptOutput
    
    
    
    # Restart minion
    Write-Host "restarting minion..."
    $runscript = Invoke-VMScript -VM $vm -ScriptText $restartservicescript -GuestUser $vmusername -GuestPassword $tmpl_pass
    Write-Host $runscript.ScriptOutput
    
    
    
    # Run highstate
    if($inputs.customProperties.highstate -eq "true")
        {
        Write-Host "running highstate..."
        $runscript = Invoke-VMScript -VM $vm -ScriptText $highstatescript -GuestUser $vmusername -GuestPassword $tmpl_pass
        Write-Host $runscript.ScriptOutput
        }
    
    
    # Remove temp files
    remove-item $tempfilegrains -force
    remove-item $tempfileminion -force

    
    }
}
