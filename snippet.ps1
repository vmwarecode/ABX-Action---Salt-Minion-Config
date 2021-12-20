# ABX Action to configure the Salt Minion and tun a highstate as part of a vRA deployment
# Created by Dennis Gerolymatos and Guillermo Martinez
# Version 1.3.3 - 20.12.2021

function handler($context, $inputs) {

#global Variables definition
$vcuser = $context.getSecret($inputs.vcUsername)        # get user for vCenter connection
$vcpassword = $context.getSecret($inputs.vcPassword)    # get password for vCenter connection
$vcfqdn = $context.getSecret($inputs.vcfqdn)            # get FQDN of vCenter
$name = $inputs.resourceNames[0]                        # get name of the VM from the resourcenames array
$ip = $inputs.addresses[0]                              # get first IP address of the VM from the addresses array
$tempfilegrains = New-TemporaryFile                     # initialize tempfile for grains
$tempfileminion = New-TemporaryFile                     # initialize tempfile for minion config

#vCenter connection
write-host "Connecting to vCenter..."
Connect-VIServer $vcfqdn -User $vcuser -Password $vcpassword -Force
write-host “Waiting for VM Tools to Start”
do {
    $toolsStatus = (Get-vm -name $name | Get-View).Guest.ToolsStatus
    write-host $toolsStatus
    sleep 3
    } until ( $toolsStatus -eq ‘toolsOk’ )
$vm = Get-vm -name $name
write-host "Running script on server "$name" with IP address "$ip


#Variables definition per operatinge system
if ($inputs.customProperties.osType -eq "WINDOWS")
{
    $tmpl_pass = $context.getSecret($inputs.tmpl_user_windows_password)     # get password for OS image
    $vmusername=$context.getSecret($inputs.tmpl_user_windows)               # get username for Windows image
    # Evaluates the correct path for minion installation
    if ((Invoke-VMScript -VM $vm -ScriptText "test-path c:\salt" -GuestUser $vmusername -GuestPassword $tmpl_pass).ScriptOutput.trim() -eq "True")
        {$saltpath = 'c:\salt'}
    elseif ((Invoke-VMScript -VM $vm -ScriptText "test-path 'c:\ProgramData\Salt Project\salt'" -GuestUser $vmusername -GuestPassword $tmpl_pass).ScriptOutput.trim() -eq "True")
        {$saltpath = 'c:\ProgramData\Salt Project\salt'}
    else
        {write-host "no minion detected in this image"}
    $restartservicescript = "restart-service salt-minion -force"         # get command for restarting minion on Windows
    $highstatescript = "$($saltpath)\salt-call state.highstate"          # get command for executing a highstate on windows
    $filepathgrains = "$($saltpath)\conf\grains"                         # path to grains file on Windows
    $filepathminion = "$($saltpath)\conf\minion.d\minion.conf"           # path to minion.conf file on Windows
    $scriptrevoke = "$($saltpath)\salt-call saltutil.revoke_auth"        # get command for revoking minion key on Windows

}
else 
{
    $tmpl_pass = $context.getSecret($inputs.tmpl_user_linux_password)      # get password for OS image
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
    write-host "Executing salt-call saltutil.revoke_auth..."
    $runscript = Invoke-VMScript -VM $vm -ScriptText $scriptrevoke -GuestUser $vmusername -GuestPassword $tmpl_pass
    Write-Host $runscript.ScriptOutput
    }
else
    {
    
    # Reads Values in "grains:" and "minionconfig" literal blocks and write them to the temp files
    write-host "Collecting key:value pairs..."
     
    $inputs.customProperties.minionconfig | add-content $tempfileminion
    $inputs.customProperties.grains | add-content $tempfilegrains
    
    # copy temp files to target OS
    write-host "Copy minion.conf file to target OS..."
    $runscript = copy-vmguestfile -source $tempfileminion -destination $filepathminion -localtoguest -VM $vm -GuestUser $vmusername -GuestPassword $tmpl_pass -Force
    Write-Host $runscript.ScriptOutput
    write-host "Copy grains file to target OS..."
    $runscript = copy-vmguestfile -source $tempfilegrains -destination $filepathgrains -localtoguest -VM $vm -GuestUser $vmusername -GuestPassword $tmpl_pass -Force
    Write-Host $runscript.ScriptOutput
    
    
    
    # Restart minion
    Write-Host "Restarting minion..."
    $runscript = Invoke-VMScript -VM $vm -ScriptText $restartservicescript -GuestUser $vmusername -GuestPassword $tmpl_pass
    Write-Host $runscript.ScriptOutput
    
    
    
    # Run highstate
    if($inputs.customProperties.highstate -eq "true")
        {
        Write-Host "Running salt highstate..."
        $runscript = Invoke-VMScript -VM $vm -ScriptText $highstatescript -GuestUser $vmusername -GuestPassword $tmpl_pass
        Write-Host $runscript.ScriptOutput
        }
    
    
    # Remove temp files
    remove-item $tempfilegrains -force
    remove-item $tempfileminion -force

    
    }

}
