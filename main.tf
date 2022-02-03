## Create Private VPC connection (Private service connect)

data "google_compute_network" "default" {
  name = var.vpc
}

data "google_service_account_access_token" "this" {
 provider               	= google
 target_service_account 	= google_service_account.sa_bastion.email
 scopes                 	= ["userinfo-email", "cloud-platform"]
 lifetime               	= "1800s"
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

## Create the compute instance (bashion host)

resource "google_service_account_key" "sa_bastion" {
  service_account_id = google_service_account.sa_bastion.name
}

resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


resource "google_os_login_ssh_public_key" "bastion" {
  provider = google.impersonator
  user = google_service_account.sa_bastion.email
  key  = tls_private_key.bastion.public_key_openssh
  depends_on = [google_service_account_iam_binding.bastion_token_creator]
}

resource "google_compute_instance" "bastion1" {
  provider     = google
  name         = "bastion-1"
  machine_type = "f1-micro"
  zone         = var.zone
  tags         = var.network_source_tags

  boot_disk {
    initialize_params {
      image = "centos-cloud/centos-7"
      size  = 20
    }
  }
  network_interface {
    network = "default"
    access_config {
      # Automatically assign a natted ip
    }
  }
  service_account {
    email  = google_service_account.sa_bastion.email
    scopes = ["compute-rw", "sql-admin"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-EOT
    #!/bin/bash
    yum update;
    yum install -y yum-utils;
    yum install -y git;
    yum install -y golang;
    EOT

  provisioner "file" {
    connection {
      type        = "ssh"
      host        = self.network_interface[0].access_config[0].nat_ip
      user        = "sa_${google_service_account.sa_bastion.unique_id}"
      private_key = tls_private_key.bastion.private_key_pem
    }
    source = "post_init.sh"
    destination = "/tmp/post_init.sh"
  }
  depends_on = [
    google_sql_database.app,
    google_project_iam_member.sa_bastion,
    google_os_login_ssh_public_key.bastion,
    google_compute_firewall.allow_ssh_to_bastion
  ]
}

resource "null_resource" "initalisation_script" {
  connection {
    type        = "ssh"
    host        = google_compute_instance.bastion1.network_interface[0].access_config[0].nat_ip
    user        = "sa_${google_service_account.sa_bastion.unique_id}"
    private_key = tls_private_key.bastion.private_key_pem
  }
  
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/post_init.sh",
      "VTT_DBUSER=${var.database_username} VTT_DBPASSWORD=${var.database_password} VTT_DBHOST=\"127.0.0.1\" /tmp/post_init.sh"
      ]
  }
  depends_on = [google_compute_instance.bastion1]
}

## Create LB
