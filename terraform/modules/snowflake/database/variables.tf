variable "database_name" {
  description = "Name of the Snowflake database to create."
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod). Used in resource comments."
  type        = string
}
