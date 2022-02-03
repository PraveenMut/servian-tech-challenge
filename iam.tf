## Create IAM and workload federation identity pools for GitHub Actions

data "google_compute_default_service_account" "default" {}

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

resource "google_project_iam_member" "sa_github_actions" {
  project = var.project
  role = "roles/run.admin"
  member = "serviceAccount:${google_service_account.sa_github_actions.email}"
}

resource "google_project_iam_member" "sa_bastion" {
    project = var.project
    for_each = toset([
        "roles/compute.instanceAdmin",
        "roles/cloudsql.editor",
        "roles/compute.instanceAdmin.v1",
        "roles/compute.osAdminLogin",
        "roles/iam.serviceAccountUser",
    ])
    role = each.key
    member= "serviceAccount:${google_service_account.sa_bastion.email}"
}

resource "google_service_account_iam_member" "gh_compute_impersonate" {
  service_account_id = data.google_compute_default_service_account.default.name
  role = "roles/iam.serviceAccountUser"
  member = "serviceAccount:${google_service_account.sa_github_actions.email}"
}

resource "google_service_account_iam_binding" "bastion_token_creator" {
  service_account_id = google_service_account.sa_bastion.name
  role = "roles/iam.serviceAccountTokenCreator"
  members = ["serviceAccount:terraform-admin@${var.project}.iam.gserviceaccount.com"]
}

module "gh_oidc" {
  source      = "terraform-google-modules/github-actions-runners/google//modules/gh-oidc"
  project_id  = var.project
  pool_id     = "github-actions-pool"
  provider_id = "github-actions-provider"
  attribute_mapping = {
      "google.subject" = "assertion.sub"
      "attribute.aud"  = "assertion.aud"
      "attribute.actor" = "assertion.actor"
  }
  allowed_audiences = ["sigstore"]
  provider_description = "Workload Federated Identity pool for GitHub Actions"
  provider_display_name = "GitHub Actions WIF"
  sa_mapping = {
    "sa_github_actions" = {
      sa_name   = "projects/${var.project}/serviceAccounts/${google_service_account.sa_github_actions.email}"
      attribute = "*"
    }
  }
}
