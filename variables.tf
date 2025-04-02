variable "hwc_access_key" {
  type        = string
  description = "description"
}

variable "hwc_secret_key" {
  type        = string
  description = "description"
}

variable "region" {
  type = string
  description = "A map of Huawei Cloud regions with descriptions"
  
}

variable "enterprise_project" {
  type = string
}

variable "ecs_pass" {
  type = string
  description = "Standard password used for ECSs"
}

variable "bastion_public_port" {
  type = string
  description = "Port used for ssh with the bastion ECS through the NAT Gateway"
}
