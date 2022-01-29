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

resource "google_sql_database" "app" {
    name = var.database_name
    instance = google_sql_database_instance.this.name
}

## Create Artifact Factory

resource "google_artifact_registry_repository" "gtd_app" {
    provider = google-beta
    location = var.region
    repository_id = var.app_name
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
    tags = var.network_source_tags

    boot_disk {
        initialize_params {
            image = "centos-cloud/centos-7"
            size = 20
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

    metadata_startup_script = <<EOF
      #!/bin/bash
      yum install -y yum-utils;
      yum-config-manager --add-repo "https://download.docker.com/linux/centos/docker-ce.repo";
      yum install -y docker-ce docker-ce-cli containerd.io;
      systemctl start docker
      EOF

    provisioner "remote-exec" {
        connection {
          type = "ssh"
          user = google_service_account.sa_bastion.unique_id
          private_key = tls_private_key.bashion.private_key_pem
        }
        inline = [
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
       "google_compute_firewall.allow_ssh_to_bastion",
       "google_service_account.sa_bastion",
       "tls_private_key.bastion",
       "google_sql_database.app"
    ]
}

## Create LB
