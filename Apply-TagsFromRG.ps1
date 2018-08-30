<#
    .DESCRIPTION
        This runbooks check resources for mandatory tags. If tags does not exist, it will apply tags from resource groups.

    .NOTES
        AUTHOR: Olikka | Eric Yew
        LASTEDIT: Jul 12, 2018
#>

$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

#List all Resources within the Subscription
$Resources = Get-AzureRmResource

#For each Resource apply the Tag of the Resource Group
Foreach ($resource in $Resources)
{
    $Rgname = $resource.Resourcegroupname

    $resourceid = $resource.resourceId
    $RGTags = (Get-AzureRmResourceGroup -Name $Rgname).Tags

    $resourcetags = $resource.Tags
    
    If($resource.ResourceType -ne "Microsoft.OperationsManagement/solutions" -Or $resource.ResourceType -notcontains "microsoft.insights")
    {
        If ($resourcetags -eq $null)
            {
                write-output "Applying the following Tags1 to $resourceid"
                $Settag = Set-AzureRmResource -ResourceId $resourceid -Tag $RGTags -Force
            
            }
        Else
            {
                $RGTagFinal = @{}
                $RGTagFinal = $RGTags                  
                        Foreach ($resourcetag in $resourcetags.GetEnumerator())
                        {                
                            If ($RGTags.Name -notcontains $resourcetag.Name)
                                {                        
                                        #write-Output "Name doesn't exist in RG Tags adding to Hash Table"
                                        Write-Output $resourcetag.Name
                                        Write-Output $resourcetag.Value
                                        $RGTagFinal.Add($resourcetag.Name,$resourcetag.Value)
                                }    
                        }
                write-Output "Applying the following Tags2 to $resourceid $RGTagFinal"
                $Settag = Set-AzureRmResource -ResourceId $resourceid -Tag $RGTagFinal -Force
            }   
    }
}
