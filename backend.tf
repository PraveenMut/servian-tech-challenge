######
# Specify Remote State
######

terraform {
  backend "gcs" {
    bucket      = "servian-terraform"
    prefix      = "terraform/state"
    credentials = file(var.credentials)
  }
}
