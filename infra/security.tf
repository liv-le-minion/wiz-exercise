# ================= Step 13: Cloud native security =================
data "aws_caller_identity" "sec" {}
data "aws_region" "sec" {}

locals {
  trail_name = "${var.project}-audit-trail"
  trail_arn  = "arn:aws:cloudtrail:${data.aws_region.sec.region}:${data.aws_caller_identity.sec.account_id}:trail/${local.trail_name}"
}

# ---------- AUDIT LOGGING: CloudTrail -> private, versioned bucket + CloudWatch Logs ----------
resource "aws_s3_bucket" "trail" {
  #checkov:skip=CKV2_AWS_61:Lifecycle rules deliberately denied by the guardrail so audit logs cannot be expired
  #checkov:skip=CKV_AWS_144:Single-region lab; production would replicate to a separate log-archive account
  #checkov:skip=CKV_AWS_145:SSE-S3 default encryption; KMS CMK out of scope for the lab, used in production
  #checkov:skip=CKV_AWS_18:Access logging needs a further bucket; CloudTrail records changes to this bucket
  #checkov:skip=CKV2_AWS_62:No consumers for S3 event notifications; alerting is via GuardDuty and SNS
  bucket = "${var.project}-audit-logs-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.sec.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  # PREVENTATIVE CONTROL: nobody - attacker or admin - can delete or expire audit logs
  statement {
    sid    = "DenyAuditLogDeletion"
    effect = "Deny"
    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:DeleteBucket",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketVersioning",
    ]
    resources = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  # PREVENTATIVE CONTROL: only Olivia and the pipeline can change this policy
  statement {
    sid       = "DenyPolicyTampering"
    effect    = "Deny"
    actions   = ["s3:PutBucketPolicy", "s3:DeleteBucketPolicy"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [var.admin_arn, aws_iam_role.github_actions.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket     = aws_s3_bucket.trail.id
  policy     = data.aws_iam_policy_document.trail_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.trail, aws_s3_bucket_versioning.trail]
}

resource "aws_cloudwatch_log_group" "trail" {
  #checkov:skip=CKV_AWS_158:CloudWatch Logs default encryption; KMS CMK used in production
  name              = "/aws/cloudtrail/${local.trail_name}"
  retention_in_days = 365
}

resource "aws_iam_role" "trail_to_cwl" {
  name = "${var.project}-cloudtrail-to-cwl"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "trail_to_cwl" {
  role = aws_iam_role.trail_to_cwl.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "audit" {
  #checkov:skip=CKV_AWS_252:Per-log-delivery SNS is noise; alerting is via GuardDuty, EventBridge and SNS
  #checkov:skip=CKV_AWS_35:SSE-S3 encryption; KMS CMK out of scope for the lab, used in production
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_to_cwl.arn

  advanced_event_selector {
    name = "All management events"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  advanced_event_selector {
    name = "Who reads the public backup bucket"
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
    field_selector {
      field       = "resources.ARN"
      starts_with = ["${aws_s3_bucket.backups.arn}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.trail, aws_iam_role_policy.trail_to_cwl]
}

# ---------- DETECTIVE CONTROL: GuardDuty + email alert on high-severity findings ----------
resource "aws_guardduty_detector" "main" {
  #checkov:skip=CKV2_AWS_3:Single lab account, not an Organizations delegated admin
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_detector_feature" "s3" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "eks" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}

resource "aws_sns_topic" "security_alerts" {
  #checkov:skip=CKV_AWS_26:Alert text holds no sensitive data; KMS CMK used in production
  name = "${var.project}-security-alerts"
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridge"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.security_alerts.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "${var.project}-guardduty-high"
  description = "GuardDuty findings with severity 7+ (high/critical)"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail        = { severity = [{ numeric = [">=", 7] }] }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_high" {
  rule = aws_cloudwatch_event_rule.guardduty_high.name
  arn  = aws_sns_topic.security_alerts.arn
  input_transformer {
    input_paths = {
      sev   = "$.detail.severity"
      type  = "$.detail.type"
      title = "$.detail.title"
      id    = "$.detail.id"
    }
    input_template = "\"GuardDuty HIGH (<sev>): <type> - <title>. Finding ID <id>\""
  }
}

output "audit_trail_bucket" {
  value = aws_s3_bucket.trail.id
}

output "audit_log_group" {
  value = aws_cloudwatch_log_group.trail.name
}

output "security_alerts_topic_arn" {
  value = aws_sns_topic.security_alerts.arn
}
