## Introduction
Terraform scripts for an end-to-end demonstration of Egress Access Points

## Resources Created
The scripts will create 
* Azure:
    * Azure private networking
    * Azure blob storage (private access with IP filtering for local IP to allow Terraform to create container)
* Confluent:
    * dedicated Confluent cluster with privatelink access to a private Azure network
    * egress access point to Azure blob storage
    * DNS entry for Azure blob storage
    * source connector (Datagen) generating dummy data into an orders topic
    * sink connector to Azure blob storage

## How to Use
1. Authenticate to Azure using Azure CLI following [these instructions](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli)
2. Fill variables in terraform.tfvars and secret.tfvars
3. Run `terraform apply -var-file=secret.tfvars`

## Clean Up
1. Run `terraform destroy -var-file=secret.tfvars`

## Notes
The script includes a command to auto-approve the private endpoint created by the egress access point. The DNS record can only be created after the egress access point is in a ready state following approval. However, the state can take a few minutes to change from pending to ready after approval which can cause the creation of the DNS entry to fail. Re-running the Terraform scripts after the egress access point is ready will result in successful creation of the DNS entry.
