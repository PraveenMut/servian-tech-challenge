## Create IAM and workload federation identity pools for GitHub Actions

resource "google_service_account" "sa_art_repo" {
    account_id = "sa-art-repo"
    display_name = "Artifact Repository Service Account"
}

resource "google_service_account" "sa_github_actions" {
    account_id = "sa-github-actions"
    display_name = "GitHub Actions Service Account"
}

resource "google_service_account" "sa_bastion" {
    account_id = "sa-bastion"
    display_name = "Service Account for the bastion host"
}

resource "google_service_account_iam_member" "sa_github_actions" {
  service_account_id = google_service_account.sa_github_actions.name
  role = "roles/run.developer"
  member = "serviceAccount:${google_service_account.sa_github_actions.email}"
}

resource "google_service_account_iam_member" "sa_bastion" {
    service_account_id = google_service_account.sa_bastion.name
    for_each = [
        "roles/compute.osAdminLogin",
        "roles/iam.serviceAccountUser"
    ]
    role = each.value
    member= "serviceAccount:${google_service_account.sa_bastion.email}"
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
    service_account_id = google_service_account.sa_github_actions.name
    role = "roles/iam.workloadIdentityProvider"
    member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/*"
}

## Create Private VPC connection (Private service connect)

resource "google_compute_network" "private" {
    provider = google-beta
    name = "private-network"
    routing_mode = "REGIONAL"
    depends_on   = [google_project_service.this]
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
    name = var.database_instance_name
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

resource "google_sql_database" "database" {
    name = var.database_name
    instance = google_sql_database_instance.this.name
}

## Create Artifact Factory

resource "google_artifact_registry_repository" "gtd_app" {
    provider = google-beta
    location = var.region
    repository_id = "gtd-app"
    description = "Repository to house the servian gtd application"
    format = "DOCKER"
}

resource "google_artifact_registry_repository_iam_member" "sa_art_repo" {
    provider = google-beta
    location = google_artifact_registry_repository.gtd_app.location
    repository = google_artifact_registry_repository.gtd_app.name
    role = "roles/artifactregistry.writer"
    member = "serviceAccount:${google_service_account.sa_art_repo.email}"
}

## Create the compute instance (bashion host)

resource "google_service_account_key" "sa_bastion" {
    service_account_id = google_service_account.sa_bastion.name
}

resource "tls_private_key" "bastion" {
    algorithm = "RSA"
    rsa_bits = 4096
}

resource "google_os_login_ssh_public_key" "bastion" {
    user = google_service_account.sa_bastion.email
    key = tls_private_key.bashion.public_key_openssh
}

resource "google_compute_instance" "bastion1" {
    name = "bastion-1"
    machine_type = "f1-micro"
    zone = var.zone
    tags = ["bastion"]

    boot_disk {
        initialize_params {
            image = "centos-cloud/centos-7"
            size = 10
        }
    }
    network_interface {
        network = "default"
            access_config {
                # Automatically assign a natted ip
            }
    }
    service_account {
      email = google_service_account.sa_bastion.email
      scopes = ["compute-rw"]
    }

    metadata = {
        enable-oslogin = "TRUE"
    }

    provisioner "remote-exec" {
        connection {
          type = "ssh"
          user = google_service_account.sa_bastion.unique_id
          private_key = tls_private_key.bashion.private_key_pem
        }
        inline = [
          "echo 'Great Scott! We have a connection, Marty!'"
        ]
    }

    depends_on = [
       "google_compute_firewall.allow_ssh_to_bastion",
       "google_service_account.sa_bastion",
       "tls_private_key.bastion"
    ]
}

## Create LB
