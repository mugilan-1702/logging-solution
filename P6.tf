source account:
provider "aws" {
  region     = var.region
  access_key = var.source_access_key
  secret_key = var.source_secret_key
  alias      = "source_account"
}

# CloudWatch Log Group in the Source Account
resource "aws_cloudwatch_log_group" "source_log_group" {
  provider = aws.source_account
  name     = "/aws/kinesisfirehose/SourceLogGroup"
}

# CloudWatch Log Resource Policy for Centralized Account
resource "aws_cloudwatch_log_resource_policy" "firehose_policy" {
  provider     = aws.source_account
  policy_name  = "CentralizedFirehoseLogPolicy"

  policy_document = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { "AWS": "590183916327" },  # Centralized account ID
        Action    = [
          "logs:PutLogEvents",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams"
        ],
        Resource  = "arn:aws:logs:${var.region}:637423594986:log-group:/aws/kinesisfirehose/SourceLogGroup:*"
      }
    ]
  })
}

# IAM Role for Source Account (with a unique name)
resource "aws_iam_role" "source_account_role" {
  provider = aws.source_account
  name     = "SourceAccountRole-${var.unique_identifier}"  # Unique name to avoid conflicts

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          AWS = "arn:aws:iam::590183916327:root"  # Centralized account ARN
        },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# IAM Role Policy for Source Account
resource "aws_iam_role_policy" "source_account_policy" {
  provider = aws.source_account
  role     = aws_iam_role.source_account_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "s3:PutObject",
        Resource = "arn:aws:s3:::testeks12-${var.unique_identifier}/*"  # Access to S3 bucket in centralized account
      }
    ]
  })
}

variable "unique_identifier" {
  default = "590183916327"  # Replace with your unique identifier
}

# IAM Policy for Source Account Log Access
resource "aws_iam_policy" "firehose_source_policy" {
  provider = aws.source_account
  name     = "SourceAccountFirehoseAccessPolicy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams"
        ],
        Resource = "arn:aws:logs:${var.region}:637423594986:log-group:/aws/kinesisfirehose/SourceLogGroup:*"
      }
    ]
  })
}

