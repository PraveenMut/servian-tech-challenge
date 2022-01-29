
data "google_client_config" "current" {}

resource "google_project_service" "this" {
  for_each = var.gcp_apis

  service = each.key

  project            = data.google_client_config.current.project
  disable_on_destroy = true
}
