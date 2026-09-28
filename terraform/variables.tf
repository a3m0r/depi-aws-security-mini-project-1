variable "project_name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "depi-sec"
}

variable "region" {
  description = "One Region for everything (fixed by the project rules)."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR of app-vpc. Subnets are calculated from it."
  type        = string
  default     = "10.0.0.0/16"
}

variable "tools_vpc_cidr" {
  description = "CIDR of tools-vpc. Must NOT overlap with vpc_cidr or peering fails."
  type        = string
  default     = "10.1.0.0/16"
}

variable "alert_email" {
  description = "Email that receives budget, alarm and remediation messages."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must look like name@example.com."
  }
}

variable "owner" {
  description = "Your name. Goes into the Owner tag."
  type        = string
  default     = "student"
}

variable "lock_alb_to_cloudfront" {
  description = <<-EOT
    true  = final design (Task 13): ALB answers 403 unless the secret header is present.
    false = Task 12 mode: ALB forwards everything, so you can test it directly in a browser.
  EOT
  type        = bool
  default     = true
}
