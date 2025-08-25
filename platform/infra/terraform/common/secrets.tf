# AWS Secrets Manager resources for the platform

# PostgreSQL password for Backstage application
resource "aws_secretsmanager_secret" "backstage_postgresql_password" {
  name        = "${var.project_context_prefix}-backstage-postgresql-password"
  description = "PostgreSQL password for Backstage application"
  
  tags = {
    Application = "Backstage"
    Environment = "Platform"
    ManagedBy   = "Terraform"
    Purpose     = "Database Authentication"
  }
}

# Generate a random password for PostgreSQL
resource "random_password" "backstage_postgresql_password" {
  length  = 32
  special = true
  # Exclude characters that might cause issues in connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store the password in AWS Secrets Manager
resource "aws_secretsmanager_secret_version" "backstage_postgresql_password" {
  secret_id     = aws_secretsmanager_secret.backstage_postgresql_password.id
  secret_string = jsonencode({
    password = random_password.backstage_postgresql_password.result
  })
}

# Additional secrets can be added here as needed
# For example, other application passwords, API keys, etc.
