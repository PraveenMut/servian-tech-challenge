provider "google" {
  project     = var.project
  region      = var.region
  credentials = file(var.credentials)
}

provider "google-beta" {
  project     = var.gcp_project
  region      = var.gcp_region
  credentials = file(var.credentials)
}

provider "tls" {

}