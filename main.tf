## Create Private VPC connection (Private service connect)

data "google_compute_network" "default" {
  name = var.vpc
}


resource "google_compute_global_address" "private_services" {
  provider      = google-beta
  name          = "private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = data.google_compute_network.default.self_link
}

resource "google_service_networking_connection" "private_services" {
  provider                = google-beta
  network                 = data.google_compute_network.default.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

## Create Serverless VPC Connector

resource "google_vpc_access_connector" "this" {
  provider      = google-beta
  name          = var.app_name
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = var.vpc
  machine_type  = "e2-micro"
}

## Create Postgres DB

resource "google_sql_database_instance" "this" {
  provider         = google
  name             = var.database_instance_name
  region           = var.region
  database_version = "POSTGRES_9_6"
  depends_on       = [google_service_networking_connection.private_services]
  settings {
    tier              = "db-f1-micro"
    availability_type = "REGIONAL"
    backup_configuration {
      enabled = true
      backup_retention_settings {
        retained_backups = 365
      }
    }
    user_labels = {
      name = var.database_name
      type = "postgres"
    }
    ip_configuration {
      ipv4_enabled    = false
      private_network = data.google_compute_network.default.self_link
    }
  }
}

resource "google_sql_user" "this" {
  provider = google
  name     = "postgres"
  instance = google_sql_database_instance.this.name
  password = var.database_password
}

resource "google_sql_database" "app" {
  name     = var.database_name
  instance = google_sql_database_instance.this.name
}

## Create Artifact Factory

resource "google_artifact_registry_repository" "gtd_app" {
  provider      = google-beta
  location      = var.region
  repository_id = var.app_name
  description   = "Repository to house the servian gtd application"
  format        = "DOCKER"
}

resource "google_artifact_registry_repository_iam_binding" "service_accounts" {
  provider   = google-beta
  location   = google_artifact_registry_repository.gtd_app.location
  repository = google_artifact_registry_repository.gtd_app.name
  role       = "roles/artifactregistry.writer"
  members    =  [
    "serviceAccount:${google_service_account.sa_art_repo.email}",
    "serviceAccount:${google_service_account.sa_github_actions.email}"
  ]
}
