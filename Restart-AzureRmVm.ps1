<#
.SYNOPSIS
  Connects to Azure and restarts a VM

.DESCRIPTION
  This runbook connects to Azure and restarts a VMs.  
  You can attach a schedule to this runbook to run it at a specific time.

.PARAMETER SubscriptionName
   Optional with default of "1-Prod".
   The name of an Azure Subscription stored in Automation Variables. To use an subscription with a different name you can pass the subscription name as a runbook input parameter or change
   the default value for this input parameter.
   
   To reduce error, create automation account variables called "Prod Subscription Name" and "DevTest Subscription Name"

.PARAMETER ResourceGroupName
   Mandatory
   Allows you to specify the resource group containing the VMs to start.  
   If this parameter is included, only VMs in the specified resource group will be stopped, otherwise all VMs in the subscription will be stopped.  

.PARAMETER VMName
    Mandatory
    Allows you to specify a single VM to start. The resource group name will be required.

.NOTES
	Created By: Eric Yew - OLIKKA
	LAST EDIT: Apr 30, 2019
	By: Eric Yew
	SOURCE: https://github.com/ericyew/AzureAutomation/blob/master/ReStart-AzureRmVM.ps1
#>

# Returns strings with status messages
[OutputType([String])]

param (
    [Parameter(Mandatory=$false)] 
    [String] $SubscriptionName = "1-Prod, 2-Dev/Test *Defaults to Prod*",

    [Parameter(Mandatory=$true)] 
    [String] $ResourceGroupName,

    [Parameter(Mandatory=$true)] 
    [String] $VMName
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
            Write-Output "Specified subscription name: [$SubscriptionName]"
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
            Write-Output "Specified subscription name: [$SubscriptionName]"
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

#Use Subscription ID if Prod or DevTest subscription to avoid errors should Subscription be renamed
    if($SubscriptionName -eq "1" -Or $SubscriptionName -eq "1-Prod, 2-Dev/Test *Defaults to Prod*" -Or $SubscriptionName -eq "2")
    {
        Select-AzureRmSubscription -SubscriptionId $SubscriptionID
    }
    else
    {
        Select-AzureRmSubscription -SubscriptionName $SubscriptionName
    }


# Get details of VM
    $VM = Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VMName

# Restart the VM
	$RestartRtn = $VM | Restart-AzureRmVM -ErrorAction Continue

	if ($RestartRtn.Status -ne 'Succeeded')
	{
		# The VM failed to start, so send notice
        Write-Output ($VM.Name + " failed to stop")
        Write-Error ($VM.Name + " failed to stop. Error was:") -ErrorAction Continue
		Write-Error (ConvertTo-Json $RestartRtn.Error) -ErrorAction Continue
	}
	else
	{
		# The VM stopped, so send notice
		Write-Output ($VM.Name + " has been restarted")
	}

