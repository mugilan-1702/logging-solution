import base64
import json
import os
from datetime import datetime
import boto3
import logging
import gzip

logger = logging.getLogger()
logger.setLevel(logging.INFO)

firehose_client = boto3.client('firehose')

def handler(event, context):
    delivery_stream_name = os.environ.get('FIREHOSE_DELIVERY_STREAM')
    if not delivery_stream_name:
        logger.error("FIREHOSE_DELIVERY_STREAM environment variable is not set")
        return {
            'statusCode': 500,
            'body': json.dumps('Configuration error: Missing Firehose delivery stream name')
        }

    logger.info(f"Delivery stream name: {delivery_stream_name}")
    logger.info(f"Received event: {json.dumps(event)}")

    records_to_firehose = []

    if 'Records' in event:
        logger.info(f"Received {len(event['Records'])} records")
        for record in event['Records']:
            if 'kinesis' in record:
                payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
                logger.info(f"Decoded Kinesis payload: {payload}")
                process_record(payload, records_to_firehose)
            else:
                logger.warning(f"Unexpected record format: {json.dumps(record)}")
    elif 'awslogs' in event:
        # Handle CloudWatch Logs data
        compressed_payload = base64.b64decode(event['awslogs']['data'])
        uncompressed_payload = gzip.decompress(compressed_payload)
        payload = json.loads(uncompressed_payload)
        logger.info(f"Decoded CloudWatch Logs payload: {json.dumps(payload)}")
        for log_event in payload['logEvents']:
            process_record(json.dumps(log_event), records_to_firehose)
    else:
        logger.warning(f"Unexpected event format: {json.dumps(event)}")

    if records_to_firehose:
        send_to_firehose(delivery_stream_name, records_to_firehose)

    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed event')
    }

def process_record(payload, records_to_firehose):
    try:
        log_entry = json.loads(payload)
    except json.JSONDecodeError:
        log_entry = {"message": payload}

    log_entry['lambda_processed_at'] = datetime.utcnow().isoformat()

    firehose_record = {
        'Data': json.dumps(log_entry) + '\n'
    }
    records_to_firehose.append(firehose_record)

    if len(records_to_firehose) == 500:
        send_to_firehose(os.environ.get('FIREHOSE_DELIVERY_STREAM'), records_to_firehose)
        records_to_firehose.clear()

def send_to_firehose(delivery_stream_name, records):
    try:
        response = firehose_client.put_record_batch(
            DeliveryStreamName=delivery_stream_name,
            Records=records
        )
        logger.info(f"Sent {len(records)} records to Firehose. Failed: {response['FailedPutCount']}")
        if response['FailedPutCount'] > 0:
            logger.error(f"Failed to deliver {response['FailedPutCount']} records to Firehose")
    except Exception as e:
        logger.error(f"Error sending records to Firehose: {str(e)}")
