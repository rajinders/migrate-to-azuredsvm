# migrate-to-azuredsvm
PowerShell script that can be used to migrate standard Azure VM to DS Series VM with SSD Premium storage.
You can read my accompaning blog [post](http://www.rajinders.com/2015/06/14/how-to-migrate-from-standard-azure-virtual-machines-to-ds-series-storage-optimized-vms/) to learn more.

## Examples
The following example shows how to take a standalone standard VM and migrate it to DS Series standalone VM with durable SSD drives.

    .\MigrateVMToPremiumStorage.ps1 -SourceVMName "rajsourcevm2" -SourceServiceName `
    "rajsourcevm2" -DestVMName "rajdsvm12" -DestServiceName "rajdsvm12svc" `
    -Location "West US" -VMSize Standard_DS2 `
    -DestStorageAccountName 'rajwestpremstg18' -DestStorageAccountContainer 'vhds'
    
The following example shows how to take a standard VM and migrate it to a DS Series VM with durable SSD drives in a virtual network

    .\MigrateVMToPremiumStorage.ps1 -SourceVMName "rajsourcevm2" -SourceServiceName "rajsourcevm2" `
    -DestVMName "rajdsvm16" -DestServiceName "rajdsvm16svc" `
    -Location "West US" -VMSize Standard_DS2 `
    -DestStorageAccountName 'rajwestpremstg19' -DestStorageAccountContainer 'vhds' `
    -VNetName rajvnettest3 -SubnetName FrontEndSubnet
    
**Notes**
* Currently this script only migrates virtual machines to the same subscription.
* It can migrate VM's to a different region as long as premium storage is available in that region
* It shuts down the existing source VM before making of copy of the VHD's for the virtual machine.
* It validates that virtual network for the destination VM exists but does not validate if subnet also exists
* It gives new names to the disks in the destination virtual machine
* If your VM has a disk smaller than 10 GB the script will fail because we are not allowed to add disks smaller than 10 GB
* Currently I am only copying disks, end points, VM extensions. I am not copying ACL's and other type of extensions like malware extension
* I only tested the script with PowerShell SDK Version 0.9.2
* I tested migrating standard VM in West US to DS Series VM in West US only. I logged into the newly created VM and verified that all disks were present. This is the extent of my testing. My VM with 3 Disk's copied in 10 minutes. 
* If your destination storage account already exists it has to be of type “Premium_LRS”. If you have an existing account of different type the script will fail. If the storage account does not exist it will be created.
