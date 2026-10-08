variable "environment_name" {
  type        = string
  description = "The azd environment name used to name and tag resources."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$", var.environment_name))
    error_message = "Use 1-63 alphanumeric characters or hyphens, starting with an alphanumeric character."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the project resources."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription in which to provision project resources."
}