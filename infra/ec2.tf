# Security group — egress-only.
# The runner initiates all connections outbound (to GitHub and Anthropic API).
# No inbound ports needed; access the instance via SSM Session Manager.
resource "aws_security_group" "runner" {
  name        = "nightlyjobs-runner"
  description = "Egress-only SG for the NightlyJobs self-hosted runner"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "HTTPS to GitHub, Anthropic API, package repos"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP for apt package downloads"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# User data — runs once on first boot.
# Installs all tooling (Java 24, Maven, gh CLI) and registers the runner as a systemd service.
locals {
  user_data = <<SHELL
#!/usr/bin/env bash
set -x
exec > /var/log/runner-init.log 2>&1

    echo "=== STEP 0: Swap (2 GB) ==="
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    free -h

    echo "=== STEP 1: System packages ==="
    export DEBIAN_FRONTEND=noninteractive
    nice -n 10 apt-get update -q
    nice -n 10 apt-get install -y --no-install-recommends \
      curl ca-certificates git jq unzip python3 || { echo "FAILED: apt packages"; exit 1; }

    echo "=== STEP 2: AWS CLI v2 ==="
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    rm -rf /tmp/awscliv2.zip /tmp/aws
    aws --version || { echo "FAILED: aws cli install"; exit 1; }

    echo "=== STEP 3: Java 24 (Temurin) ==="
    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
      | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg
    echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb noble main" \
      > /etc/apt/sources.list.d/adoptium.list
    nice -n 10 apt-get update -q
    nice -n 10 apt-get install -y temurin-24-jdk || { echo "FAILED: temurin install"; exit 1; }
    java -version

    echo "=== STEP 4: Maven ==="
    nice -n 10 apt-get install -y --no-install-recommends maven || { echo "FAILED: maven install"; exit 1; }
    mvn -version

    echo "=== STEP 5: GitHub CLI ==="
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list
    apt-get update -q && apt-get install -y gh || { echo "FAILED: gh cli install"; exit 1; }
    gh --version

    echo "=== STEP 6: Read secrets from SSM ==="
    REGION="${var.aws_region}"
    GITHUB_PAT=$(aws ssm get-parameter \
      --name "/nightlyjobs/github-pat" \
      --with-decryption \
      --region "$REGION" \
      --query "Parameter.Value" \
      --output text) || { echo "FAILED: read github-pat from SSM"; exit 1; }
    echo "PAT length: $${#GITHUB_PAT}"

    GITHUB_REPO=$(aws ssm get-parameter \
      --name "/nightlyjobs/github-repo" \
      --region "$REGION" \
      --query "Parameter.Value" \
      --output text) || { echo "FAILED: read github-repo from SSM"; exit 1; }
    echo "Repo: $GITHUB_REPO"

    echo "=== STEP 7: Download runner ==="
    RUNNER_VERSION="${var.runner_version}"
    RUNNER_DIR="/opt/actions-runner"
    useradd -m -s /bin/bash runner 2>/dev/null || true
    mkdir -p "$RUNNER_DIR"

    curl -fsSL \
      "https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz" \
      -o /tmp/runner.tar.gz || { echo "FAILED: runner download"; exit 1; }
    tar -xz -C "$RUNNER_DIR" -f /tmp/runner.tar.gz || { echo "FAILED: runner extract"; exit 1; }
    rm /tmp/runner.tar.gz
    chown -R runner:runner "$RUNNER_DIR"
    ls -la "$RUNNER_DIR"

    echo "=== STEP 8: Get registration token ==="
    REG_TOKEN=$(curl -fsSL -X POST \
      -H "Authorization: Bearer $GITHUB_PAT" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/$GITHUB_REPO/actions/runners/registration-token" \
      | jq -r '.token')
    echo "Token received: $${REG_TOKEN:0:4}..."
    [ "$REG_TOKEN" != "null" ] || { echo "FAILED: token is null — check PAT permissions"; exit 1; }

    echo "=== STEP 9: Configure runner ==="
    sudo -u runner "$RUNNER_DIR/config.sh" \
      --url "https://github.com/$GITHUB_REPO" \
      --token "$REG_TOKEN" \
      --name "${var.runner_name}" \
      --labels "${var.runner_labels}" \
      --unattended \
      --replace || { echo "FAILED: runner config"; exit 1; }

    echo "=== STEP 10: Install systemd service ==="
    cat > /etc/systemd/system/github-runner.service << EOF
[Unit]
Description=GitHub Actions Runner (NightlyJobs)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=runner
WorkingDirectory=/opt/actions-runner
ExecStart=/opt/actions-runner/run.sh
Restart=always
RestartSec=10
KillMode=process
StandardOutput=append:/var/log/github-runner.log
StandardError=append:/var/log/github-runner.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable github-runner
    systemctl start github-runner
    systemctl status github-runner --no-pager

    echo "=== STEP 11: CloudWatch agent ==="
    curl -fsSL https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
      -o /tmp/cwagent.deb && dpkg -i /tmp/cwagent.deb && rm /tmp/cwagent.deb

    echo '{"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/var/log/runner-init.log","log_group_name":"/nightlyjobs/runner-init","log_stream_name":"{instance_id}","retention_in_days":7},{"file_path":"/var/log/github-runner.log","log_group_name":"/nightlyjobs/runner","log_stream_name":"{instance_id}","retention_in_days":7},{"file_path":"/opt/actions-runner/_diag/Worker_*.log","log_group_name":"/nightlyjobs/runner-worker","log_stream_name":"{instance_id}","retention_in_days":7}]}}}}' \
      > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

    echo "=== Bootstrap complete — runner is online ==="
SHELL
}

resource "aws_instance" "runner" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.runner.id]
  iam_instance_profile   = aws_iam_instance_profile.runner.name

  # Public IP so the instance can reach GitHub and Anthropic API without a NAT Gateway
  associate_public_ip_address = true

  user_data                   = local.user_data
  user_data_replace_on_change = true   # replace instance if user_data changes

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30   # GB — enough for Maven cache + runner workspace
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens = "required"   # IMDSv2 only — security best practice
  }

  tags = { Name = var.runner_name }
}