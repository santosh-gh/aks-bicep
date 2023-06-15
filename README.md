# blog
    https://blog.johnalfaro.com/ code samples

# The Bicep modules will provision the following Azure Resources under subscription scope:

    A Resource Group with Baseline variables

    Hub VNet with required subnets

    Azure Firewall Subnet

    Azure Bastion Subnet
    
    A jumpbox subnet
    
    Spoke VNET with AKS cluster subnet and additional subnet for other services like Azure Container Registry etc.

    Azure Firewall and required routes

    Azure Bastion resource and a jumpbox VM without public IP for securing traffic

    Azure Container Registry for storing images.

    A Private Endpoint for ACR

    Private DNS Zone

    AAD Enabled, Managed Private AKS Cluster with monitoring Addon and Azure Policy enabled

    Private AK Cluster need the UDR routes enabled via Firewall.
