variable "resource_group" {
  description = "The name of the Azure Resource Group that the virtual network belongs to"
  type        = string
}

variable "region" {
  description = "The region of your VNet"
  type        = string
}

variable "vnet_name" {
  description = "The name of your VNet that you want to connect to Confluent Cloud Cluster"
  type        = string
}

variable "storage_account" {
  description = "The name of your Azure Storage Account"
  type        = string
}

variable "subscription_id" {
  description = "The Azure subscription ID to enable for the Private Link Access where your VNet exists"
  type        = string
}

variable "client_id" {
  description = "The ID of the Client on Azure"
  type        = string
  sensitive   = true
}

variable "client_secret" {
  description = "The Secret of the Client on Azure"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "The Azure tenant ID in which Subscription exists"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "confluent_env_name" {
    description = "The name of the Confluent environment"
    type        = string
}

variable "private_link_name" {
    description = "The name of the private link network"
    type        = string
}

variable "cluster_name" {
    description = "The name of the cluster"
    type        = string
}

variable "subnet_name_by_zone" {
  description = "A map of Zone to Subnet Name"
  type        = map(string)
}

variable "local_ip" {
  description = "IP of local machine"
  type        = string
}