centralized account:
  # Provider configuration for the centralized account
  provider "aws" {
    region     = var.region
    access_key = var.centralized_access_key
    secret_key = var.centralized_secret_key
    alias      = "centralized_account"
  }

  # Provider configuration for the source account
  provider "aws" {
    region     = var.region
    access_key = var.source_access_key
    secret_key = var.source_secret_key
    alias      = "source_account"
  }

  resource "aws_cloudwatch_log_group" "centralized_logs_group" {
    provider = aws.centralized_account
    name     = "/aws/kinesisfirehose/CentralizedLogs"
  }

  resource "aws_cloudwatch_log_resource_policy" "firehose_policy" {
    provider     = aws.centralized_account
    policy_name  = "CentralizedFirehoseLogPolicy"

    policy_document = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect    = "Allow",
          Principal = { "AWS": "637423594986" },  # Use Account ID directly (no ARN)
          Action    = [
            "logs:PutLogEvents",
            "logs:CreateLogStream",
            "logs:DescribeLogStreams"
          ],
          Resource  = "arn:aws:logs:${var.region}:590183916327:log-group:/aws/kinesisfirehose/CentralizedLogs:*"
        }
      ]
    })
  }



  # IAM Role for Kinesis Firehose in the Centralized Account
  resource "aws_iam_role" "firehose_role_centralized" {
    provider = aws.centralized_account
    name     = "CentralizedFirehoseRole"

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

  # IAM Policy for Firehose Role to Write to S3
  resource "aws_iam_role_policy" "firehose_policy_centralized" {
    provider = aws.centralized_account
    role     = aws_iam_role.firehose_role_centralized.name

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect = "Allow",
          Action = [
            "s3:PutObject",
            "s3:GetBucketLocation",
            "s3:ListBucket",
            "s3:PutObjectAcl"
          ],
          Resource = "arn:aws:s3:::testeks12*"
        },
        {
          Effect = "Allow",
          Action = [
            "logs:PutLogEvents",
            "logs:CreateLogStream",
            "logs:DescribeLogStreams"
          ],
          Resource = "arn:aws:logs:${var.region}:590183916327:log-group:/aws/kinesisfirehose/CentralizedLogs:*"
        }
      ]
    })
  }

  resource "aws_s3_bucket" "logs_bucket" {
    provider = aws.centralized_account
    bucket   = "testeks12-${var.unique_identifier}" # Append unique identifier
  }

  variable "unique_identifier" {
    default = "590183916327" # Replace with a unique value, such as your AWS Account ID or another identifier
  }

  # S3 Bucket Versioning
  resource "aws_s3_bucket_versioning" "logs_bucket_versioning" {
    provider = aws.centralized_account
    bucket   = aws_s3_bucket.logs_bucket.id

    versioning_configuration {
      status = "Enabled"
    }
  }

  # IAM Role in the Source Account for Accessing Centralized S3 Bucket
  resource "aws_iam_role" "source_account_role" {
    provider = aws.source_account  # Provider for the source account
    name     = "SourceAccountRole"

    assume_role_policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect    = "Allow",
          Principal = {
            AWS = "arn:aws:iam::590183916327:root"  # Centralized account ARN
          },
          Action    = "sts:AssumeRole"
        }
      ]
    })
  }

  # Policy for Source Account Role to Allow Access to S3 Bucket
  resource "aws_iam_role_policy" "source_account_policy" {
    provider = aws.source_account
    role     = aws_iam_role.source_account_role.name

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect   = "Allow",
          Action   = "s3:PutObject",
          Resource = "arn:aws:s3:::testeks12-${var.unique_identifier}/*"  # Access to S3 bucket in centralized account
        }
      ]
    })
  }

  # S3 Bucket Policy (Optional, if needed for cross-account access)
  resource "aws_s3_bucket_policy" "logs_bucket_policy" {
    provider = aws.centralized_account
    bucket   = aws_s3_bucket.logs_bucket.id

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect    = "Allow",
          Principal = {
            AWS = "arn:aws:iam::637423594986:role/SourceAccountRole"  # Source account role ARN
          },
          Action    = "s3:PutObject",
          Resource  = "${aws_s3_bucket.logs_bucket.arn}/*"
        }
      ]
    })
  }

  # Kinesis Firehose Stream
  resource "aws_kinesis_firehose_delivery_stream" "firehose_stream" {
    provider    = aws.centralized_account
    name        = "CentralizedFirehoseStream"
    destination = "extended_s3"

    extended_s3_configuration {
      role_arn         = aws_iam_role.firehose_role_centralized.arn
      bucket_arn       = aws_s3_bucket.logs_bucket.arn
      buffering_size   = 5
      buffering_interval = 300

      cloudwatch_logging_options {
        enabled         = true
        log_group_name  = "/aws/kinesisfirehose/CentralizedLogs"
        log_stream_name = "firehose-delivery-stream"
      }
    }
  }


  resource "aws_iam_role" "lambda_execution_role" {
    provider = aws.centralized_account
    name     = "CentralizedLambdaExecutionRole"

    assume_role_policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect    = "Allow",
          Principal = { Service = "lambda.amazonaws.com" },
          Action    = "sts:AssumeRole"
        }
      ]
    })
  }

  resource "aws_iam_policy" "lambda_policy" {
    provider = aws.centralized_account
    name     = "LambdaS3AndCloudWatchPolicy"

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect = "Allow",
          Action = [
            "s3:GetObject",
            "s3:ListBucket"
          ],
          Resource = [
            "arn:aws:s3:::testeks12",
            "arn:aws:s3:::testeks12/*"
          ]
        },
        {
          Effect = "Allow",
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          Resource = "arn:aws:logs:${var.region}:590183916327:log-group:/aws/kinesisfirehose/CentralizedLogGroup:*"
        }
      ]
    })
  }

  resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
    provider   = aws.centralized_account
    role       = aws_iam_role.lambda_execution_role.name
    policy_arn = aws_iam_policy.lambda_policy.arn
  }

  resource "aws_lambda_function" "process_s3_logs" {
    provider = aws.centralized_account
    function_name = "ProcessS3Logs"
    runtime       = "python3.9"
    handler       = "lambda_function.lambda_handler"
    role          = aws_iam_role.lambda_execution_role.arn

    filename         = "lambda_function.zip"
    source_code_hash = filebase64sha256("lambda_function.zip")
  }

  resource "aws_s3_bucket_notification" "s3_bucket_notification" {
    provider = aws.centralized_account
    bucket   = aws_s3_bucket.logs_bucket.id

    lambda_function {
      lambda_function_arn = aws_lambda_function.process_s3_logs.arn
      events              = ["s3:ObjectCreated:*"]
    }
  }

  resource "aws_lambda_permission" "allow_s3" {
    provider = aws.centralized_account
    statement_id  = "AllowExecutionFromS3"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.process_s3_logs.function_name
    principal     = "s3.amazonaws.com"
    source_arn    = aws_s3_bucket.logs_bucket.arn
  }
