## Allow access to Bastion host through SSH


## East-west traffic between bastion to DB will not be necessary
## as Google Cloud SQL Proxy will provide a secure tunnel to the
## DB instance.
resource "google_compute_firewall" "allow_ssh_to_bastion" {
    name    = "allow-ssh-to-bastion"
    network = var.vpc
    direction = "INGRESS"

    allow {
        protocol = "tcp"
        ports = ["22"]
    }

    source_tags = var.network_source_tags
} 
