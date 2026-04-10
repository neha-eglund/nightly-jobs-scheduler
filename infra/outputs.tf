output "runner_public_ip" {
  description = "Public IP of the runner instance (for reference — use SSM Session Manager to connect)"
  value       = aws_instance.runner.public_ip
}

output "runner_instance_id" {
  description = "EC2 instance ID — use with 'aws ssm start-session' to get a shell"
  value       = aws_instance.runner.id
}

output "ssm_connect_command" {
  description = "Command to open a shell on the runner via SSM (no SSH key or port 22 needed)"
  value       = "aws ssm start-session --target ${aws_instance.runner.id} --region ${var.aws_region}"
}

output "runner_logs" {
  description = "Command to tail the bootstrap log on the runner"
  value       = "aws ssm start-session --target ${aws_instance.runner.id} --region ${var.aws_region} --document-name AWS-StartInteractiveCommand --parameters command='tail -f /var/log/runner-init.log'"
}