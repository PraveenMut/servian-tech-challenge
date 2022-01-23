
data "google_client_config" "current" {}

resource "google_project_service" "this" {
  for_each = toset([
    "compute.googleapis.com",
    "run.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "vpcaccess.googleapis.com",
    "containerregistry.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com"
  ])

  service = each.key

  project            =  data.google_client_config.current.project
  disable_on_destroy = true
}