cenralized updated one:
# Centralized account resources
resource "aws_kinesis_stream" "centralized_log_stream" {
  provider         = aws.central_account
  name             = "centralized-log-stream"
  shard_count      = 1
  retention_period = 24

  tags = {
    Environment = "production"
  }
}

resource "aws_iam_role" "source_account_access" {
  provider = aws.central_account
  name     = "SourceAccountKinesisAccess"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.source_account_id}:root"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "kinesis_access" {
  provider = aws.central_account
  name     = "KinesisAccessPolicy"
  role     = aws_iam_role.source_account_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = aws_kinesis_stream.centralized_log_stream.arn
      }
    ]
  })
}

# In the centralized account configuration
resource "aws_cloudwatch_log_destination" "kinesis_destination" {
  name       = "kinesis-destination"
  role_arn   = aws_iam_role.cloudwatch_destination_role.arn
  target_arn = aws_kinesis_stream.centralized_log_stream.arn
}

resource "aws_iam_role" "cloudwatch_destination_role" {
  name = "cloudwatch-destination-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.region}.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudwatch_destination_policy" {
  role = aws_iam_role.cloudwatch_destination_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecordBatch"
        ]
        Resource = aws_kinesis_stream.centralized_log_stream.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_destination_policy" "kinesis_destination_policy" {
  destination_name = aws_cloudwatch_log_destination.kinesis_destination.name
  access_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.source_account_id
        }
        Action = "logs:PutSubscriptionFilter"
        Resource = aws_cloudwatch_log_destination.kinesis_destination.arn
      }
    ]
  })
}

resource "aws_lambda_function" "process_kinesis_logs" {
  provider      = aws.central_account
  filename      = "lambda_function.zip"
  function_name = "ProcessKinesisLogs"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.9"

  environment {
    variables = {
      FIREHOSE_DELIVERY_STREAM = aws_kinesis_firehose_delivery_stream.log_delivery_stream.name
    }
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  provider = aws.central_account
  name     = "LambdaKinesisToFirehoseRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_kinesis_firehose_policy" {
  provider = aws.central_account
  name     = "LambdaKinesisFirehosePolicy"
  role     = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.centralized_log_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.log_delivery_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_event_source_mapping" "kinesis_lambda_trigger" {
  provider           = aws.central_account
  event_source_arn   = aws_kinesis_stream.centralized_log_stream.arn
  function_name      = aws_lambda_function.process_kinesis_logs.arn
  starting_position  = "LATEST"
}

resource "aws_kinesis_firehose_delivery_stream" "log_delivery_stream" {
  provider    = aws.central_account
  name        = "CentralizedLogDeliveryStream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.log_storage.arn


    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_logs.name
      log_stream_name = "FirehoseDeliveryLogs"
    }
  }
}

resource "aws_iam_role" "firehose_role" {
  provider = aws.central_account
  name     = "FirehoseDeliveryRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "firehose_policy" {
  provider = aws.central_account
  name     = "FirehoseDeliveryPolicy"
  role     = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.log_storage.arn,
          "${aws_s3_bucket.log_storage.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = aws_cloudwatch_log_group.firehose_logs.arn
      }
    ]
  })
}

resource "aws_s3_bucket" "log_storage" {
  provider = aws.central_account
  bucket   = "centralized-log-storage-${var.unique_identifier}"
}

resource "aws_cloudwatch_log_group" "centralized_logs" {
  provider          = aws.central_account
  name              = "/aws/centralized/logs"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "firehose_logs" {
  provider          = aws.central_account
  name              = "/aws/kinesisfirehose/CentralizedLogs"
  retention_in_days = 7
}

