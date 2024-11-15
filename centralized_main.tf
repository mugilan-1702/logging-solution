# Provider for Centralized Account
provider "aws" {
  alias  = "centralized_account"
  region = var.region
}

# Provider for Source Account
provider "aws" {
  alias  = "source_account"
  region = var.region
}

# Data for the current account identity in the Centralized Account
data "aws_caller_identity" "current" {
  provider = aws.centralized_account
}

# Check if the Kinesis Stream already exists
data "aws_kinesis_stream" "existing_log_stream" {
  provider = aws.centralized_account
  name     = "CrossAccountLogStream"
}

# Centralized Account Kinesis Stream
resource "aws_kinesis_stream" "log_stream" {
  provider    = aws.centralized_account
  name        = "CrossAccountLogStream"
  shard_count = 1

  count = length(data.aws_kinesis_stream.existing_log_stream) == 0 ? 1 : 0
}

# IAM Role for Firehose in Centralized Account (to allow receiving CloudWatch logs)
resource "aws_iam_role" "firehose_role_centralized" {
  provider = aws.centralized_account
  name     = "CentralizedAccountFirehoseRole"

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

# IAM policy for allowing Firehose role to write logs to the centralized log group
resource "aws_iam_role_policy" "firehose_policy_centralized" {
  provider = aws.centralized_account
  role     = aws_iam_role.firehose_role_centralized.name

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

# IAM Role for Firehose (allow source account to assume this role)
resource "aws_iam_role" "firehose_role" {
  provider = aws.centralized_account
  name     = "KinesisFirehoseRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          AWS = "arn:aws:iam::637423594986:root"  # source account
        },
        Action    = "sts:AssumeRole"
      },
      {
        Effect    = "Allow",
        Principal = { Service = "firehose.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# IAM Role Policy for Firehose
resource "aws_iam_role_policy" "firehose_policy" {
  provider = aws.centralized_account
  role     = aws_iam_role.firehose_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListShards"
        ],
        Resource = "arn:aws:kinesis:${var.region}:${data.aws_caller_identity.current.account_id}:stream/CrossAccountLogStream"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams"
        ],
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/CentralizedLogGroup:*"
      }
    ]
  })
}

# CloudWatch Log Group in Centralized Account
resource "aws_cloudwatch_log_group" "log_group_centralized" {
  provider          = aws.centralized_account
  name              = "/aws/kinesisfirehose/CentralizedLogGroup"
  retention_in_days = 14
}

# CloudWatch Log Stream for Firehose in Centralized Account
resource "aws_cloudwatch_log_stream" "log_stream" {
  provider       = aws.centralized_account
  log_group_name = aws_cloudwatch_log_group.log_group_centralized.name
  name           = "FirehoseLogStream"
}

# Check if the Firehose Delivery Stream already exists in Centralized Account
data "aws_kinesis_firehose_delivery_stream" "existing_firehose" {
  provider = aws.centralized_account
  name     = "KinesisToS3"
}

# Firehose Delivery Stream (only create if it does not exist)
resource "aws_kinesis_firehose_delivery_stream" "firehose_to_s3" {
  provider    = aws.centralized_account
  name        = "KinesisToS3"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    bucket_arn         = "arn:aws:s3:::testeks12"
    buffering_size     = 64
    buffering_interval = 60
    compression_format = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.log_group_centralized.name
      log_stream_name = aws_cloudwatch_log_stream.log_stream.name
    }

    prefix              = "data/!{timestamp:yyyy}/!{timestamp:MM}/!{timestamp:dd}/"
    error_output_prefix = "error_data/"
  }

  kinesis_source_configuration {
    kinesis_stream_arn = "arn:aws:kinesis:${var.region}:637423594986:stream/CrossAccountLogStream"
    role_arn           = aws_iam_role.firehose_role.arn
  }
}
