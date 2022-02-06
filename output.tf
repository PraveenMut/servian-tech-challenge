## Obtain the workload identity provider ID
output "workload_identity_pool_id" {
  value = module.gh_oidc.provider_name
}

## obtain the private key to ssh into the bastion instance
output "private_key_pem" {
  sensitive = true
  value = tls_private_key.bastion
}

## obtain os login ssh user tied to the service account
output "unique_id" {
  value = "sa_${google_service_account.sa_bastion.unique_id}"
}

## obtain host IP
output "host" {
  value = google_compute_instance.bastion1.network_interface[0].access_config[0].nat_ip
}