####
# Entrypoint script of initating project
####

#!/bin/bash

set -euo pipefail

cd ..

mkdir -p .config

# Create vars to specify relevant authN
export PROJECT_NAME="servian-gtd-application-tester"
export TF_ADMIN="terraform-administrator"
export TF_CREDS="${PWD}/.config/${TF_ADMIN}.json"
export BILLING_ACCOUNT="$(gcloud beta billing accounts list | grep "True" | awk '{print $1}' | tr -d '\r\n')"
export BUCKET_NAME="servian-terraform"

# specify vars for terraform runs
export GOOGLE_PROJECT="${PROJECT_NAME}"

# Create project, underlying IAM for the terraform user
echo "Creating Project..."
gcloud projects create ${PROJECT_NAME} \
    --set-as-default

echo "Linking Billing..."
gcloud beta billing projects link ${PROJECT_NAME} \
    --billing-account ${BILLING_ACCOUNT}

echo "Create Terraform Service Account..."
gcloud iam service-accounts create ${TF_ADMIN} \
    --display-name "terraform-admin-account"

echo "Fetching Keys..."
echo "WARNING: THIS IS SENSITIVE DATA. DO NOT COMMIT THE PRIVATE KEY."
gcloud iam service-accounts keys create ${TF_CREDS} \
    --iam-account ${TF_ADMIN}@${PROJECT_NAME}.iam.gserviceaccount.com


# Wait for the service account gets propgated
sleep 30

echo "Adding IAM policies for the terraform account..."

ROLES=(
    "roles/editor" 
    "roles/artifactregistry.admin" 
    "roles/iam.serviceAccountAdmin" 
    "roles/iam.serviceAccountTokenCreator" 
    "roles/iam.workloadIdentityPoolAdmin" 
    "roles/resourcemanager.projectIamAdmin" 
    "roles/servicenetworking.networksAdmin" 
    "roles/storage.admin"
)

for r in "${ROLES[@]}"
do
    echo "Adding IAM Policy Binding ${r}"
    gcloud projects add-iam-policy-binding ${PROJECT_NAME} \
    --member serviceAccount:${TF_ADMIN}@${PROJECT_NAME}.iam.gserviceaccount.com \
    --role "${r}"
done

# Enable the serviceusage API to allow terraform to create IAM
echo "Enable APIs to allow Terraform to interact with the underlying GCP REST APIs..."

SERVICES=(
    "serviceusage.googleapis.com" 
    "cloudresourcemanager.googleapis.com" 
    "iam.googleapis.com" 
    "compute.googleapis.com" 
    "run.googleapis.com"
    "cloudresourcemanager.googleapis.com" 
    "vpcaccess.googleapis.com" 
    "artifactregistry.googleapis.com" 
    "sqladmin.googleapis.com" 
    "servicenetworking.googleapis.com" 
    "iamcredentials.googleapis.com" 
    "sts.googleapis.com"
    )
for s in "${SERVICES[@]}"
do
    echo "Enabling service ${s}"
    gcloud services enable "${s}"
done

# Create bucket for remote state and set versioning
echo "Create Bucket for remote TF state..."
gsutil mb -p ${PROJECT_NAME} -l australia-southeast1 gs://${BUCKET_NAME}
gsutil versioning set on gs://${BUCKET_NAME}

#Init the backend
echo "Initalising Terraform..."
GOOGLE_APPLICATION_CREDENTIALS="${TF_CREDS}" terraform init


echo "|-------------------------------------------|"
echo "|        Initialisation Complete.           |"
echo "|-------------------------------------------|"
echo ""
echo "To provision underlying resources. Run terraform plan."
echo "Terraform Plan can be run with exported environment variables."
echo "Alternatively, you can use the provided convenience wrapper."
echo "The convenience wrapper ensures that credentials aren't stored in the shell."
echo "It also initalises the TF default credentials."
echo "Usage ./terrawrapper.sh [plan|apply|output]"
echo "If satisfactory, Run a terraform apply."

echo "Afterwards, run the CI/CD pipeline."
echo "This pipeline will build and push the image to Google Artifact Repository."
echo "This pushed image will then be used by Cloud Run to serve the application."