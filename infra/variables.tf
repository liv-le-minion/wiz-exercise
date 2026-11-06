variable "region" {
  type    = string
  default = "ap-southeast-2"
}

variable "project" {
  type    = string
  default = "wiz"
}

variable "admin_arn" {
  description = "Olivia's lab IAM user - keeps cluster-admin and KMS admin"
  default     = "arn:aws:iam::228886155047:user/odl_user_2455505"
}
