data "google_service_account_access_token" "this" {
 provider               	= google
 target_service_account 	= google_service_account.sa_bastion.email
 scopes                 	= ["userinfo-email", "cloud-platform"]
 lifetime               	= "1800s"
}

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
    source = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }
  depends_on = [
    google_sql_database.app,
    google_project_iam_member.sa_bastion,
    google_os_login_ssh_public_key.bastion,
    google_compute_firewall.allow_ssh_to_bastion
  ]
}

## Race Condition Mitigation.
## Although the underlying Google APIs may report
## a 202 Created or a successful creation
## Terraform may interpret this as a fully successful instance creation.
## We need to ensure all of the depedencies are fully installed in the
## metadata startup scripts. 
## The quickest way to implement this is in a sleep function or a derivative 
## of a retry fn in bash. Either way, it does the same thing. Avoids accessing the deps
## prior to their actual installation. 
resource "time_sleep" "wait_120_seconds" {
  create_duration = "120s"
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
      "sudo chmod +x /tmp/bootstrap.sh",
      "VTT_DBUSER=${var.database_username} VTT_DBPASSWORD=${var.database_password} VTT_DBHOST=\"127.0.0.1\" /tmp/bootstrap.sh"
      ]
  }
  depends_on = [google_compute_instance.bastion1, time_sleep.wait_120_seconds]
}

