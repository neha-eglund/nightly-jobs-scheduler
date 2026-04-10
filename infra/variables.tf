variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for the runner"
  type        = string
  default     = "t3.medium"   # 2 vCPU, 4 GB — sufficient for Java + Maven + Claude API calls
}

variable "github_repo" {
  description = "GitHub repository to register the runner against (owner/repo)"
  type        = string
  # e.g. "nehaeglund/claude-github-demo"
}

variable "github_pat" {
  description = "GitHub PAT with 'repo' scope — used once at startup to register the runner"
  type        = string
  sensitive   = true
}

variable "runner_name" {
  description = "Display name for the self-hosted runner in GitHub"
  type        = string
  default     = "nightlyjobs-runner"
}

variable "runner_labels" {
  description = "Comma-separated extra labels to apply to the runner"
  type        = string
  default     = "nightlyjobs,self-hosted,linux,x64"
}

variable "runner_version" {
  description = "GitHub Actions runner version to install"
  type        = string
  default     = "2.317.0"
}