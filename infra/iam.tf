# IAM role for the EC2 runner instance.
# Only needs SSM access (for Systems Manager session management — no SSH required)
# and the ability to read its own SSM parameters.

resource "aws_iam_role" "runner" {
  name = "nightlyjobs-runner"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM Session Manager — lets you shell into the instance without opening port 22
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow the instance to read its secrets from SSM Parameter Store
resource "aws_iam_role_policy" "read_params" {
  name = "read-runner-params"
  role = aws_iam_role.runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/nightlyjobs/*"
    }]
  })
}

resource "aws_iam_instance_profile" "runner" {
  name = "nightlyjobs-runner"
  role = aws_iam_role.runner.name
}