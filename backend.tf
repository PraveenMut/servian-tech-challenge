######
# Specify Remote State
######

terraform {
  backend "gcs" {
    bucket      = "servian-terraform-state"
    prefix      = "terraform/state"
  }
}
