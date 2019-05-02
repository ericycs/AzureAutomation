<#
.SYNOPSIS
  Connects to Azure and rename an existing virtual machine (ARM only) in a resource group.

.DESCRIPTION
  This runbook connects to Azure and performs the following tasks :
  	- Stops the specified virtual machine
	- Store the virtual machine configuration
	- Remove the virtual machine from Azure
	- Recreate the virtual machine with the new name, existing vhd and nic
	- Starts the specified virtual machine
  
.PARAMETER AzureSubscriptionName
   Optional with default of "1-Prod".
   The name of an Azure Subscription stored in Automation Variables. To use an subscription with a different name you can pass the subscription name as a runbook input parameter or change
   the default value for this input parameter.
   
   To reduce error, create automation account variables called "Prod Subscription Name" and "DevTest Subscription Name"

.PARAMETER VMName
   Mandatory with no default.
   The name of the virtual machine which you want to add a new data disk.
   It must be the name of an ARM virtual machine.

.PARAMETER ResourceGroupName
   Mandatory with no default.
   The name of the resource group which contains the targeted virtual machine. 
    
.PARAMETER NewVMName
   Mandatory with no default.
   The new name for the virtual machine which you want to rename.
   It must be a unique name for an ARM virtual machine.
   
.NOTES
 	Created By: Eric Yew
	LAST EDIT: May 2, 2019
	By: Eric Yew
    SOURCE: https://github.com/ericyew/AzureAutomation/blob/master/Rename-AzureRmVm.ps1
#>


param (
    [Parameter(Mandatory=$false)] 
    [String] $AzureSubscriptionName = "1-Prod, 2-Dev/Test *Defaults to Prod*",

    [parameter(Mandatory=$true)] 
    [String] $VMName,
	
	[parameter(Mandatory=$true)] 
    [String] $NewVMName,
	
    [parameter(Mandatory=$true)] 
    [String] $ResourceGroupName	
) 

# Enable Verbose logging for testing
#    $VerbosePreference = "Continue"

# Error Checking: Trim white space from both ends of string enter.
$VMName = $VMName -replace '\s',''
$AzureSubscriptionName = $AzureSubscriptionName.trim()	
$NewVMName = $NewVMName -replace '\s',''
$ResourceGroupName = $ResourceGroupName -replace '\s',''

# Retrieve subscription name from variable asset if not specified
    if($AzureSubscriptionName -eq "1" -Or $AzureSubscriptionName -eq "1-Prod, 2-Dev/Test *Defaults to Prod*")
    {
        $AzureSubscriptionName = Get-AutomationVariable -Name 'Prod Subscription Name'
        if($AzureSubscriptionName.length -gt 0)
        {
            Write-Output "Specified subscription name/ID: [$AzureSubscriptionName]"
        }
        else
        {
            throw "No variable asset with name 'Prod Subscription Name' was found. Either specify an Azure subscription name or define the 'Prod Subscription Name' variable setting"
        }
    }
    elseIf($AzureSubscriptionName -eq "2")
    {
        $AzureSubscriptionName = Get-AutomationVariable -Name 'DevTest Subscription Name'
        if($AzureSubscriptionName.length -gt 0)
        {
            Write-Output "Specified subscription name/ID: [$AzureSubscriptionName]"
        }
        else
        {
            throw "No variable asset with name 'DevTest Subscription Name' was found. Either specify an Azure subscription name or define the 'DevTest Subscription Name' variable setting"
        }
    }
    else
    {
        if($AzureSubscriptionName.length -gt 0)
        {
            Write-Output "Specified subscription name/ID: [$AzureSubscriptionName]"
        }
        else
        {
            throw "No variable asset or subscription with name $AzureSubscriptionName was found. Either specify an Azure subscription name or specify 1,2 or 3 options"
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
    Select-AzureRmSubscription -SubscriptionName $AzureSubscriptionName


# Getting the virtual machine config
    $VM = Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
    $VMConfig = $VM

#Runbook will not run on SQL Server IaaS VM deployed from marketplace
    If (Get-AzureRmVMSqlServerExtension -ResourceGroupName $ResourceGroupName -VMName $VMName){
        Write-Output "VM is a SQL VM. It is not recommended to perform this action on a SQL VM"
        Write-Output "Exiting runbook"
        Exit
    }

#Shutdown the VM
    "Shutting down the virtual machine ..."
    $RmPState = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status -ErrorAction SilentlyContinue -WarningAction SilentlyContinue).Statuses.Code[1]

    if ($RmPState -eq 'PowerState/deallocated')
    {
        "$VMName is already shut down."
    }
    else
    {
        $StopSts = $VM | Stop-AzureRmVM -Force -ErrorAction Stop
        "The virtual machine has been stopped."
    }

#Reconfigure and Clean-up VM config to reflect deployment from attached disks
	$VM.Name = $NewVMName
    $vm.StorageProfile.OSDisk.Name = $vmName
    $vm.StorageProfile.OSDisk.CreateOption = "Attach"
    $vm.StorageProfile.DataDisks | 
        ForEach-Object { $_.CreateOption = "Attach" }
    $vm.StorageProfile.ImageReference = $null
    $vm.OSProfile = $null

#Remove the virtual machine from Azure
    Remove-AzureRmVM -VMName $VMName -ResourceGroupName $ResourceGroupName -Force -ErrorAction Stop

#Recreate the virtual machine with the new name
    New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $VM.Location -VM $VM -Verbose

"The virtual machine has been renamed and started."
