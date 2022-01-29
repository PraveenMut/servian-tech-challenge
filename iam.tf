## Create IAM and workload federation identity pools for GitHub Actions

resource "google_service_account" "sa_art_repo" {
    account_id = "sa-art-repo"
    display_name = "Artifact Repository Service Account"
}

resource "google_service_account" "sa_github_actions" {
    account_id = "sa-github-actions"
    display_name = "GitHub Actions Service Account"
}

resource "google_service_account" "sa_bastion" {
    account_id = "sa-bastion"
    display_name = "Service Account for the bastion host"
}

resource "google_service_account_iam_member" "sa_github_actions" {
  service_account_id = google_service_account.sa_github_actions.name
  role = "roles/run.developer"
  member = "serviceAccount:${google_service_account.sa_github_actions.email}"
}

resource "google_service_account_iam_member" "sa_bastion" {
    service_account_id = google_service_account.sa_bastion.name
    for_each = [
        "roles/compute.osAdminLogin",
        "roles/iam.serviceAccountUser"
    ]
    role = each.key
    member= "serviceAccount:${google_service_account.sa_bastion.email}"
}

resource "google_iam_workload_identity_pool" "github_pool" {
    provider = google-beta
    workload_identity_pool_id = "github-pool-1"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
    provider = google-beta
    workload_identity_pool_id = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
    workload_identity_pool_provider_id = "github_provider-1"
    display_name = "GitHub WIF Provider"
    attribute_mapping = {
        "google.subject" = "assertion.sub"
        "attribute.aud"  = "assertion.aud"
        "attribute.actor" = "assertion.actor"
    }
    oidc {
      allowed_audiences = ["sigstore"]
      issuer_uri = "https://vstoken.actions.githubusercontent.com"
    }
}

resource "google_service_account_iam_member" "gh_pool_impersonator" {
    provider = google-beta
    service_account_id = google_service_account.sa_github_actions.name
    role = "roles/iam.workloadIdentityProvider"
    member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/*"
}
