<#
Copyright 2015 Rajinder Singh

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
#>


<#
.SYNOPSIS
Migrates an existing VM into a DS Series VM which uses Premium storage. 

.DESCRIPTION
This script migrates an exitsing VM into a DS Series VM which uses Premium Storage. At this time DS Series VM's are not available in all regions.
It currently expects the VM to be migrated in the same subscription. It supports migrating VM to the same region or a different region.
It can be easily extended to support migrating to a different subscription as well

.PARAMETER SourceVMName
The name of the VM that needs to be migrated

.PARAMTER SourceServiceName
The name of service for the old VM

.PARAMETER DestVMName
The name of New DS Series VM that will be created.

.PARAMTER DestServiceName
The name of the Service for the new VM

.PARAMTER Location
Region where new VM will be created

.PARAMTER Size
Size of the new VM

.PARAMTER DestStorageAccountName
Name of the storage account where the VM will be created. It has to be premium storage account

.PARAMETER ResourceGroupName
Resource group where the cache will be create

.EXAMPLE

# Migrate a standalone virtual machine to a DS Series virtual machine with Premium storage. Both the VM's are in the same subscription
.\MigrateVMToPremiumStorage.ps1 -SourceVMName "rajsourcevm2" -SourceServiceName "rajsourcevm2" -DestVMName "rajdsvm12" -DestServiceName "rajdsvm12svc" -Location "West US" -VMSize Standard_DS2 -DestStorageAccountName 'rajwestpremstg18' -DestStorageAccountContainer 'vhds'


# Migrate a standalone virtual machine to a DS Series virtual machine with Premium storage. Both the VM's are in the same subscription
.\MigrateVMToPremiumStorage.ps1 -SourceVMName "rajsourcevm2" -SourceServiceName "rajsourcevm2" -DestVMName "rajdsvm16" -DestServiceName "rajdsvm16svc" -Location "West US" -VMSize Standard_DS2 -DestStorageAccountName 'rajwestpremstg19' -DestStorageAccountContainer 'vhds' -VNetName rajvnettest3 -SubnetName FrontEndSubnet

#>

[CmdletBinding(DefaultParameterSetName="Default")]
Param
(
    [Parameter (Mandatory = $true)]
    [string] $SourceVMName,

    [Parameter (Mandatory = $true)]
    [string] $SourceServiceName,

    [Parameter (Mandatory = $true)]
    [string] $DestVMName,

    [Parameter (Mandatory = $true)]
    [string] $DestServiceName,

    [Parameter (Mandatory = $true)]
    [ValidateSet('West US','East US 2','West Europe','East China','Southeast Asia','West Japan', ignorecase=$true)]
    [string] $Location,

    [Parameter (Mandatory = $true)]
    [ValidateSet('Standard_DS1','Standard_DS2','Standard_DS3','Standard_DS4','Standard_DS11','Standard_DS12','Standard_DS13','Standard_DS14', ignorecase=$true)]
    [string] $VMSize,

    [Parameter (Mandatory = $true)]
    [string] $DestStorageAccountName,

    [Parameter (Mandatory = $true)]
    [string] $DestStorageAccountContainer,

    [Parameter (Mandatory = $false)]
    [string] $VNetName,

    [Parameter (Mandatory = $false)]
    [string] $SubnetName
)


#publish version of the the powershell cmdlets we are using
(Get-Module Azure).Version

#$VerbosePreference = "Continue" 
$StorageAccountTypePremium = 'Premium_LRS'

#############################################################################################################
#validation section
#Perform as much upfront validation as possible
#############################################################################################################

#validate that current subscription is set
$CurrentSubscription = Get-AzureSubscription -ErrorAction SilentlyContinue

if (!$CurrentSubscription) 
{
	Write-Error "Cannot find current subscription"
	return
}

#validate upfront that this service we are trying to create already exists
if((Get-AzureService -ServiceName $DestServiceName -ErrorAction SilentlyContinue) -ne $null)
{
    Write-Error "Service [$DestServiceName] already exists"
    return
}

#Determine we are migrating the VM to a Virtual network. If it is then verify that VNET exists
if( !$VNetName -and !$SubnetName )
{
    $DeployToVNet = $false
}
else
{
    $DeployToVNet = $true
    $vnetSite = Get-AzureVNetSite -VNetName $VNetName -ErrorAction SilentlyContinue

    if (!$vnetSite)
    {
        Write-Error "Virtual Network [$VNetName] does not exist"
        return
    }
}

Write-Host "DepoyToVNet is set to [$DeployToVnet]"

#TODO: add validation to make sure the destination VM size can accomodate the number of disk in the source VM

$DestStorageAccount = Get-AzureStorageAccount -StorageAccountName $DestStorageAccountName -ErrorAction SilentlyContinue

