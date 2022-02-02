provider "google" {
  project     = var.project
  region      = var.region
  credentials = file(var.credentials)
}

provider "google" {
  alias = "impersonator"
  access_token = data.google_service_account_access_token.this.access_token
  project = var.project
  region = var.region
  scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/userinfo.email"
  ]
}

provider "google-beta" {
  project     = var.project
  region      = var.region
  credentials = file(var.credentials)
}

provider "tls" {

}