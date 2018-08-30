#Requires -Module AzureRM.Profile
#Requires -Module AzureRM.Compute

<#
.SYNOPSIS
  Connects to Azure and stops all VMs in the specified Azure subscription or resource group. Ignores VM in Exception Lists.

.DESCRIPTION
  This runbook connects to Azure and stops all VMs in an Azure subscription or resource group.  
  You can attach a schedule to this runbook to run it at a specific time.

.PARAMETER SubscriptionName
   Optional with default of "1-Prod".
   The name of an Azure Subscription stored in Automation Variables. To use an subscription with a different name you can pass the subscription name as a runbook input parameter or change
   the default value for this input parameter.
   
   To reduce error, create automation account variables called "Prod Subscription Name" and "DevTest Subscription Name"

.PARAMETER ResourceGroupName
   Optional
   Allows you to specify the resource group containing the VMs to start.  
   If this parameter is included, only VMs in the specified resource group will be stopped, otherwise all VMs in the subscription will be stopped.  

.PARAMETER VMName
    Optional
    Allows you to specify a single VM to start. The resource group name will be required.

.PARAMETER VMsExceptionList
    Optional
    Allows you to specify a list of (comma separated) VMs in the resource group/subscription to be excluded from the runbook. 

.NOTES
	Created By: Eric Yew - OLIKKA
	LAST EDIT: Aug 31, 2018
	By: Eric Yew
	SOURCE: https://github.com/ericyew/AzureAutomation/blob/master/Stop-AzureRmVM.ps1
#>

# Returns strings with status messages
[OutputType([String])]

param (
    [Parameter(Mandatory=$false)] 
    [String] $SubscriptionName = "1-Prod, 2-Dev/Test *Defaults to Prod*",

    [Parameter(Mandatory=$false)] 
    [String] $ResourceGroupName,

    [Parameter(Mandatory=$false)] 
    [String] $VMName,

    [Parameter(Mandatory=$false)] 
    [String] $VMsExceptionList
)

# Error Checking: Trim white space from both ends of string enter.
$VMName = $VMName -replace '\s',''
$SubscriptionName = $SubscriptionName.trim()	
$ResourceGroupName = $ResourceGroupName -replace '\s',''

# Retrieve subscription name from variable asset if not specified
    if($SubscriptionName -eq "1" -Or $SubscriptionName -eq "1-Prod, 2-Dev/Test *Defaults to Prod*")
    {
        $SubscriptionName = Get-AutomationVariable -Name 'Prod Subscription Name'
        $SubscriptionID = Get-AutomationVariable -Name 'Prod Subscription ID'
        if($SubscriptionName.length -gt 0)
        {
            Write-Output "Specified subscription name/ID: [$SubscriptionName]"
        }
        else
        {
            throw "No variable asset with name 'Prod Subscription Name' was found. Either specify an Azure subscription name or define the 'Prod Subscription Name' variable setting"
        }
    }
    elseIf($SubscriptionName -eq "2")
    {
        $SubscriptionName = Get-AutomationVariable -Name 'DevTest Subscription Name'
        $SubscriptionID = Get-AutomationVariable -Name 'DevTest Subscription ID'
        if($SubscriptionName.length -gt 0)
        {
            Write-Output "Specified subscription name/ID: [$SubscriptionName]"
        }
        else
        {
            throw "No variable asset with name 'DevTest Subscription Name' was found. Either specify an Azure subscription name or define the 'DevTest Subscription Name' variable setting"
        }
    }
    else
    {
        if($SubscriptionName.length -gt 0)
        {
            Write-Output "Specified subscription name/ID: [$SubscriptionName]"
        }
    }

#Connect to Azure
    try
    {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection=Get-AutomationConnection -Name AzureRunAsConnection         

        "Logging in to Azure..."
        Connect-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    }
    catch {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection AzureRunAsConnection not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }
    Select-AzureRmSubscription -SubscriptionName $SubscriptionName


# If there is a specific resource group, then get all VMs in the resource group,
# otherwise get all VMs in the subscription.
if ($ResourceGroupName) { 
    if ($VMName) {
        $VMs = @()
        $VMs += Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VMName
    }
    else {
	    [System.Collections.ArrayList]$VMs = Get-AzureRmVM -ResourceGroupName $ResourceGroupName
    }
}
else { 
	[System.Collections.ArrayList]$VMs = Get-AzureRmVM
}

$VMsList = $VMs.clone()
if ($VMsExceptionList) {
    $VMsExceptionList = $VMsExceptionList -replace '\s',''
    $AzureVMsException = $VMsExceptionList.Split(",") 
        [System.Collections.ArrayList]$AzureVMsToNotHandle = $AzureVMsException
    Foreach ($VM in $VMs.GetEnumerator()) {
        Foreach ($VMException in $AzureVMsToNotHandle) {
            If ($VM.name -eq $VMException) {
                $VMsList.Remove($VM)
            }
        }
    }

}

# Start each of the VMs
"Shutting down the virtual machine ..."
foreach ($VM in $VMsList) {
    $RmPState = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VM.Name -Status -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Statuses.Code[1]

    if ($RmPState -eq 'PowerState/deallocated')
    {
        Write-Output ($VM.Name + " is already shut down.")
    }
    else
    {
        $StopSts = $VM | Stop-AzureRmVM -Force -ErrorAction Continue
        Write-Output ($VM.Name + " has been stopped.")
    }
}

