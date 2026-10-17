data "aws_partition" "current" {}

locals {
  arn_prefix     = "arn:${data.aws_partition.current.partition}"
  log_group_arns = "${local.arn_prefix}:logs:${var.aws_region}:${var.aws_account_id}:log-group:/ec2/${var.project}/${var.environment}/*"
  ssm_path_arn   = "${local.arn_prefix}:ssm:${var.aws_region}:${var.aws_account_id}:parameter${var.ssm_parameter_path}"
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.project}-${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-ec2-role"
  })
}

data "aws_iam_policy_document" "ec2_inline" {
  statement {
    sid    = "AppBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*",
    ]
  }

  # Log groups are created by Terraform, so no CreateLogGroup.
  statement {
    sid    = "AppLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      local.log_group_arns,
      "${local.log_group_arns}:*",
    ]
  }

  statement {
    sid    = "AppConfig"
    effect = "Allow"
    actions = [
      "ssm:GetParametersByPath",
      "ssm:GetParameters",
      "ssm:GetParameter",
    ]
    resources = [
      local.ssm_path_arn,
      "${local.ssm_path_arn}/*",
    ]
  }

  dynamic "statement" {
    for_each = length(var.ecr_repository_arns) > 0 ? [1] : []
    content {
      sid    = "EcrPull"
      effect = "Allow"
      actions = [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability",
      ]
      resources = var.ecr_repository_arns
    }
  }

  # GetAuthorizationToken does not support resource-level restrictions.
  dynamic "statement" {
    for_each = length(var.ecr_repository_arns) > 0 ? [1] : []
    content {
      sid       = "EcrLogin"
      effect    = "Allow"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "ec2_inline" {
  name   = "${var.project}-${var.environment}-ec2-policy"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_inline.json
}

# Shell access via SSM Session Manager instead of SSH (no port 22, no keys):
#   aws ssm start-session --target <instance-id>
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "${local.arn_prefix}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.project}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-ec2-profile"
  })
}
