# Provider for the source account
provider "aws" {
  region     = var.region
  access_key = var.source_access_key
  secret_key = var.source_secret_key
}

# Provider for the centralized account
provider "aws" {
  alias      = "centralized_account"
  region     = var.region
  access_key = var.centralized_access_key
  secret_key = var.centralized_secret_key
}

# Data for centralized account's caller identity (optional, for debugging purposes)
data "aws_caller_identity" "centralized_account" {
  provider = aws.centralized_account
}

# CloudWatch log group in the source account
resource "aws_cloudwatch_log_group" "log_group_source" {
  provider          = aws
  name              = "/aws/kinesisfirehose/SourceLogGroup"
  retention_in_days = 14
}


# CloudWatch log group in the centralized account (for logging Firehose delivery)
resource "aws_cloudwatch_log_group" "log_group_centralized" {
  provider          = aws.centralized_account
  name              = "/aws/kinesisfirehose/CentralizedLogGroup"
  retention_in_days = 14
}

# CloudWatch log stream in the centralized account
resource "aws_cloudwatch_log_stream" "log_stream" {
  provider       = aws.centralized_account
  name           = "KinesisFirehoseLogStream"
  log_group_name = aws_cloudwatch_log_group.log_group_centralized.name
}

# Kinesis stream in the centralized account (instead of the source account)
resource "aws_kinesis_stream" "log_stream" {
  provider    = aws.centralized_account
  name        = "CrossAccountLogStream"
  shard_count = 1
}

# IAM role in the source account to allow CloudWatch Logs to be pushed to centralized account
resource "aws_iam_role" "firehose_role_source" {
  provider = aws
  name     = "SourceAccountFirehoseRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "firehose.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# IAM policy for allowing CloudWatch logs push from source to centralized account
resource "aws_iam_role_policy" "firehose_policy_source" {
  provider = aws
  role     = aws_iam_role.firehose_role_source.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:CreateLogGroup"
        ],
        Resource = "${aws_cloudwatch_log_group.log_group_centralized.arn}:*"
      }
    ]
  })
}


# Kinesis Firehose Delivery Stream in the Source Account (sending logs to centralized account)
resource "aws_kinesis_firehose_delivery_stream" "firehose_to_centralized" {
  provider    = aws
  name        = "SourceToCentralizedKinesisFirehose"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_role_source.arn
    bucket_arn         = "arn:aws:s3:::testeks12"  # Replace with your S3 bucket ARN
    buffering_size     = 64
    buffering_interval = 60
    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.log_group_centralized.name
      log_stream_name = "KinesisFirehoseCentralizedLogStream"
    }

    prefix              = "data/!{timestamp:yyyy}/!{timestamp:MM}/!{timestamp:dd}/"
    error_output_prefix = "error_data/"
  }

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.log_stream.arn  # Kinesis stream ARN from source account
    role_arn           = aws_iam_role.firehose_role_source.arn
  }
}
