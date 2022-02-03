variable "project" {
    type = string
    default = "servian-gtd-application"
}

variable "app_name" {
  type = string
  default = "gtd-app"
}

variable "vpc" {
  type = string
  default = "default"
}

variable "region" {
    type = string
    default = "australia-southeast1"
}

variable "zone" {
    type = string
    default = "australia-southeast1-a"
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
      "iam.googleapis.com",
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

variable "database_username" {
  type = string
}

variable "database_password" {
  type = string
  sensitive = true
}