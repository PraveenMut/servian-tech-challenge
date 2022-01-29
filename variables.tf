variable "project" {
    type = string
    default = "servian-gtd"
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