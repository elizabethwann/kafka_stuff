provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

resource "confluent_environment" "staging" {
  display_name = var.confluent_env_name
}

resource "confluent_network" "private-link" {
  display_name     = var.private_link_name
  cloud            = "AZURE"
  region           = var.region
  connection_types = ["PRIVATELINK"]
  environment {
    id = confluent_environment.staging.id
  }
  dns_config {
    resolution = "PRIVATE"
  }
}

resource "confluent_private_link_access" "azure" {
  display_name = "Azure Private Link Access"
  azure {
    subscription = var.subscription_id
  }
  environment {
    id = confluent_environment.staging.id
  }
  network {
    id = confluent_network.private-link.id
  }
}

resource "confluent_kafka_cluster" "dedicated" {
  display_name = var.cluster_name
  availability = "MULTI_ZONE"
  cloud        = confluent_network.private-link.cloud
  region       = confluent_network.private-link.region
  dedicated {
    cku = 2
  }
  environment {
    id = confluent_environment.staging.id
  }
  network {
    id = confluent_network.private-link.id
  }
}

# Set up Private Endpoints for Azure Private Link in your Azure subscription
# Set up DNS records to use Azure Private Endpoints
locals {
  hosted_zone = length(regexall(".glb", confluent_kafka_cluster.dedicated.bootstrap_endpoint)) > 0 ? replace(regex("^[^.]+-([0-9a-zA-Z]+[.].*):[0-9]+$", confluent_kafka_cluster.dedicated.rest_endpoint)[0], "glb.", "") : regex("[.]([0-9a-zA-Z]+[.].*):[0-9]+$", confluent_kafka_cluster.dedicated.bootstrap_endpoint)[0]
  network_id  = regex("^([^.]+)[.].*", local.hosted_zone)[0]
}

resource "azurerm_private_dns_zone" "hz" {
  resource_group_name = azurerm_resource_group.this.name
  name = local.hosted_zone
}

resource "azurerm_private_endpoint" "endpoint" {
  for_each = var.subnet_name_by_zone

  name                = "confluent-${local.network_id}-${each.key}"
  location            = var.region
  resource_group_name = azurerm_resource_group.this.name

  subnet_id = azurerm_subnet.this.id

  private_service_connection {
    name                              = "confluent-${local.network_id}-${each.key}"
    is_manual_connection              = true
    private_connection_resource_alias = lookup(confluent_network.private-link.azure[0].private_link_service_aliases, each.key, "\n\nerror: ${each.key} subnet is missing from CCN's Private Link service aliases")
    request_message                   = "PL"
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "hz" {
  name                  = azurerm_virtual_network.vnet.name
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.hz.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_a_record" "rr" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.hz.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 60
  records = [
    for _, ep in azurerm_private_endpoint.endpoint : ep.private_service_connection[0].private_ip_address
  ]
}

resource "azurerm_private_dns_a_record" "zonal" {
  for_each = var.subnet_name_by_zone

  name                = "*.az${each.key}"
  zone_name           = azurerm_private_dns_zone.hz.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 60
  records = [
    azurerm_private_endpoint.endpoint[each.key].private_service_connection[0].private_ip_address,
  ]
}

# Set up Egress Access Point for Blob Storage
resource "confluent_access_point" "main" {
  display_name = "blob_access"
  environment {
    id = confluent_environment.staging.id
  }
  gateway {
    id = confluent_network.private-link.gateway[0].id
  }
  azure_egress_private_link_endpoint {
    private_link_service_resource_id = azurerm_storage_account.this.id
    private_link_subresource_name = "blob"
  }
}

# Auto approve private endpoint
resource "null_resource" "endpoint_approval" {
  provisioner "local-exec" {
    command     = <<-EOT
          $storage_id = $(az network private-endpoint-connection list --id ${azurerm_storage_account.this.id} --query "[?contains(properties.privateLinkServiceConnectionState.status, 'Pending')].id" -o json) | ConvertFrom-Json
          az network private-endpoint-connection approve --id $storage_id --description "Approved in Terraform"
        EOT
    interpreter = ["pwsh", "-Command"]
  }
  depends_on = [confluent_access_point.main]
}

# Set up DNS Record
resource "confluent_dns_record" "main" {
  display_name = "blob_dns"
  environment {
    id = confluent_environment.staging.id
  }
  domain = trimprefix(trimsuffix(azurerm_storage_account.this.primary_blob_endpoint, "/"), "https://")
  gateway {
    id = confluent_network.private-link.gateway[0].id
  }
  private_link_access_point {
    id = confluent_access_point.main.id
  }
}

resource "confluent_service_account" "app-manager" {
  display_name = "orders-app-sa"
  description  = "Service Account for orders app"
}

resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.dedicated.rbac_crn
}

resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "app-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-manager' service account"
  disable_wait_for_ready = true
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.dedicated.id
    api_version = confluent_kafka_cluster.dedicated.api_version
    kind        = confluent_kafka_cluster.dedicated.kind

    environment {
      id = confluent_environment.staging.id
    }
  }
  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin,

    confluent_private_link_access.azure,
    azurerm_private_dns_zone_virtual_network_link.hz,
    azurerm_private_dns_a_record.rr,
    azurerm_private_dns_a_record.zonal
  ]
}

resource "confluent_connector" "source" {
  environment {
    id = confluent_environment.staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.dedicated.id
  }

  config_sensitive = {
    "kafka.api.key"    = confluent_api_key.app-manager-kafka-api-key.id
    "kafka.api.secret" = confluent_api_key.app-manager-kafka-api-key.secret
  }

  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "DatagenSourceConnector_0"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-manager.id
    "kafka.topic"              = "orders"
    "output.data.format"       = "JSON"
    "quickstart"               = "ORDERS"
    "tasks.max"                = "1"
  }
}

resource "confluent_connector" "sink" {
  environment {
    id = confluent_environment.staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.dedicated.id
  }

  config_sensitive = {
    "kafka.api.key"    = confluent_api_key.app-manager-kafka-api-key.id
    "kafka.api.secret" = confluent_api_key.app-manager-kafka-api-key.secret
  }

  config_nonsensitive = {
    "connector.class"          = "AzureBlobSink"
    "name"                     = "AzureBlobSink_0"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-manager.id
    "topics"                   = "orders"
    "input.data.format"        = "JSON"
    "azblob.account.name"      = azurerm_storage_account.this.name
    "azblob.account.key"       = azurerm_storage_account.this.primary_access_key
    "azblob.container.name"    = azurerm_storage_container.this.name
    "output.data.format"       = "JSON"
    "topics.dir"               = "orders"
    "time.interval"            = "HOURLY"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_connector.source,
    confluent_dns_record.main,
    confluent_access_point.main
  ]
}