#check to see if the storage account exists and create a premium storage account if it does not exist
if(!$DestStorageAccount)
{
    # Create a new storage account
    Write-Output "";
    Write-Output ("Configuring Destination Storage Account {0} in location {1}" -f $DestStorageAccountName, $Location);

    $DestStorageAccount = New-AzureStorageAccount -StorageAccountName $DestStorageAccountName -Location $Location -Type $StorageAccountTypePremium -ErrorVariable errorVariable -ErrorAction SilentlyContinue | Out-Null

    if (!($?)) 
    { 
        throw "Cannot create the Storage Account [$DestStorageAccountName] on $Location. Error Detail: $errorVariable" 
    } 
    
    Write-Verbose "Created Destination Storage Account [$DestStorageAccountName] with AccountType of [$($DestStorageAccount.AccountType)]"     
}
else
{
    Write-Host "Destination Storage account [$DestStorageAccountName] already exists. Storage account type is [$($DestStorageAccount.AccountType)]"

    #make sure if the account already exists it is of type premium storage
    if( $DestStorageAccount.AccountType -ne $StorageAccountTypePremium )
    {
        Write-Error "Storage account [$DestStorageAccountName] account type of [$($DestStorageAccount.AccountType)] is invalid"
        return
    }
}

Write-Host "Setting current Azure Subscription to [$($CurrentSubscription.SubscriptionId)] with Storage Account [$($DestStorageAccountName)]"
Set-AzureSubscription -SubscriptionId $CurrentSubscription.SubscriptionId -CurrentStorageAccountName $DestStorageAccountName

Write-Host "Source VM Name is [$SourceVMName] and Service Name is [$SourceServiceName]"

#Get VM Details
$SourceVM = Get-AzureVM -Name $SourceVMName -ServiceName $SourceServiceName -ErrorAction SilentlyContinue

if($SourceVM -eq $null)
{
    Write-Error "Unable to find Virtual Machine [$SourceServiceName] in Service Name [$SourceServiceName]"
    return
}


Write-Host "vm name is [$($SourceVM.Name)] and vm status is [$($SourceVM.Status)]"


#need to shutdown the existing VM before copying its disks.
if($SourceVM.Status -eq "ReadyRole")
{
    Write-Host "Shutting down virtual machine [$SourceVMName]"
    #Shutdown the VM
    Stop-AzureVM -ServiceName $SourceServiceName -Name $SourceVMName -Force
}


$osdisk = $SourceVM | Get-AzureOSDisk

Write-Host "OS Disk name is $($osdisk.DiskName) and disk location is $($osdisk.MediaLink)"

$disk_configs = @{}

# Used to track disk copy status
$diskCopyStates = @()

##################################################################################################################
# Kicks off the async copy of VHDs
##################################################################################################################

# Copies to remote storage account
# Returns blob copy state to poll against
function StartCopyVHD($sourceDiskUri, $diskName, $OS, $destStorageAccountName, $destContainer)
{
    Write-Host "Destination Storage Account is [$destStorageAccountName], Destination Container is [$destContainer]"

    #extract the name of the source storage account from the URI of the VHD
    $sourceStorageAccountName = $sourceDiskUri.Host.Replace(".blob.core.windows.net", "")
    

    $vhdName = $sourceDiskUri.Segments[$sourceDiskUri.Segments.Length - 1].Replace("%20"," ") 
    $sourceContainer = $sourceDiskUri.Segments[$sourceDiskUri.Segments.Length - 2].Replace("/", "")

    $sourceStorageAccountKey = (Get-AzureStorageKey -StorageAccountName $sourceStorageAccountName).Primary
    $sourceContext = New-AzureStorageContext -StorageAccountName $sourceStorageAccountName -StorageAccountKey $sourceStorageAccountKey

    $destStorageAccountKey = (Get-AzureStorageKey -StorageAccountName $destStorageAccountName).Primary
    $destContext = New-AzureStorageContext -StorageAccountName $destStorageAccountName -StorageAccountKey $destStorageAccountKey
    if((Get-AzureStorageContainer -Name $destContainer -Context $destContext -ErrorAction SilentlyContinue) -eq $null)
    {
        New-AzureStorageContainer -Name $destContainer -Context $destContext | Out-Null

        while((Get-AzureStorageContainer -Name $destContainer -Context $destContext -ErrorAction SilentlyContinue) -eq $null)
        {
            Write-Host "Pausing to ensure container $destContainer is created.." -ForegroundColor Green
            Start-Sleep 15
        }
    }

    # Save for later disk registration 
    $destinationUri = "https://$destStorageAccountName.blob.core.windows.net/$destContainer/$vhdName"
    
    if($OS -eq $null)
    {
        $disk_configs.Add($diskName, "$destinationUri")
    }
    else
    {
       $disk_configs.Add($diskName, "$destinationUri;$OS")
    }

    #start async copy of the VHD. It will overwrite any existing VHD
    $copyState = Start-AzureStorageBlobCopy -SrcBlob $vhdName -SrcContainer $sourceContainer -SrcContext $sourceContext -DestContainer $destContainer -DestBlob $vhdName -DestContext $destContext -Force

    return $copyState
}


