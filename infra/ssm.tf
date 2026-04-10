# Store the GitHub PAT in SSM Parameter Store (SecureString).
# The EC2 instance reads it at first boot to register the runner,
# so the token never appears in plaintext in user_data or Terraform state.

resource "aws_ssm_parameter" "github_pat" {
  name        = "/nightlyjobs/github-pat"
  description = "GitHub PAT used to register the self-hosted Actions runner"
  type        = "SecureString"
  value       = var.github_pat
}

resource "aws_ssm_parameter" "github_repo" {
  name        = "/nightlyjobs/github-repo"
  description = "GitHub repo the runner is registered against (owner/repo)"
  type        = "String"
  value       = var.github_repo
}