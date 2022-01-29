variable "project" {
    type = string
    default = "servian-gtd"
}

variable "app_name" {
  type = string
  default = "gtd-app"
}

variable "region" {
    type = string
    default = "australia-southeast-1"
}

variable "zone" {
    type = string
    default = "australia-southeast-1a"
}

variable "database_instance_name" {
  type = string
  default = "gtd-db"
}

variable "credentials" {
    type = string
}

variable "database_name" {
  type = string
  default = "app"
}

variable "gcp_apis" {
    type = set(string)
    default = [
      "compute.googleapis.com",
      "run.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "vpcaccess.googleapis.com",
      "containerregistry.googleapis.com",
      "sqladmin.googleapis.com",
      "servicenetworking.googleapis.com"
    ]
}

variable "network_source_tags" {
  type = list(string)
  default = ["bastion"]
}