##################################################################################################################
# Tracks status of each blob copy and waits until all the blobs have been copied
##################################################################################################################

function TrackBlobCopyStatus()
{
    param($diskCopyStates)
    do
    {
        $copyComplete = $true
        Write-Host "Checking Disk Copy Status for VM Copy" -ForegroundColor Green
        foreach($diskCopy in $diskCopyStates)
        {
            $state = $diskCopy | Get-AzureStorageBlobCopyState | Format-Table -AutoSize -Property Status,BytesCopied,TotalBytes,Source
            if($state -ne "Success")
            {
                $copyComplete = $true
                Write-Host "Current Status" -ForegroundColor Green
                $hideHeader = $false
                $inprogress = 0
                $complete = 0
                foreach($diskCopyTmp in $diskCopyStates)
                { 
                    $stateTmp = $diskCopyTmp | Get-AzureStorageBlobCopyState
                    $source = $stateTmp.Source
                    if($stateTmp.Status -eq "Success")
                    {
                        Write-Host (($stateTmp | Format-Table -HideTableHeaders:$hideHeader -AutoSize -Property Status,BytesCopied,TotalBytes,Source | Out-String)) -ForegroundColor Green
                        $complete++
                    }
                    elseif(($stateTmp.Status -like "*failed*") -or ($stateTmp.Status -like "*aborted*"))
                    {
                        Write-Error ($stateTmp | Format-Table -HideTableHeaders:$hideHeader -AutoSize -Property Status,BytesCopied,TotalBytes,Source | Out-String)
                        return $false
                    }
                    else
                    {
                        Write-Host (($stateTmp | Format-Table -HideTableHeaders:$hideHeader -AutoSize -Property Status,BytesCopied,TotalBytes,Source | Out-String)) -ForegroundColor DarkYellow
                        $copyComplete = $false
                        $inprogress++
                    }
                    $hideHeader = $true
                }
                if($copyComplete -eq $false)
                {
                    Write-Host "$complete Blob Copies are completed with $inprogress that are still in progress." -ForegroundColor Magenta
                    Write-Host "Pausing 60 seconds before next status check." -ForegroundColor Green 
                    Start-Sleep 60
                }
                else
                {
                    Write-Host "Disk Copy Complete" -ForegroundColor Green
                    break 
                }
            }
        }
    } while($copyComplete -ne $true) 
    Write-Host "Successfully Copied up all Disks" -ForegroundColor Green
}


# Mark the start time of the script execution 
$startTime = Get-Date 

Write-Host "Destination storage account name is [$DestStorageAccountName]"

# Copy disks using the async API from the source URL to the destination storage account
$diskCopyStates += StartCopyVHD -sourceDiskUri $osdisk.MediaLink -destStorageAccount $DestStorageAccountName -destContainer $DestStorageAccountContainer -diskName $osdisk.DiskName -OS $osdisk.OS


# copy all the data disks
$SourceVM | Get-AzureDataDisk | foreach {

    Write-Host "Disk Name [$($_.DiskName)], Size is [$($_.LogicalDiskSizeInGB)]"

    #Premium storage does not allow disks smaller than 10 GB
    if( $_.LogicalDiskSizeInGB -lt 10 )
    {
        Write-Warning "Data Disk [$($_.DiskName)] with size [$($_.LogicalDiskSizeInGB) is less than 10GB so it cannnot be added" 
    }
    else
    {
        Write-Host "Destination storage account name is [$DestStorageAccountName]"
        $diskCopyStates += StartCopyVHD -sourceDiskUri $_.MediaLink -destStorageAccount $DestStorageAccountName -destContainer $DestStorageAccountContainer -diskName $_.DiskName
    }
}

#check that status of blob copy. This may take a while if you are doing cross region copies.
#even in the same region a 127 GB takes nearly 10 minutes
TrackBlobCopyStatus -diskCopyStates $diskCopyStates

# Mark the finish time of the script execution 
$finishTime = Get-Date 
 
# Output the time consumed in seconds 
$TotalTime = ($finishTime - $startTime).TotalSeconds 
Write-Host "The disk copies completed in $TotalTime seconds." -ForegroundColor Green


Write-Host "Registering Copied Disk" -ForegroundColor Green

$luncount = 0   # used to generate unique lun value for data disks
$index = 0  # used to generate unique disk names
$OSDisk = $null

$datadisk_details = @{}

