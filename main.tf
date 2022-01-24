## Create IAM and workload federation identity pools for GitHub Actions

resource "google_service_account" "sa-art-repo" {
    account_id = "sa-art-repo"
    display_name = "Artifact Repository Service Account"
}

resource "google_iam_workload_identity_pool" "github_pool" {
    provider = google-beta
    workload_identity_pool_id = "github-pool-1"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
    provider = google-beta
    workload_identity_pool_id = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
    workload_identity_pool_provider_id = "github_provider-1"
    display_name = "GitHub WIF Provider"
    attribute_mapping = {
        "google.subject" = "assertion.sub"
        "attribute.aud"  = "assertion.aud"
        "attribute.actor" = "assertion.actor"
    }
    oidc {
      allowed_audiences = ["sigstore"]
      issuer_uri = "https://vstoken.actions.githubusercontent.com"
    }
}

resource "google_service_account_iam_member" "gh_pool_impersonator" {
    provider = google-beta
    service_account_id = google_service_account.sa-art-repo.name
    role = "roles/iam.workloadIdentityProvider"
    member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/*"
}

## Create Private VPC connection (Private service connect)

resource "google_compute_network" "private" {
    provider = google-beta
    name = "private-network"
    routing_mode = "REGIONAL"
}

resource "google_compute_global_address" "private_ip_address" {
    provider = google-beta
    name = "private-ip-address"
    purpose = "VPC_PEERING"
    address_type = "INTERNAL"
    prefix_length = 16
    network = google_compute_network.private.self_link
}

resource "google_service_networking_connection" "private_vpc" {
    provider = google-beta
    network = google_compute_network.private.self_link
    service = "servicenetworking.googleapis.com"
    reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

## Create Serverless VPC Connector

resource "google_vpc_access_connector" "this" {
  provider      = google-beta
  name          = "servian-gtd-app"
  region        =  var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.private.name
  machine_type  = "e2-micro"
}

## Create Postgres DB

resource "google_sql_database_instance" "this" {
    provider = google-beta
    name = var
    region = var.region
    database_version = "POSTGRES_9_6"
    depends_on = [google_service_networking_connection.private_vpc_connection]
    settings {
        tier = "db-f1-micro"
        availability_type = "REGIONAL"
        backup_configuration {
          enabled = True
          backup_retention_settings {
            retained_backups = 365
          }
        }
        user_labels = {
            name  = var.database_name
            type = "postgres"
        }
        ip_configuration {
          ipv4_enabled = false
          private_network = google_compute_network.private.self_link
        }
    }
}

## Create Artifact Factory

resource "google_artifact_registry_repository" "gtd-app" {
    provider = google-beta
    location = var.region
    repository_id = "gtd-app"
    description = "Repository to house the servian gtd application"
    format = "DOCKER"
}

resource "google_artifact_registry_repository_iam_member" "sa-art-repo" {
    provider = google-beta
    location = google_artifact_registry_repository.gtd-app.location
    repository = google_artifact_registry_repository.gtd-app.name
    role = "roles/artifactregistry.writer"
    member = "serviceAccount:${google_service_account.sa-art-repo.email}"
}

## Create the compute instance (bashion host)

## execute remote commands

## Seed DB

## Create LB
