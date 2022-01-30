
resource "google_project_service" "this" {
  for_each = var.gcp_apis

  service = each.key

  disable_on_destroy = true
}
