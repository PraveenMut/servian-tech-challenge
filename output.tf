output "workload_identity_pool_id" {
  value = google_iam_workload_identity_pool_provider.github_provider.name
}