foreach($diskName in $disk_configs.Keys)
{
    $index = $index + 1

    $diskConfig = $disk_configs[$diskName].Split(";")

    #since we are using the same subscription we need to update the diskName for it to be unique
    $newDiskName = "$DestVMName" + "-disk-" + $index

    Write-Host "Adding disk [$newDiskName]"

    #check to see if this disk already exists
    $azureDisk = Get-AzureDisk -DiskName $newDiskName -ErrorAction SilentlyContinue

    if(!$azureDisk)
    {

        if($diskConfig.Length -gt 1)
        {
           Write-Host "Adding OS disk [$newDiskName] -OS [$diskConfig[1]] -MediaLocation [$diskConfig[0]]"

           #Expect OS Disk to be the first disk in the array
           $OSDisk = Add-AzureDisk -DiskName $newDiskName -OS $diskConfig[1] -MediaLocation $diskConfig[0]

           $vmconfig = New-AzureVMConfig -Name $DestVMName -InstanceSize $VMSize -DiskName $OSDisk.DiskName  

        }
        else
        {
            Write-Host "Adding Data disk [$newDiskName] -MediaLocation [$diskConfig[0]]"

            Add-AzureDisk -DiskName $newDiskName -MediaLocation $diskConfig[0]

            $datadisk_details[$luncount] = $newDiskName

            $luncount = $luncount + 1   
        }
    }
    else
    {
        Write-Error "Unable to add Azure Disk [$newDiskName] as it already exists"
        Write-Error "You can use Remove-AzureDisk -DiskName $newDiskName to remove the old disk"
        return
    }
}


#add all the data disks to the VM configuration
foreach($lun in $datadisk_details.Keys)
{
    $datadisk_name = $datadisk_details[$lun]

    Write-Host "Adding data disk [$datadisk_name] to the VM configuration"

    $vmconfig | Add-AzureDataDisk -Import -DiskName $datadisk_name  -LUN $lun
}


#read all the end points in the source VM and create them in the destination VM
#NOTE: I don't copy ACL's yet. I need to add this.
$SourceVM | get-azureendpoint | foreach {

    if($_.LBSetName -eq $null)
    {
        write-Host "Name is [$($_.Name)], Port is [$($_.Port)], LocalPort is [$($_.LocalPort)], Protocol is [$($_.Protocol)], EnableDirectServerReturn is [$($_.EnableDirectServerReturn)]]"
        $vmconfig | Add-AzureEndpoint -Name $_.Name -LocalPort $_.LocalPort -PublicPort $_.Port -Protocol $_.Protocol -DirectServerReturn $_.EnableDirectServerReturn
    }
    else
    {
        write-Host "Name is [$($_.Name)], Port is [$($_.Port)], LocalPort is [$($_.LocalPort)], Protocol is [$($_.Protocol)], EnableDirectServerReturn is [$($_.EnableDirectServerReturn)], LBSetName is [$($_.LBSetName)]"        
        $vmconfig | Add-AzureEndpoint -Name $_.Name -LocalPort $_.LocalPort -PublicPort $_.Port -Protocol $_.Protocol -DirectServerReturn $_.EnableDirectServerReturn -LBSetName $_.LBSetName -DefaultProbe
    }
}


# 
if( $DeployToVnet )
{
    Write-Host "Virtual Network Name is [$VNetName] and Subnet Name is [$SubnetName]" 

    $vmconfig | Set-AzureSubnet -SubnetNames $SubnetName
    $vmconfig | New-AzureVM -ServiceName $DestServiceName -VNetName $VNetName -Location $Location
}
else
{
    #Creating the virtual machine
    $vmconfig | New-AzureVM -ServiceName $DestServiceName -Location $Location
}

#get any vm extensions
#there may be other types of extensions that be in the source vm. I don't copy them yet 
$SourceVM | get-azurevmextension | foreach {
    Write-Host "ExtensionName [$($_.ExtensionName)] Publisher [$($_.Publisher)] Version [$($_.Version)] ReferenceName [$($_.ReferenceName)] State [$($_.State)] RoleName [$($_.RoleName)]"
    get-azurevm -ServiceName $DestServiceName -Name $DestVMName -Verbose | set-azurevmextension -ExtensionName $_.ExtensionName -Publisher $_.Publisher -Version $_.Version -ReferenceName $_.ReferenceName -Verbose | Update-azurevm -Verbose
}

#change storage account back to original value
if ($CurrentSubscription.CurrentStorageAccountName -and ($CurrentSubscription.CurrentStorageAccountName -ne $DestStorageAccountName)) 
{
	Write-Host "Setting current Azure Subscription to [$($CurrentSubscription.SubscriptionId)] with Storage Account [$($CurrentSubscription.CurrentStorageAccountName)]"
	Set-AzureSubscription -SubscriptionId $CurrentSubscription.SubscriptionId -CurrentStorageAccountName $CurrentSubscription.CurrentStorageAccountName
}