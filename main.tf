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
  network                 = google_compute_network.private.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
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
  depends_on = [google_project_service.this]
}

resource "google_artifact_registry_repository_iam_member" "sa_art_repo" {
  provider   = google-beta
  location   = google_artifact_registry_repository.gtd_app.location
  repository = google_artifact_registry_repository.gtd_app.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.sa_art_repo.email}"
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
    yum install -y yum-utils;
    yum-config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo";
    yum install -y docker-ce docker-ce-cli containerd.io;
    EOT

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = self.network_interface[0].access_config[0].nat_ip
      user        = google_service_account.sa_bastion.unique_id
      private_key = tls_private_key.bastion.private_key_pem
    }
    inline = [
      "sudo systemctl start docker",
      "sudo usermod -aG docker $USER",
      "newgrp docker",
      "curl -L https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -o cloud_sql_proxy",
      "chmod +x cloud_sql_proxy",
      "sudo mv cloud_sql_proxy /usr/local/bin",
      "docker pull servian/techchallengeapp",
      "cloud-sql-proxy -instances=${google_sql_database_instance.this.connection_name}=tcp:5432 &",
      "docker run -e VTT_DBUSER=${var.database_username} -e VTT_DBPASSWORD=${var.database_password} -e VTT_DBHOST=\"127.0.0.1\" servian/techchallengeapp updatedb -s"
    ]
  }
  depends_on = [
    google_project_service.this,
    google_sql_database.app,
    google_compute_firewall.allow_ssh_to_bastion,
  ]
}

## Create LB
